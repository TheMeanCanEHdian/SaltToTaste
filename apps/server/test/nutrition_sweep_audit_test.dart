import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// The recorded provider, recording what it is asked.
class _Recording implements NutritionProvider {
  final FixtureProvider inner = FixtureProvider();
  final List<String> searched = [];
  final List<int> fetched = [];

  /// Every detail 404s — a superseded record (negative path).
  bool detail404 = false;

  /// Every call throws, as with no key set or the hourly budget spent.
  bool down = false;

  @override
  Future<List<FdcCandidate>> search(String query) {
    searched.add(query);
    if (down) {
      throw const NutritionProviderException('budget used up');
    }
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    fetched.add(fdcId);
    if (down) {
      throw const NutritionProviderException('budget used up');
    }
    return detail404 ? null : inner.food(fdcId);
  }
}

/// Changes from the 2026-09-26 sweep audit (plan items 2, 3b, 4, 5, 6),
/// pinned on real corpus lines.
void main() {
  group('matcher v4 on real corpus items', () {
    test('a second amount left in the item leaves the query and the key', () {
      // '½ cup plus 2 tablespoons extra-virgin olive oil'
      expect(
        normalizeItem('plus 2 tablespoons extra-virgin olive oil'),
        'extra-virgin olive oil',
      );
      // '3 tablespoons plus 2 teaspoons kosher salt' matched pickles.
      expect(itemKeyFor('plus 2 teaspoons kosher salt'), 'kosher salt');
      // '2 teaspoons minced fresh thyme or ½ teaspoon dried'
      expect(normalizeItem('fresh thyme or 1/2 teaspoon dried'), 'thyme');
      // '¼ teaspoon finely grated lemon zest plus ½ teaspoon juice'
      expect(
        normalizeItem('finely grated lemon zest plus 1/2 teaspoon juice'),
        'lemon zest',
      );
      // '1 teaspoon grated zest plus 1 tablespoon juice from 1 lemon': the
      // fruit is named before the second amount is cut.
      expect(
        normalizeItem('grated zest plus 1 tablespoon juice from 1 lemon'),
        'lemon zest',
      );
      // '1 teaspoon juice from 1 lemon or 1 teaspoon champagne vinegar'
      expect(
        normalizeItem('juice from 1 lemon or 1 teaspoon champagne vinegar'),
        'lemon juice',
      );
    });

    test('a number that is not an amount stays', () {
      for (final item in [
        '85 or 93 percent lean ground turkey',
        '93 percent lean ground beef',
        'whole or 2 percent low-fat milk',
      ]) {
        expect(normalizeItem(item), item, reason: item);
      }
      // '1 large egg plus 1 large yolk': no measure word, no cut.
      expect(normalizeItem('large egg plus 1 large yolk'), 'egg 1 yolk');
    });

    test('equipment is not food; "pan" and "chips" alone are', () {
      for (final item in [
        'Wooden skewers',
        '12-inch metal skewers',
        '36-inch square cheesecloth',
        'wood chips',
        '(13 by 9-inch) disposable aluminum roasting pan',
      ]) {
        expect(isNonFood(normalizeItem(item)), isTrue, reason: item);
      }
      for (final item in [
        'pan sauce (optional; recipes follow)',
        'Giblet Pan Gravy (recipe follows)',
        'Pan-Seared Steaks (this page)',
        'tortilla chips',
      ]) {
        expect(isNonFood(normalizeItem(item)), isFalse, reason: item);
      }
    });

    test('"A or B" searches A only when A is a known query, never an '
        'adjective', () {
      bool always(String _) => true;
      bool never(String _) => false;
      // 'brandy' is a rewrite target: a food noun, cached or not.
      expect(leftAlternative('brandy or dry sherry', never), 'brandy');
      expect(leftAlternative('pecans or walnuts', always), 'pecans');
      expect(leftAlternative('pecans or walnuts', never), isNull);
      // A one-word A before a longer B shares B's noun — even when that
      // word is itself a cached query (the snapshot held 'chicken', 'dark',
      // 'light' and 'sweetened').
      for (final item in [
        'green or brown lentils',
        'chicken or vegetable broth',
        'sweetened or unsweetened dried cranberries',
        normalizeItem('semisweet or bittersweet chocolate'),
      ]) {
        expect(leftAlternative(item, always), isNull, reason: item);
      }
      // A rewrite phrase splits: parsley is a rewrite target.
      expect(
        leftAlternative(normalizeItem('fresh parsley or basil leaves'), never),
        'parsley',
      );
    });
  });

  test('a line whose own words were never searched reads the answer stored '
      "under its key's words — zero FDC calls, ranked under its own", () async {
    final tmp = Directory.systemTemp.createTempSync('salt-sibling');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final db = SaltDatabase.open('${tmp.path}/salt.db');
    addTearDown(db.dispose);
    final provider = _Recording();
    // The recorded answer for 'garlic cloves', stored under the key form.
    final answer = await provider.inner.search('garlic cloves');
    db.fdcSearchCachePut(
      'garlic clove',
      jsonEncode([for (final hit in answer) hit.toJson()]),
    );
    // Garlic and Olive Oil Mashed Potatoes.
    const line = IngredientLine(
      raw:
          '5 medium garlic cloves, minced or pressed through a garlic press '
          '(about 5 teaspoons)',
      item: 'medium garlic cloves',
    );
    expect(
      lineSearchFor(db, 'garlic cloves', 'garlic clove'),
      (query: 'garlic cloves', answer: 'garlic clove'),
    );
    final expected = [
      for (final c in rankCandidates('garlic cloves', answer).take(8))
        (c.candidate.fdcId, c.confidence),
    ];
    for (final cacheOnly in [true, false]) {
      final ranked = await candidatesForLine(
        db,
        provider,
        line,
        cacheOnly: cacheOnly,
      );
      expect(
        [
          for (final c in ranked) (c.candidate.fdcId, c.confidence),
        ],
        expected,
        reason: 'cacheOnly: $cacheOnly',
      );
    }
    expect(provider.searched, isEmpty);
    expect(
      db.fdcSearchCacheGet('garlic cloves'),
      isNull,
      reason: 'the answer is read, not copied: new rows are FDC requests',
    );
  });

  group('the engine on real corpus recipes', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late _Recording provider;
    late Map<String, Recipe> recipes;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-sweep-audit');
      final config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath);
      final sourceRoot = Directory('${tempDir.path}/source')
        ..createSync(recursive: true);
      Directory('${sourceRoot.path}/recipes').createSync();
      const files = {
        'mash': '0000-garlic-and-olive-oil-mashed-potatoes.yaml',
        'tomato': '0013-ultimate-cream-of-tomato-soup.yaml',
        'mujaddara': '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
        'stuffed': '0156-old-fashioned-stuffed-turkey.yaml',
        'julia': '0159-julia-childs-stuffed-turkey-updated.yaml',
        'bundt': '0857-rich-chocolate-bundt-cake.yaml',
      };
      for (final name in files.values) {
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${sourceRoot.path}/recipes/$name');
      }
      importSourceRoot(sourceRootPath: sourceRoot.path, db: db, config: config);
      recipes = {
        for (final entry in files.entries)
          entry.key: db
              .recipeByIdOrSlug(
                entry.value.substring(5, entry.value.length - 5),
              )!
              .recipe,
      };
      provider = _Recording();
      // The recorded 'garlic cloves' answer under the key form only.
      final garlic = await provider.inner.search('garlic cloves');
      db
        ..fdcSearchCachePut(
          'garlic clove',
          jsonEncode([for (final hit in garlic) hit.toJson()]),
        )
        // 'green' as a cached query (FDC answered nothing): only the
        // adjective guard keeps "green or brown lentils" whole.
        ..fdcSearchCachePut('green', '[]');
      for (final recipe in recipes.values) {
        await matchAndCompute(db, provider, recipe);
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    (IngredientLine, IngredientMatchRow) rowOf(String recipe, String raw) {
      final lines = nutritionLines(recipes[recipe]!);
      final position = lines.indexWhere((line) => line.raw == raw);
      expect(position, isNonNegative, reason: raw);
      return (
        lines[position],
        db
            .ingredientMatchesFor(recipes[recipe]!.id)
            .firstWhere((row) => row.position == position),
      );
    }

    test('equipment is a confirmed zero and never searched', () {
      for (final (recipe, raw) in [
        ('stuffed', '1 36-inch square cheesecloth, folded in quarters'),
        ('julia', 'Wooden skewers'),
      ]) {
        final (_, row) = rowOf(recipe, raw);
        expect(row.status, 'confirmed', reason: raw);
        expect(row.fdcId, isNull);
        expect(row.description, 'Equipment — not food, counts as zero');
      }
      expect(
        provider.searched.where(
          (q) => q.contains('cheesecloth') || q.contains('skewer'),
        ),
        isEmpty,
      );
    });

    test('no query carries a second amount', () {
      final (_, salt) = rowOf(
        'stuffed',
        '3 tablespoons plus 2 teaspoons kosher salt',
      );
      expect(salt.itemKey, 'kosher salt');
      expect(provider.searched, contains('extra-virgin olive oil'));
      expect(
        provider.searched.where(
          (q) => RegExp(r'\d+ (teaspoon|tablespoon|cup)').hasMatch(q),
        ),
        isEmpty,
      );
    });

    test('"brandy or dry sherry" searches brandy; "green or brown lentils" '
        'stays whole', () async {
      final (_, brandy) = rowOf('tomato', '2 tablespoons brandy or dry sherry');
      final top = rankCandidates(
        'brandy',
        await provider.inner.search('brandy'),
      ).first;
      expect(brandy.fdcId, top.candidate.fdcId);
      expect(brandy.confidence, top.confidence);
      expect(brandy.itemKey, 'brandy or dry sherry', reason: 'key unchanged');
      expect(provider.searched, isNot(contains('brandy or dry sherry')));
      final body = await matchesBody(db, provider, recipes['tomato']!);
      final item = (body['items']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere(
            (i) => i['raw'] == '2 tablespoons brandy or dry sherry',
          );
      expect(item['candidates_query'], 'brandy');
      expect(item['candidates_cached_at'], isNotNull);

      expect(provider.searched, contains('green or brown lentils'));
      expect(provider.searched, isNot(contains('green')));
    });

    test('a plural line is served by its key-form sibling', () async {
      final (_, garlic) = rowOf(
        'mash',
        '5 medium garlic cloves, minced or pressed through a garlic press '
            '(about 5 teaspoons)',
      );
      expect(provider.searched, isNot(contains('garlic cloves')));
      final top = rankCandidates(
        'garlic cloves',
        await provider.inner.search('garlic cloves'),
      ).first;
      expect(garlic.fdcId, top.candidate.fdcId);
      final body = await matchesBody(db, provider, recipes['mash']!);
      final item = (body['items']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere(
            (i) => i['raw'] == garlic.raw,
          );
      expect(item['candidates_query'], 'garlic clove');
      expect(item['candidates'], isNotEmpty);
    });

    test('a food detail is fetched only for portions; no stand-in reaches '
        'fdc_food_cache, yet the totals count every line', () async {
      final bundt = recipes['bundt']!;
      // Every cached food row is FDC's own detail, portions and all — or,
      // where the detail was asked for and 404'd (the recordings hold no
      // detail for it), the search hit: FDC's only record of that food.
      var details = 0;
      for (final row in db.ingredientMatchesFor(bundt.id)) {
        final cached = row.fdcId == null
            ? null
            : db.fdcFoodCacheGet(row.fdcId!);
        if (cached == null) {
          continue;
        }
        final detail = await provider.inner.food(row.fdcId!);
        if (detail == null) {
          expect(provider.fetched, contains(row.fdcId), reason: row.raw);
        } else {
          details += 1;
          expect(cached, jsonEncode(detail.toJson()), reason: row.raw);
        }
      }
      expect(details, isPositive, reason: 'a portion line fetched its food');
      // Weighed lines whose food no other line needed portions from: never
      // fetched, never cached.
      final weighed = [
        for (final row in db.ingredientMatchesFor(bundt.id))
          if (row.gramSource == 'weight' &&
              row.fdcId != null &&
              db.fdcFoodCacheGet(row.fdcId!) == null)
            row,
      ];
      expect(weighed, isNotEmpty);
      for (final row in weighed) {
        expect(provider.fetched, isNot(contains(row.fdcId)), reason: row.raw);
      }
      final lazy = db.nutritionFor(bundt.id)!;
      expect(lazy.caloriesPerServing, isNotNull);

      // A later recompute (a serving-basis change) reads the stand-ins from
      // the cached search hits: no FDC call, so it works with the budget
      // spent, and it still caches none of them.
      final calls = provider.fetched.length + provider.searched.length;
      provider.down = true;
      try {
        await recomputeTotals(
          db,
          provider,
          bundt,
          servingBasis: lazy.servingBasis! * 2,
        );
      } finally {
        provider.down = false;
      }
      expect(provider.fetched.length + provider.searched.length, calls);
      final halved = db.nutritionFor(bundt.id)!;
      expect(halved.matchedCount, lazy.matchedCount);
      expect(
        halved.caloriesPerServing,
        closeTo(lazy.caloriesPerServing! / 2, 0.01),
      );
      for (final row in weighed) {
        expect(db.fdcFoodCacheGet(row.fdcId!), isNull, reason: row.raw);
      }
      await recomputeTotals(
        db,
        provider,
        bundt,
        servingBasis: lazy.servingBasis,
      );
    });

    test('a decision on a stand-in lands with the budget spent: a pick of '
        'the matched food, a confirm, a confirm applied to all', () async {
      final bundt = recipes['bundt']!;
      final standIns = [
        for (final row in db.ingredientMatchesFor(bundt.id))
          if (row.fdcId != null && db.fdcFoodCacheGet(row.fdcId!) == null) row,
      ];
      // Each threw 'budget used up' when apply_to_all re-read the food from
      // FDC (review round 2).
      expect(standIns, isNotEmpty);
      final calls = provider.fetched.length + provider.searched.length;
      provider.down = true;
      try {
        await applyMatchOverride(db, provider, bundt, standIns.first.position, {
          'fdc_id': standIns.first.fdcId,
        });
        for (final row in standIns) {
          final applied = await applyMatchOverride(
            db,
            provider,
            bundt,
            row.position,
            {'confirmed': true, 'apply_to_all': true},
          );
          expect(applied, isNotNull, reason: row.raw);
        }
      } finally {
        provider.down = false;
      }
      expect(provider.fetched.length + provider.searched.length, calls);
      for (final row in standIns) {
        final now = db
            .ingredientMatchesFor(bundt.id)
            .firstWhere((match) => match.position == row.position);
        expect(now.status, 'confirmed', reason: row.raw);
        expect(now.grams, row.grams, reason: row.raw);
        expect(db.fdcFoodCacheGet(row.fdcId!), isNull, reason: row.raw);
      }
    });

    test(
      "a picked hit the line's own answer does not hold still reads "
      'from the cache: the food is found in whichever answer holds it',
      () async {
        final bundt = recipes['bundt']!;
        final (line, _) = rowOf(
          'bundt',
          '1¾ cups (8¾ ounces) unbleached all-purpose flour',
        );
        // The review sheet's own search: a person looks up another flour.
        final hits = await searchCandidates(db, provider, 'whole-wheat flour');
        final own = db.fdcSearchCacheGet(
          lineSearchFor(
            db,
            normalizeItem(line.item ?? line.raw),
            itemKeyFor(line.item ?? line.raw),
          ).answer,
        )!;
        final pick = hits.firstWhere(
          (hit) =>
              !own.contains('{"fdc_id":${hit.candidate.fdcId},') &&
              db.fdcFoodCacheGet(hit.candidate.fdcId) == null,
        );
        final calls = provider.fetched.length + provider.searched.length;
        provider.down = true;
        try {
          final position = nutritionLines(bundt).indexOf(line);
          await applyMatchOverride(db, provider, bundt, position, {
            'fdc_id': pick.candidate.fdcId,
          });
          await recomputeTotals(db, provider, bundt, servingBasis: 8);
        } finally {
          provider.down = false;
        }
        // A weighed line: the hit stands in, no detail fetched or cached.
        expect(provider.fetched.length + provider.searched.length, calls);
        expect(db.fdcFoodCacheGet(pick.candidate.fdcId), isNull);
      },
    );
  });

  test(
    'a superseded food (detail 404) no compute cached still counts when the '
    'totals are recomputed later: its search hit stands in, as before',
    skip: skipIfNoCorpus,
    () async {
      final tmp = Directory.systemTemp.createTempSync('salt-superseded');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final config = ServerConfig(
        dataDir: tmp.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      final db = SaltDatabase.open(config.dbPath);
      addTearDown(db.dispose);
      const name = '0857-rich-chocolate-bundt-cake.yaml';
      Directory('${tmp.path}/source/recipes').createSync(recursive: true);
      File(
        '$corpusRecipesDir/$name',
      ).copySync('${tmp.path}/source/recipes/$name');
      importSourceRoot(
        sourceRootPath: '${tmp.path}/source',
        db: db,
        config: config,
      );
      final bundt = db.recipeByIdOrSlug('rich-chocolate-bundt-cake')!.recipe;
      final provider = _Recording()..detail404 = true;
      await matchAndCompute(db, provider, bundt);
      final fresh = db.nutritionFor(bundt.id)!;

      await recomputeTotals(db, provider, bundt);
      final later = db.nutritionFor(bundt.id)!;
      expect(later.matchedCount, fresh.matchedCount);
      expect(later.caloriesPerServing, fresh.caloriesPerServing);
    },
  );
}
