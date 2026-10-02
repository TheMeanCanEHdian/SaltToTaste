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

  /// The receipt's `moved` (targets left because their recipe was laid out
  /// anew meanwhile). Synthesized — a stated exception: the race that sets
  /// it cannot be staged against a fake; the field is the server's own.
  int moved = 0;

  /// The receipt's other reasons (`decided`, `gone`, `failed_lines`) —
  /// synthesized for the same reason as [moved].
  ({int decided, int gone, int failedLines}) reasons = (
    decided: 0,
    gone: 0,
    failedLines: 0,
  );

  /// When set, an apply_to_all PUT answers WITHOUT its `applied` block, as
  /// the server does when the decision had no food to apply (the route
  /// omits the key for a null `AppliedToOthers`). Synthesized — a stated
  /// exception: the fake cannot stage the server's reason.
  bool noApplied = false;

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
          if (sent['apply_to_all'] == true && !noApplied)
            'applied': {
              'recipes': others,
              'lines': others + 3,
              'failed': 0,
              'completed': others ~/ 3,
              'completed_recipes': [
                for (var i = 0; i < others ~/ 3; i++) 'recipe-$i',
              ],
              'moved': moved,
              'decided': reasons.decided,
              'gone': reasons.gone,
              'failed_lines': reasons.failedLines,
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

  /// The golden's lines as a save left them: the last line moved to the
  /// top, every other line one down.
  List<String> lastLineMovedToTop() {
    final raws = [for (final m in cubit.state.matches!) m.raw];
    return [raws.last, ...raws.take(raws.length - 1)];
  }

  test('a pick raises the offer, sized and named by the server', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, raw: line.raw, fdcId: 123456);
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
    await cubit.override(line.position, raw: line.raw, confirmed: true);
    await pumpEventQueue();
    expect(cubit.state.offer!.lines, 44);
    expect(cubit.state.offer!.others, 41);
  });

  test('re-picking the food the line already had still offers', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, raw: line.raw, fdcId: line.fdcId);
    await pumpEventQueue();
    expect(line.fdcId, isNotNull, reason: 'the golden line is matched');
    expect(cubit.state.offer!.lines, 44);
  });

  test('applying resends the same decision with apply_to_all and shows the '
      "server's receipt in the offer's place", () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, raw: line.raw, fdcId: 123456);
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

    cubit.dismissReceipt();
    expect(cubit.state.applied, isNull);
  });

  test('a confirm resends confirmed, not a food id', () async {
    await boot(others: 7);
    final line = flour();
    await cubit.override(line.position, raw: line.raw, confirmed: true);
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
    await cubit.override(line.position, raw: line.raw, skipped: true);
    await pumpEventQueue();
    expect(cubit.state.offer, isNull, reason: 'a skip is not a decision');
    await cubit.override(line.position, raw: line.raw, grams: 12);
    await pumpEventQueue();
    expect(cubit.state.offer, isNull, reason: 'grams alone pick nothing');

    await boot(others: 0);
    await cubit.override(flour().position, raw: flour().raw, fdcId: 123456);
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
    await cubit.override(
      line.position,
      raw: line.raw,
      fdcId: 123456,
      grams: 250,
    );
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
    await cubit.override(a.position, raw: a.raw, fdcId: 123456);
    await pumpEventQueue();
    adapter.gate = Completer<void>();
    final sweep = cubit.applyToAll();
    await pumpEventQueue();
    expect(cubit.state.applying, isTrue);

    await cubit.override(b.position, raw: b.raw, confirmed: true);
    await pumpEventQueue();
    expect(cubit.state.offer?.position, b.position);

    adapter.gate!.complete();
    await sweep;
    await pumpEventQueue();
    expect(cubit.state.offer?.position, b.position, reason: 'B stands');
    expect(cubit.state.applied?.position, a.position);
  });

  test("Run 052 O7/S6: the newer offer is placed by its text on the apply's "
      'answer, as the receipt is', () async {
    await boot(others: 41);
    final a = flour();
    final b = cubit.state.matches!.firstWhere(
      (m) => m.position != a.position && m.fdcId != null,
    );
    await cubit.override(a.position, raw: a.raw, fdcId: 123456);
    await pumpEventQueue();
    adapter.gate = Completer<void>();
    final sweep = cubit.applyToAll();
    await pumpEventQueue();
    await cubit.override(b.position, raw: b.raw, confirmed: true);
    await pumpEventQueue();
    // A save lands before the apply answers: every line one down.
    adapter.layout = lastLineMovedToTop();
    adapter.gate!.complete();
    await sweep;
    await pumpEventQueue();
    expect(cubit.state.offer?.position, b.position + 1);
    expect(cubit.state.offer?.raw, b.raw);
    expect(cubit.state.applied?.position, a.position + 1);
  });

  test('Run 052 O7/S6: a newer offer whose line the apply\'s answer no '
      'longer has is withdrawn, and the message says so', () async {
    await boot(others: 41);
    final a = flour();
    final b = cubit.state.matches!.firstWhere(
      (m) => m.position != a.position && m.fdcId != null,
    );
    await cubit.override(a.position, raw: a.raw, fdcId: 123456);
    await pumpEventQueue();
    adapter.gate = Completer<void>();
    final sweep = cubit.applyToAll();
    await pumpEventQueue();
    await cubit.override(b.position, raw: b.raw, confirmed: true);
    await pumpEventQueue();
    // A save removes b's line before the apply answers.
    adapter.layout = [
      for (final m in cubit.state.matches!)
        if (m.position != b.position) m.raw,
    ];
    adapter.gate!.complete();
    await sweep;
    await pumpEventQueue();
    expect(cubit.state.offer, isNull);
    expect(cubit.state.error, contains('withdrawn'));
  });

  // Run 053 S16: a newer offer stands beside the first apply's receipt; an
  // apply of it whose answer has no `applied` must clear that OLD receipt —
  // left up, it would read as this apply's.
  test('S16: an apply answered without a receipt clears the receipt '
      'still shown from the apply before', () async {
    await boot(others: 41);
    final a = flour();
    final b = cubit.state.matches!.firstWhere(
      (m) => m.position != a.position && m.fdcId != null,
    );
    await cubit.override(a.position, raw: a.raw, fdcId: 123456);
    await pumpEventQueue();
    adapter.gate = Completer<void>();
    final sweep = cubit.applyToAll();
    await pumpEventQueue();
    await cubit.override(b.position, raw: b.raw, confirmed: true);
    await pumpEventQueue();
    adapter.gate!.complete();
    adapter.gate = null;
    await sweep;
    await pumpEventQueue();
    expect(cubit.state.applied?.raw, a.raw);
    expect(cubit.state.offer?.raw, b.raw);
    adapter.noApplied = true;
    await cubit.applyToAll();
    await pumpEventQueue();
    expect(adapter.puts.last['apply_to_all'], isTrue);
    expect(cubit.state.applied, isNull);
    expect(cubit.state.offer, isNull);
  });

  // Run 054 S8: a receipt and a newer offer coexist (the `newer` path
  // above); Dismiss on the receipt — here the unanchored one, whose line a
  // save removed — drops only the receipt, never offer B.
  test(
    'S8: dismissing a receipt keeps a pending offer for another line',
    () async {
      await boot(others: 41);
      final a = flour();
      final b = cubit.state.matches!.firstWhere(
        (m) => m.position != a.position && m.fdcId != null,
      );
      await cubit.override(a.position, raw: a.raw, fdcId: 123456);
      await pumpEventQueue();
      adapter.gate = Completer<void>();
      final sweep = cubit.applyToAll();
      await pumpEventQueue();
      await cubit.override(b.position, raw: b.raw, confirmed: true);
      await pumpEventQueue();
      adapter.layout = [
        for (final m in cubit.state.matches!)
          if (m.position != a.position) m.raw,
      ];
      adapter.gate!.complete();
      adapter.gate = null;
      await sweep;
      await pumpEventQueue();
      expect(cubit.state.applied, isNotNull);
      expect(cubit.state.applied!.position, isNull);
      final offerB = cubit.state.offer;
      expect(offerB?.raw, b.raw);
      cubit.dismissReceipt();
      expect(cubit.state.applied, isNull);
      expect(
        cubit.state.offer,
        offerB,
        reason: 'offer B survives Dismiss of A',
      );
      // …and "Not now" on offer B leaves nothing behind.
      cubit.dismissOffer();
      expect(cubit.state.offer, isNull);
    },
  );

  // S8's other arm: offer B's line is gone from the answer too, so B is
  // withdrawn and its message stands beside A's receipt with no offer
  // open. Dismissing the receipt clears that message — nothing open owns
  // it, and kept it holds the admin queue (queueShouldAdvance).
  test('S8: dismissing a receipt with no offer open clears a withdrawn '
      "offer's message", () async {
    await boot(others: 41);
    final a = flour();
    final b = cubit.state.matches!.firstWhere(
      (m) => m.position != a.position && m.fdcId != null,
    );
    await cubit.override(a.position, raw: a.raw, fdcId: 123456);
    await pumpEventQueue();
    adapter.gate = Completer<void>();
    final sweep = cubit.applyToAll();
    await pumpEventQueue();
    await cubit.override(b.position, raw: b.raw, confirmed: true);
    await pumpEventQueue();
    adapter.layout = [
      for (final m in cubit.state.matches!)
        if (m.position != a.position && m.position != b.position) m.raw,
    ];
    adapter.gate!.complete();
    adapter.gate = null;
    await sweep;
    await pumpEventQueue();
    expect(cubit.state.applied, isNotNull);
    expect(cubit.state.offer, isNull);
    expect(cubit.state.error, contains('was withdrawn'));
    cubit.dismissReceipt();
    expect(cubit.state.applied, isNull);
    expect(cubit.state.error, isNull);
  });

  test("F7: the receipt carries the server's moved, decided, gone and "
      'failed_lines counts', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, raw: line.raw, fdcId: 123456);
    await pumpEventQueue();
    adapter
      ..moved = 2
      ..reasons = (decided: 3, gone: 4, failedLines: 5);
    await cubit.applyToAll();
    await pumpEventQueue();
    final a = cubit.state.applied;
    expect((a?.moved, a?.decided, a?.gone, a?.failedLines), (2, 3, 4, 5));
  });

  test('a second tap while applying is a no-op', () async {
    await boot(others: 41);
    await cubit.override(flour().position, raw: flour().raw, fdcId: 123456);
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
    await cubit.override(a.position, raw: a.raw, fdcId: 123456);
    await pumpEventQueue();
    await cubit.applyToAll();
    await pumpEventQueue();
    expect(cubit.state.applied, isNotNull);
    final b = cubit.state.matches!.firstWhere((m) => m.position != a.position);
    await cubit.override(b.position, raw: b.raw, skipped: true);
    await pumpEventQueue();
    expect(cubit.state.applied, isNull);
  });

  test('dismissing a failed apply clears its error too', () async {
    await boot(others: 41);
    await cubit.override(flour().position, raw: flour().raw, fdcId: 123456);
    await pumpEventQueue();
    adapter.failNextPut = true;
    await cubit.applyToAll();
    await pumpEventQueue();
    expect(cubit.state.error, isNotNull);
    cubit.dismissOffer();
    expect(cubit.state.error, isNull, reason: 'the queue must not stall');
    expect(cubit.state.offer, isNull);
  });

  test('a failed apply keeps the offer and says why', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, raw: line.raw, fdcId: 123456);
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

    // Run 052 O7/S6: the response to a PUT is read after the server's
    // awaits, so a save in them can stand another line at the position.
    test('the offer is raised on the line the person SENT, found by its '
        'text in the answer, and the apply sends that text', () async {
      await boot(others: 41);
      final line = flour();
      adapter.layout = lastLineMovedToTop();
      await cubit.override(line.position, raw: line.raw, fdcId: 123456);
      await pumpEventQueue();
      expect(cubit.state.offer?.raw, line.raw);
      expect(cubit.state.offer?.position, line.position + 1);
      adapter
        ..guard = true
        ..puts.clear();
      await cubit.applyToAll();
      await pumpEventQueue();
      expect(adapter.puts.single['raw'], line.raw);
      expect(adapter.putPaths.last, endsWith('/${line.position + 1}'));
      expect(cubit.state.error, isNull);
      expect(cubit.state.applied?.raw, line.raw);
    });

    test('no offer when no row of the answer reads the sent text', () async {
      await boot(others: 41);
      final line = flour();
      adapter.layout = [
        for (final m in cubit.state.matches!)
          if (m.position != line.position) m.raw,
      ];
      await cubit.override(line.position, raw: line.raw, fdcId: 123456);
      await pumpEventQueue();
      expect(cubit.state.offer, isNull);
    });

    test("the receipt stands where the apply's answer has its line, and a "
        'reload moves it by text', () async {
      await boot(others: 41);
      final line = flour();
      await cubit.override(line.position, raw: line.raw, fdcId: 123456);
      await pumpEventQueue();
      // The save lands while the apply runs: its answer has the line one
      // down (unguarded: the apply's own write was guarded before it).
      adapter.layout = lastLineMovedToTop();
      adapter.gate = Completer<void>();
      final apply = cubit.applyToAll();
      await pumpEventQueue();
      adapter.gate!.complete();
      await apply;
      expect(cubit.state.applied?.position, line.position + 1);
      expect(cubit.state.applied?.raw, line.raw);
      // A further save puts it back; the reload follows it.
      adapter.layout = null;
      await cubit.loadMatches(force: true);
      await pumpEventQueue();
      expect(cubit.state.applied?.position, line.position);
      // Removed (a synthesized deletion of the golden's own line — the
      // stated exception): the receipt STAYS, unanchored, its counts whole
      // (Run 053 O17: it reports what the apply wrote library-wide).
      final shown = cubit.state.applied!;
      adapter.layout = [
        for (final m in cubit.state.matches!)
          if (m.position != line.position) m.raw,
      ];
      await cubit.loadMatches(force: true);
      await pumpEventQueue();
      expect(cubit.state.applied?.position, isNull);
      expect(cubit.state.applied?.raw, line.raw);
      expect(
        (cubit.state.applied?.recipes, cubit.state.applied?.lines),
        (shown.recipes, shown.lines),
      );
      // The line back: an unanchored receipt stays unanchored (which twin or
      // position it was is no longer known); a dismiss clears it.
      adapter.layout = null;
      await cubit.loadMatches(force: true);
      await pumpEventQueue();
      expect(cubit.state.applied?.position, isNull);
      cubit.dismissReceipt();
      expect(cubit.state.applied, isNull);
    });

    // Run 053 O17 (the digest's repro): a save removes the acted-on line
    // while the apply runs — the answer has no row reading it. The receipt
    // and every reason count still reach the person, unanchored, and no
    // error claims the apply failed.
    test('O17: the receipt of an apply whose line a save removed meanwhile '
        'is kept, unanchored, with every count', () async {
      await boot(others: 41);
      final line = flour();
      await cubit.override(line.position, raw: line.raw, fdcId: 123456);
      await pumpEventQueue();
      adapter
        ..moved = 2
        ..reasons = (decided: 3, gone: 4, failedLines: 5);
      adapter.gate = Completer<void>();
      final apply = cubit.applyToAll();
      await pumpEventQueue();
      adapter.layout = [
        for (final m in cubit.state.matches!)
          if (m.position != line.position) m.raw,
      ];
      adapter.gate!.complete();
      await apply;
      await pumpEventQueue();
      final a = cubit.state.applied;
      expect(a, isNotNull);
      expect(a!.position, isNull);
      expect(a.raw, line.raw);
      expect(
        (a.recipes, a.lines, a.moved, a.decided, a.gone, a.failedLines),
        (41, 44, 2, 3, 4, 5),
      );
      expect(cubit.state.offer, isNull);
      expect(cubit.state.applying, isFalse);
      expect(cubit.state.error, isNull);
    });

    // The same window for a pending OFFER: a reload that no longer has its
    // line withdraws it, and the message names why — the line is no longer
    // in the recipe as it was.
    test('O17: an offer whose line a reload no longer has is withdrawn, and '
        'the message names the line and why', () async {
      await boot(others: 41);
      final line = flour();
      await cubit.override(line.position, raw: line.raw, fdcId: 123456);
      await pumpEventQueue();
      adapter.layout = [
        for (final m in cubit.state.matches!)
          if (m.position != line.position) m.raw,
      ];
      await cubit.loadMatches(force: true);
      await pumpEventQueue();
      expect(cubit.state.offer, isNull);
      expect(
        cubit.state.error,
        'The apply-to-all offer for "${line.raw}" was withdrawn: that line '
        'is no longer in the recipe as it was.',
      );
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
      // S15: twins, one AT the position — the offer stays where it stands
      // (which twin it was is known), never withdrawn.
      expect(
        offerOnReload(offer, [row(5, offer.raw), row(6, offer.raw)]),
        offer,
      );
      expect(
        rowReading(
          [row(6, offer.raw), row(7, offer.raw)],
          offer.raw,
          7,
        )?.position,
        7,
      );
      // The receipt is placed by the same rule, and shown only under the row
      // at its position that reads its text.
      final receipt = (
        position: 6,
        raw: offer.raw,
        recipes: 1,
        lines: 1,
        failed: 0,
        completed: 0,
        completedRecipes: const <String>[],
        moved: 0,
        decided: 0,
        gone: 0,
        failedLines: 0,
      );
      expect(
        receiptOnReload(receipt, [row(6, salt), row(7, offer.raw)]).position,
        7,
      );
      // O17: unplaceable — gone, or twins neither at its position — it is
      // kept unanchored (position null), counts whole, and is under no row.
      for (final rows in [
        [row(6, salt)],
        [row(5, offer.raw), row(7, offer.raw)],
      ]) {
        final kept = receiptOnReload(receipt, rows);
        expect(kept.position, isNull);
        expect((kept.raw, kept.recipes, kept.lines), (offer.raw, 1, 1));
        expect(rows.any((m) => receiptIsFor(kept, m)), isFalse);
      }
      expect(receiptIsFor(receipt, row(6, offer.raw)), isTrue);
      expect(receiptIsFor(receipt, row(6, salt)), isFalse);
      expect(receiptIsFor(receipt, row(7, offer.raw)), isFalse);
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
