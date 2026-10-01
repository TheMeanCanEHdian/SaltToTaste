import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

import 'support/contract_goldens.dart';

/// The apply-to-all offer, driven through the REAL [NutritionCubit] and
/// [NutritionRepository] over the COMMITTED contract goldens — the real
/// server's `nutrition_matches` and `nutrition` bodies for the Bundt cake.
/// Only `others` is raised from the golden's 0 (one computed recipe cannot
/// have others) so that an offer can arise; the count is the server's own
/// field, in the server's own shape.
class _Adapter implements HttpClientAdapter {
  _Adapter({required this.others});

  final int others;

  /// Every PUT body, in order.
  final List<Map<String, dynamic>> puts = [];

  /// When set, the next PUT fails with a 500 envelope.
  bool failNextPut = false;

  /// When set, the next PUT is refused as the server refuses a line a save
  /// moved: 409 `line_moved`, naming where the line is now.
  bool lineMovedNextPut = false;

  /// How many times the rows were fetched (`GET …/nutrition/matches`).
  int matchGets = 0;

  /// Every PUT's path, in order (its last segment is the position).
  final List<String> putPaths = [];

  /// A save since the rows were read, as the recipe's line texts by position
  /// (null: the golden's own). Synthesized — a stated exception: only ever a
  /// reordering or a deletion of the golden's own real lines, no new text.
  List<String>? layout;

  /// When set, a PUT is guarded as the server guards it: a `raw` that is not
  /// the line now at the position is refused 409 `line_moved`.
  bool guard = false;

  /// When set, an apply_to_all PUT waits here before answering — a sweep
  /// held open so a test can act while it runs.
  Completer<void>? gate;

  Map<String, dynamic> _matches() {
    final body = golden('nutrition_matches');
    final raws = layout;
    return {
      'items': [
        for (final (at, item) in (body['items'] as List).indexed)
          if (raws == null || at < raws.length)
            {
              ...item as Map<String, dynamic>,
              if (raws != null) 'raw': raws[at],
              'others': others,
              // Distinct from `others` on purpose: two lines of one ingredient
              // in one recipe are 1 recipe but 2 lines.
              'others_lines': others == 0 ? 0 : others + 3,
            },
      ],
    };
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    const headers = {
      'content-type': ['application/json'],
    };
    final path = options.path;
    if (options.method == 'PUT' && path.contains('/nutrition/matches/')) {
      // The body arrives as a stream at this layer, not as options.data.
      final bytes = <int>[];
      await for (final chunk in requestStream!) {
        bytes.addAll(chunk);
      }
      final sent = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      puts.add(sent);
      putPaths.add(path);
      if (sent['apply_to_all'] == true && gate != null) {
        await gate!.future;
      }
      final at = int.parse(path.split('/').last);
      final now = [
        for (final item in _matches()['items'] as List)
          if ((item as Map)['position'] == at) item['raw'],
      ];
      if (lineMovedNextPut ||
          (guard && (now.isEmpty || sent['raw'] != now.single))) {
        lineMovedNextPut = false;
        return ResponseBody.fromString(
          jsonEncode({
            'error': {
              'code': 'line_moved',
              'message': 'That line has moved since it was read.',
              'request_id': 'req-test',
              'position': null,
            },
          }),
          409,
          headers: headers,
        );
      }
      if (failNextPut) {
        failNextPut = false;
        return ResponseBody.fromString(
          jsonEncode({
            'error': {
              'code': 'internal',
              'message': 'the server fell over',
              'request_id': 'req-test',
            },
          }),
          500,
          headers: headers,
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          ..._matches(),
          if (sent['apply_to_all'] == true)
            'applied': {
              'recipes': others,
              'lines': others + 3,
              'failed': 0,
              'completed': others ~/ 3,
              'completed_recipes': [
                for (var i = 0; i < others ~/ 3; i++) 'recipe-$i',
              ],
            },
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/nutrition/matches')) {
      matchGets++;
      return ResponseBody.fromString(
        jsonEncode(_matches()),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/nutrition')) {
      return ResponseBody.fromString(
        jsonEncode(golden('nutrition')),
        200,
        headers: headers,
      );
    }
    return ResponseBody.fromString('{}', 404, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late NutritionCubit cubit;

  Future<void> boot({required int others}) async {
    adapter = _Adapter(others: others);
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    cubit = NutritionCubit(
      NutritionRepository(dio),
      'rich-chocolate-bundt-cake',
    );
    addTearDown(cubit.close);
    await cubit.loadMatches();
    await pumpEventQueue();
  }

  /// The golden's flour line — a real matched line with an item.
  IngredientMatch flour() =>
      cubit.state.matches!.firstWhere((m) => (m.item ?? '').contains('flour'));

  test('a pick raises the offer, sized and named by the server', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, fdcId: 123456);
    await pumpEventQueue();
    expect(cubit.state.offer, (
      position: line.position,
      raw: line.raw,
      label: itemLabel(line.item)!,
      fdcId: 123456,
      confirmed: false,
      grams: null,
      others: 41,
      lines: 44,
    ));
    expect(cubit.state.applied, isNull);
  });

  test('a confirm carries the same two counts: lines and recipes', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, confirmed: true);
    await pumpEventQueue();
    expect(cubit.state.offer!.lines, 44);
    expect(cubit.state.offer!.others, 41);
  });

  test('re-picking the food the line already had still offers', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, fdcId: line.fdcId);
    await pumpEventQueue();
    expect(line.fdcId, isNotNull, reason: 'the golden line is matched');
    expect(cubit.state.offer!.lines, 44);
  });

  test('applying resends the same decision with apply_to_all and shows the '
      "server's receipt in the offer's place", () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, fdcId: 123456);
    await pumpEventQueue();
    adapter.puts.clear();

    await cubit.applyToAll();
    await pumpEventQueue();

    expect(adapter.puts, [
      {'raw': line.raw, 'fdc_id': 123456, 'apply_to_all': true},
    ]);
    expect(cubit.state.offer, isNull);
    final applied = cubit.state.applied!;
    expect(
      (
        applied.position,
        applied.recipes,
        applied.lines,
        applied.failed,
        applied.completed,
      ),
      // The server's `applied.completed` reaches the receipt.
      (line.position, 41, 44, 0, 13),
    );
    // …and which recipes: the queue names a shortfall against its promise.
    expect(applied.completedRecipes, hasLength(13));
    expect(applied.completedRecipes.first, 'recipe-0');
    expect(cubit.state.applying, isFalse);

    cubit.dismissApply();
    expect(cubit.state.applied, isNull);
  });

  test('a confirm resends confirmed, not a food id', () async {
    await boot(others: 7);
    final line = flour();
    await cubit.override(line.position, confirmed: true);
    await pumpEventQueue();
    expect(cubit.state.offer?.confirmed, isTrue);
    expect(cubit.state.offer?.fdcId, isNull);
    adapter.puts.clear();
    await cubit.applyToAll();
    await pumpEventQueue();
    expect(adapter.puts, [
      {'raw': line.raw, 'confirmed': true, 'apply_to_all': true},
    ]);
  });

  test('no offer for a skip, a grams-only change, or when nothing would '
      'change', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, skipped: true);
    await pumpEventQueue();
    expect(cubit.state.offer, isNull, reason: 'a skip is not a decision');
    await cubit.override(line.position, grams: 12);
    await pumpEventQueue();
    expect(cubit.state.offer, isNull, reason: 'grams alone pick nothing');

    await boot(others: 0);
    await cubit.override(flour().position, fdcId: 123456);
    await pumpEventQueue();
    expect(cubit.state.offer, isNull, reason: 'every other line is on it');
  });

  test('the offer names the item as a person would', () {
    expect(itemLabel('(1 1/2 sticks) unsalted butter'), 'unsalted butter');
    expect(
      itemLabel('instant espresso powder (optional)'),
      'instant espresso powder',
    );
    expect(itemLabel('(optional)'), isNull);
    expect(itemLabel(null), isNull);
  });

  test('the amount typed with the pick travels with the apply', () async {
    // "Save match & amount" sends fdc_id AND grams in one PUT; the resend
    // must carry both, or the server recomputes this line's grams from the
    // estimate and the typed amount is gone.
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, fdcId: 123456, grams: 250);
    await pumpEventQueue();
    expect(cubit.state.offer?.grams, 250);
    adapter.puts.clear();
    await cubit.applyToAll();
    await pumpEventQueue();
    expect(adapter.puts, [
      {'raw': line.raw, 'fdc_id': 123456, 'grams': 250, 'apply_to_all': true},
    ]);
  });

  test('a decision on another row while an apply runs keeps ITS offer; the '
      'receipt lands for the applied row', () async {
    await boot(others: 41);
    final a = flour();
    final b = cubit.state.matches!.firstWhere(
      (m) => m.position != a.position && m.fdcId != null,
    );
    await cubit.override(a.position, fdcId: 123456);
    await pumpEventQueue();
    adapter.gate = Completer<void>();
    final sweep = cubit.applyToAll();
    await pumpEventQueue();
    expect(cubit.state.applying, isTrue);

    await cubit.override(b.position, confirmed: true);
    await pumpEventQueue();
    expect(cubit.state.offer?.position, b.position);

    adapter.gate!.complete();
    await sweep;
    await pumpEventQueue();
    expect(cubit.state.offer?.position, b.position, reason: 'B stands');
    expect(cubit.state.applied?.position, a.position);
  });

  test('a second tap while applying is a no-op', () async {
    await boot(others: 41);
    await cubit.override(flour().position, fdcId: 123456);
    await pumpEventQueue();
    adapter.puts.clear();
    adapter.gate = Completer<void>();
    final first = cubit.applyToAll();
    await pumpEventQueue();
    await cubit.applyToAll(); // ignored
    adapter.gate!.complete();
    await first;
    await pumpEventQueue();
    expect(adapter.puts, hasLength(1));
  });

  test('the next decision clears a shown receipt', () async {
    await boot(others: 41);
    final a = flour();
    await cubit.override(a.position, fdcId: 123456);
    await pumpEventQueue();
    await cubit.applyToAll();
    await pumpEventQueue();
    expect(cubit.state.applied, isNotNull);
    final b = cubit.state.matches!.firstWhere((m) => m.position != a.position);
    await cubit.override(b.position, skipped: true);
    await pumpEventQueue();
    expect(cubit.state.applied, isNull);
  });

  test('dismissing a failed apply clears its error too', () async {
    await boot(others: 41);
    await cubit.override(flour().position, fdcId: 123456);
    await pumpEventQueue();
    adapter.failNextPut = true;
    await cubit.applyToAll();
    await pumpEventQueue();
    expect(cubit.state.error, isNotNull);
    cubit.dismissApply();
    expect(cubit.state.error, isNull, reason: 'the queue must not stall');
    expect(cubit.state.offer, isNull);
  });

  test('a failed apply keeps the offer and says why', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, fdcId: 123456);
    await pumpEventQueue();
    adapter.failNextPut = true;
    await cubit.applyToAll();
    await pumpEventQueue();
    expect(cubit.state.offer, isNotNull, reason: 'retry or decline');
    expect(cubit.state.applied, isNull);
    expect(cubit.state.applying, isFalse);
    // The app words a 500 for people; the point is that it is SAID.
    expect(cubit.state.error, isNotEmpty);
  });

  // Run 050 P4: the line's text travels with every write; a save since
  // that moved the line is refused (409 line_moved) and the rows reload.
  test('a write sends the line text it was made on', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, raw: line.raw, fdcId: 123456);
    await pumpEventQueue();
    expect(adapter.puts.single, containsPair('raw', line.raw));
    await cubit.applyToAll();
    await pumpEventQueue();
    expect(adapter.puts.last, containsPair('raw', line.raw));
    expect(adapter.puts.last, containsPair('apply_to_all', true));
  });

  test('a line_moved refusal says so, writes nothing and reloads the rows '
      'so the screen finds the line where it is now', () async {
    await boot(others: 41);
    final line = flour();
    final gets = adapter.matchGets;
    adapter.lineMovedNextPut = true;
    await cubit.override(line.position, raw: line.raw, skipped: true);
    await pumpEventQueue();
    expect(adapter.matchGets, gets + 1);
    expect(cubit.state.error, contains('moved'));
    expect(cubit.state.overridingPosition, isNull);
    expect(cubit.state.offer, isNull);
  });

  // Run 051 A1: the offer carries the text of the line it was raised on.
  // A save between the offer and the Apply tap refuses the first send; the
  // retry must name the SAME line, where it is now — never the line a save
  // put at the offer's old position (the food then landed on another
  // ingredient library-wide).
  group('A1: the offer follows its own line', () {
    /// The golden's lines as a save left them: the last line moved to the
    /// top, every other line one down.
    List<String> lastLineMovedToTop() {
      final raws = [for (final m in cubit.state.matches!) m.raw];
      return [raws.last, ...raws.take(raws.length - 1)];
    }

    test('the retry after line_moved sends the offer line text at the '
        'position that line moved to, and lands', () async {
      await boot(others: 41);
      final line = flour();
      await cubit.override(line.position, raw: line.raw, fdcId: 123456);
      await pumpEventQueue();
      expect(cubit.state.offer?.raw, line.raw);
      adapter
        ..layout = lastLineMovedToTop()
        ..guard = true;
      adapter.puts.clear();
      await cubit.applyToAll();
      await pumpEventQueue();
      expect(cubit.state.error, contains('moved'));
      // Re-located by its text, one down.
      expect(cubit.state.offer?.position, line.position + 1);
      expect(cubit.state.offer?.raw, line.raw);
      await cubit.applyToAll();
      await pumpEventQueue();
      expect(adapter.puts.last['raw'], line.raw);
      expect(adapter.putPaths.last, endsWith('/${line.position + 1}'));
      expect(adapter.puts.last['fdc_id'], 123456);
      expect(cubit.state.applied?.position, line.position + 1);
      expect(cubit.state.offer, isNull);
    });

    test('an offer whose line a save removed is withdrawn, and the message '
        'says why; nothing more is sent', () async {
      await boot(others: 41);
      final line = flour();
      await cubit.override(line.position, raw: line.raw, fdcId: 123456);
      await pumpEventQueue();
      adapter
        ..layout = [
          for (final m in cubit.state.matches!)
            if (m.position != line.position) m.raw,
        ]
        ..guard = true;
      adapter.puts.clear();
      await cubit.applyToAll();
      await pumpEventQueue();
      expect(adapter.puts.single['raw'], line.raw);
      expect(cubit.state.offer, isNull);
      expect(cubit.state.error, contains('withdrawn'));
      expect(cubit.state.error, contains('moved'));
      await cubit.applyToAll();
      await pumpEventQueue();
      expect(adapter.puts, hasLength(1));
    });

    test(
      "an override's line_moved reload re-locates a pending offer too",
      () async {
        await boot(others: 41);
        final line = flour();
        await cubit.override(line.position, raw: line.raw, fdcId: 123456);
        await pumpEventQueue();
        final other = cubit.state.matches!.first;
        adapter
          ..layout = lastLineMovedToTop()
          ..guard = true;
        await cubit.override(other.position, raw: other.raw, skipped: true);
        await pumpEventQueue();
        expect(cubit.state.offer?.position, line.position + 1);
      },
    );

    test('a retry reload of the rows (the Retry button) re-locates the '
        'offer too, so the apply lands on its line in one send', () async {
      await boot(others: 41);
      final line = flour();
      await cubit.override(line.position, raw: line.raw, fdcId: 123456);
      await pumpEventQueue();
      adapter
        ..layout = lastLineMovedToTop()
        ..guard = true;
      adapter.puts.clear();
      await cubit.loadMatches(force: true);
      await pumpEventQueue();
      expect(cubit.state.offer?.position, line.position + 1);
      await cubit.applyToAll();
      await pumpEventQueue();
      expect(adapter.puts.single['raw'], line.raw);
      expect(adapter.putPaths.last, endsWith('/${line.position + 1}'));
      expect(cubit.state.applied?.position, line.position + 1);
    });

    test('offerOnReload keeps, moves, or withdraws by text alone', () {
      const offer = (
        position: 6,
        raw: '1¾ cups (8¾ ounces) unbleached all-purpose flour',
        label: 'unbleached all-purpose flour',
        fdcId: 123456,
        confirmed: false,
        grams: null,
        others: 41,
        lines: 44,
      );
      IngredientMatch row(int position, String raw) =>
          IngredientMatch(position: position, raw: raw);
      const salt = '1 teaspoon table salt';
      expect(offerOnReload(offer, [row(6, offer.raw)]), offer);
      expect(
        offerOnReload(offer, [row(6, salt), row(7, offer.raw)])?.position,
        7,
      );
      expect(offerOnReload(offer, [row(6, salt)]), isNull);
      // Twins, neither at the position: which one it was is unknowable.
      expect(
        offerOnReload(offer, [
          row(5, offer.raw),
          row(6, salt),
          row(7, offer.raw),
        ]),
        isNull,
      );
      // The banner: the row at the position that still reads the text.
      expect(offerIsFor(offer, row(6, offer.raw)), isTrue);
      expect(offerIsFor(offer, row(6, salt)), isFalse);
      expect(offerIsFor(offer, row(7, offer.raw)), isFalse);
    });
  });
}
