import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/nutrition/provider.dart';

/// A provider backed by RECORDED REAL FDC responses
/// (test/fixtures/fdc/*.json — regenerate with
/// `SALT_FDC_KEY=... dart run tool/record_fdc_fixtures.dart`, or copy a
/// sweep snapshot's cached answer with `--from-db`). A recorded empty answer
/// is FDC's own "no hits", a recorded `null` food its 404; an answer nobody
/// recorded throws [UnrecordedAnswer] — never a silent 404 or empty answer,
/// which would walk a test down a path production never takes — unless the
/// test names the query in [pending] (answered as no hits: see
/// [pendingSearches]).
class FixtureProvider implements NutritionProvider {
  /// Loads the recorded fixtures from disk.
  FixtureProvider({this.pending = const {}, this.superseded = const {}})
    : _searches =
          jsonDecode(
                File('test/fixtures/fdc/searches.json').readAsStringSync(),
              )
              as Map<String, dynamic>,
      _foods =
          jsonDecode(
                File('test/fixtures/fdc/foods.json').readAsStringSync(),
              )
              as Map<String, dynamic>;

  final Map<String, dynamic> _searches;
  final Map<String, dynamic> _foods;

  /// Searches no fixture records that a test names, answered as FDC's no
  /// hits: each is one no sweep snapshot holds ([pendingSearches]), or a
  /// query synthesized to be one FDC was never asked.
  Set<String> pending;

  /// Foods a test declares superseded — FDC's detail 404s for them — though
  /// no fixture records the 404: a test naming the path it pins.
  final Set<int> superseded;

  /// How many searches were served — cache-behavior assertions.
  int searchCalls = 0;

  /// How many food-detail lookups reached the provider.
  int foodCalls = 0;

  /// When set, every search blocks until it completes. Recorded fixtures
  /// answer instantly, so this is the only way to hold a background compute
  /// mid-flight long enough to assert on what the API reports while it runs.
  Completer<void>? gate;

  /// When set, every search throws a [NutritionProviderException] with this
  /// message — the rejected-key / drained-budget / FDC-outage class of
  /// failure (review B15).
  String? failWith;

  @override
  Future<List<FdcCandidate>> search(String query) async {
    searchCalls += 1;
    final failure = failWith;
    if (failure != null) {
      throw NutritionProviderException(failure);
    }
    await gate?.future;
    if (!_searches.containsKey(query) && !pending.contains(query)) {
      throw UnrecordedAnswer('search "$query"');
    }
    final hits = _searches[query];
    if (hits is! List) {
      return const [];
    }
    return [
      for (final hit in hits)
        FdcCandidate.fromJson(hit as Map<String, dynamic>),
    ];
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    foodCalls += 1;
    if (superseded.contains(fdcId)) {
      return null;
    }
    if (!_foods.containsKey('$fdcId')) {
      throw UnrecordedAnswer('food $fdcId');
    }
    final raw = _foods['$fdcId'];
    return raw == null ? null : FdcFood.fromJson(raw as Map<String, dynamic>);
  }
}

/// Searches the corpus-backed suites ask that NO sweep snapshot's cache
/// holds (snapshots 1–7, r2 and the diag DBs checked; checkpoint 5 review):
/// pending one live search each, answered as no hits by a test that names
/// them. Every other answer those suites need is recorded from snapshot 7.
const Set<String> pendingSearches = {
  // Acquacotta (0405): "… thick-crusted country bread …".
  'thick-crusted country bread',
  // The legacy v0 recipe (test/fixtures/legacy-v0, Brown Butter Gemelli):
  // its unit-less "unit …" lines and two items.
  'chili flakes',
  'gemelli pasta',
  'unit green onions',
  'unit lemon',
  'unit vegetable stock concentrate',
};

/// A fixture miss: the test asked FDC something no fixture recorded. A
/// [NutritionProviderException] (the engine treats it as FDC failing, never
/// as an answer) with its own type, so a test can tell a miss from a real
/// failure it staged with [FixtureProvider.failWith].
class UnrecordedAnswer extends NutritionProviderException {
  /// Names the unrecorded [what] ('search "…"', 'food 123').
  const UnrecordedAnswer(String what)
    : super(
        'unrecorded fixture: $what — record it from a snapshot with '
        'tool/record_fdc_fixtures.dart --from-db',
      );
}
