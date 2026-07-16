import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/nutrition/provider.dart';

/// A provider backed by RECORDED REAL FDC responses
/// (test/fixtures/fdc/*.json — regenerate with
/// `SALT_FDC_KEY=... dart run tool/record_fdc_fixtures.dart`). Unknown
/// queries return nothing, like FDC for gibberish.
class FixtureProvider implements NutritionProvider {
  /// Loads the recorded fixtures from disk.
  FixtureProvider()
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

  /// How many searches were served — cache-behavior assertions.
  int searchCalls = 0;

  /// When set, every search blocks until it completes. Recorded fixtures
  /// answer instantly, so this is the only way to hold a background compute
  /// mid-flight long enough to assert on what the API reports while it runs.
  Completer<void>? gate;

  @override
  Future<List<FdcCandidate>> search(String query) async {
    searchCalls += 1;
    await gate?.future;
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
    final raw = _foods['$fdcId'];
    return raw == null ? null : FdcFood.fromJson(raw as Map<String, dynamic>);
  }
}
