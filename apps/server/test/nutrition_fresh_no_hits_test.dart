import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/fdc_fixtures.dart';

/// The recorded provider, made to answer one call with NO hits — the shape
/// FDC returns for a query it has nothing for (`{"totalHits":0,"foods":[]}`,
/// which UsdaFdcProvider turns into an empty list). A negative-path input the
/// recordings cannot supply for a query they DO hold.
class _NoHitsOnce implements NutritionProvider {
  _NoHitsOnce(this.inner);
  final FixtureProvider inner;
  bool noHits = false;
  int calls = 0;

  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls += 1;
    if (noHits) {
      noHits = false;
      return const [];
    }
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) => inner.food(fdcId);
}

void main() {
  test('a live search that finds nothing does not evict the stored answer '
      'every line with that item reads', () async {
    final tmp = Directory.systemTemp.createTempSync('salt-no-hits');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final db = SaltDatabase.open('${tmp.path}/salt.db');
    addTearDown(db.dispose);
    final provider = _NoHitsOnce(FixtureProvider());
    const line = IngredientLine(raw: '1 cup sour cream', item: 'sour cream');
    final key = searchQueryFor(normalizeItem('sour cream'));

    await foodSearchBody(db, provider, 'sour cream');
    final before = await candidatesForLine(db, provider, line, cacheOnly: true);
    expect(before, isNotEmpty, reason: 'the recording holds sour cream');
    final storedBefore = db.fdcSearchCacheGet(key);

    // The admin clicks "Search live" and FDC, this once, has no hits.
    provider.noHits = true;
    final calls = provider.calls;
    final live = await foodSearchBody(db, provider, 'sour cream', fresh: true);
    expect(provider.calls, calls + 1, reason: 'one live call');
    expect(live['items'], isEmpty, reason: 'the live answer is reported');
    expect(live['cached'], isFalse);

    expect(db.fdcSearchCacheGet(key), storedBefore, reason: 'row kept');
    final after = await candidatesForLine(db, provider, line, cacheOnly: true);
    expect(after.length, before.length, reason: 'every line still has them');
    final computed = await candidatesForLine(db, provider, line);
    expect(computed, isNotEmpty, reason: 'the compute path still finds them');
  });
}
