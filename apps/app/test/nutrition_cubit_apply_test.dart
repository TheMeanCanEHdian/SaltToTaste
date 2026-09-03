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

  /// When set, an apply_to_all PUT waits here before answering — a sweep
  /// held open so a test can act while it runs.
  Completer<void>? gate;

  Map<String, dynamic> _matches() {
    final body = golden('nutrition_matches');
    return {
      'items': [
        for (final item in body['items'] as List)
          {...item as Map<String, dynamic>, 'others': others},
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
      if (sent['apply_to_all'] == true && gate != null) {
        await gate!.future;
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
            'applied': {'recipes': others, 'lines': others + 3, 'failed': 0},
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/nutrition/matches')) {
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

  test('a pick whose food others are not on raises the offer, sized and '
      'named by the server', () async {
    await boot(others: 41);
    final line = flour();
    await cubit.override(line.position, fdcId: 123456);
    await pumpEventQueue();
    expect(cubit.state.offer, (
      position: line.position,
      label: itemLabel(line.item)!,
      fdcId: 123456,
      confirmed: false,
      grams: null,
      others: 41,
    ));
    expect(cubit.state.applied, isNull);
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
      {'fdc_id': 123456, 'apply_to_all': true},
    ]);
    expect(cubit.state.offer, isNull);
    expect(cubit.state.applied, (
      position: line.position,
      recipes: 41,
      lines: 44,
      failed: 0,
    ));
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
      {'confirmed': true, 'apply_to_all': true},
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
      {'fdc_id': 123456, 'grams': 250, 'apply_to_all': true},
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
}
