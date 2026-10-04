import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/applied.dart';
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
  group('matcher v5 on real corpus items', () {
    test('a second amount left in the item leaves the query and the key', () {
      // '½ cup plus 2 tablespoons extra-virgin olive oil'
      expect(
        normalizeItem('plus 2 tablespoons extra-virgin olive oil'),
        'extra-virgin olive oil',
      );
      // '3 tablespoons plus 2 teaspoons kosher salt' matched pickles.
      expect(itemKeyFor('plus 2 teaspoons kosher salt'), 'kosher salt');
      // '2 teaspoons minced fresh thyme or ½ teaspoon dried': B's own amount
      // goes, B stays.
      expect(
        normalizeItem('fresh thyme or 1/2 teaspoon dried'),
        'thyme or dried',
      );
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
        'lemon juice or champagne vinegar',
      );
      // '¼ cup plus 1 tablespoon juice from 2 to 3 lemons, spent halves
      // reserved' (0286): the moved fruit is not a food ahead of the leading
      // amount — lemon juice, not the whole-lemon key.
      const juice = 'plus 1 tablespoon juice from 2 to 3 lemons';
      expect(normalizeItem(juice), 'lemon juice');
      expect(itemKeyFor(juice), 'lemon juice');
      expect(itemKeyFor(juice), isNot(itemKeyFor('lemons')));
      // '1 teaspoon cornstarch dissolved in 1 teaspoon water' (0673),
      // '½ teaspoon instant espresso powder mixed with 1 tablespoon water'
      // (0930): the dangling connector goes with the cut, and so does the
      // participle before it (audit 3, N8: both base queries are cached).
      expect(
        normalizeItem('cornstarch dissolved in 1 teaspoon water'),
        'cornstarch',
      );
      expect(
        normalizeItem('instant espresso powder mixed with 1 tablespoon water'),
        'instant espresso powder',
      );
      // '1 teaspoon plus 2 pinches table salt, divided' (0049).
      expect(normalizeItem('plus 2 pinches table salt'), 'table salt');
      // 'Small pinch cayenne pepper' (0301): a measure word with no number
      // before it is not an amount — but it is no food either: leading, it
      // leaves the item (matcher v8).
      expect(normalizeItem('Small pinch cayenne pepper'), 'cayenne pepper');
    });

    test('"A or <amount> B" drops only the amount: B is a food', () {
      for (final (item, expected) in [
        // '5 tablespoons masa harina or 3 tablespoons cornstarch' (0495)
        (
          'masa harina or 3 tablespoons cornstarch',
          'masa harina or cornstarch',
        ),
        // '… crushed saltines (about 16) or quick oatmeal or 1⅓ cups fresh
        // bread crumbs' (0306)
        (
          'crushed saltines (about 16) or quick oatmeal or 1 1/3 cups fresh '
              'bread crumbs',
          'saltines or quick oatmeal or bread crumbs',
        ),
        // '1 pound fresh Chinese noodles or 8 ounces dried linguine' (0540)
        (
          'fresh Chinese noodles or 8 ounces dried linguine',
          'chinese noodles or dried linguine',
        ),
      ]) {
        expect(normalizeItem(item), expected, reason: item);
      }
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
        // '4 (2-inch) wood chunks' (0587), '2 wood chunks soaked in water …'
        // (0646)
        '(2-inch) wood chunks',
        'wood chunks',
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
      // 'pecans' is a rewrite target since matcher v21 ('whole pecans or
      // walnuts'): a food noun, cached or not, as 'brandy' is. An A that
      // is neither cached nor in the rewrite table is no known query.
      expect(leftAlternative('pecans or walnuts', never), 'pecans');
      expect(leftAlternative('pistachios or almonds', never), isNull);
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
      // A rewrite KEY splits too, uncached: '1 pound ziti or other short
      // tubular pasta' (0367) — a one-word A that is a food noun, not an
      // adjective — and '1 pound linguine or spaghetti' (0337).
      expect(
        leftAlternative('ziti or other short tubular pasta', never),
        'ziti',
      );
      expect(leftAlternative('linguine or spaghetti', never), 'linguine');
      // Nothing after the "or": no alternative to split from (a hand-edited
      // item; the corpus has none — negative path).
      expect(leftAlternative('brandy or', always), isNull);
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
        'never splits on its adjective', () async {
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

      // Since matcher v21 the phrase is rewritten to its noun, 'lentils';
      // the adjective guard still never searches 'green' (leftAlternative
      // above).
      expect(provider.searched, contains('lentils'));
      expect(provider.searched, isNot(contains('green or brown lentils')));
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
        recomputeTotals(
          db,
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
      recomputeTotals(
        db,
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
          recomputeTotals(db, bundt, servingBasis: 8);
        } finally {
          provider.down = false;
        }
        // A weighed line: the hit stands in, no detail fetched or cached.
        expect(provider.fetched.length + provider.searched.length, calls);
        expect(db.fdcFoodCacheGet(pick.candidate.fdcId), isNull);
      },
    );

    GramResolution? onDetail(IngredientLine line, FdcFood food) => resolveGrams(
      amounts: line.amounts,
      food: food,
      normalizedItem: normalizeItem(line.item ?? line.raw),
      raw: line.raw,
    );

    test('a volume line takes its grams from the fetched detail, portions '
        'and all', () async {
      final (line, row) = rowOf('mujaddara', '1 teaspoon sugar');
      final detail = (await provider.inner.food(row.fdcId!))!;
      expect(detail.portions, isNotEmpty);
      final expected = onDetail(line, detail)!;
      expect(expected.source, GramSource.portion);
      expect(row.gramSource, 'portion');
      expect(row.grams, expected.grams);
    });

    test('a macro-complete record below a macro-incomplete top hit is the '
        'food', () async {
      final (line, row) = rowOf('mujaddara', '½ teaspoon salt');
      final search = lineSearchFor(
        db,
        normalizeItem(line.item ?? line.raw),
        itemKeyFor(line.item ?? line.raw),
      );
      final top = rankCandidates(
        search.query,
        await provider.inner.search(search.answer),
      ).first.candidate;
      expect(
        top.nutrientsPer100g!.keys,
        isNot(contains('208')),
        reason: 'the Foundation salt record publishes no energy',
      );
      expect(row.fdcId, isNot(top.fdcId));
    });

    test(
      'a pick on a volume line fetches the detail for its portions',
      () async {
        final bundt = recipes['bundt']!;
        final (line, _) = rowOf('bundt', '1 teaspoon table salt');
        final pick = (await provider.inner.search('table salt')).firstWhere(
          (hit) => db.fdcFoodCacheGet(hit.fdcId) == null,
        );
        await applyMatchOverride(
          db,
          provider,
          bundt,
          nutritionLines(bundt).indexOf(line),
          {'fdc_id': pick.fdcId},
        );
        final (_, row) = rowOf('bundt', '1 teaspoon table salt');
        final expected = onDetail(
          line,
          (await provider.inner.food(pick.fdcId))!,
        )!;
        expect(row.fdcId, pick.fdcId);
        expect(row.gramSource, 'portion');
        expect(row.grams, expected.grams);
        expect(db.fdcFoodCacheGet(pick.fdcId), isNotNull);
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

      recomputeTotals(db, bundt);
      final later = db.nutritionFor(bundt.id)!;
      expect(later.matchedCount, fresh.matchedCount);
      expect(later.caloriesPerServing, fresh.caloriesPerServing);
    },
  );

  group('which cached answer a line reads (review of the sweep batch)', () {
    late Directory tmp;
    late SaltDatabase db;
    final fixtures = FixtureProvider();

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('salt-line-search');
      db = SaltDatabase.open('${tmp.path}/salt.db');
    });
    tearDown(() {
      db.dispose();
      tmp.deleteSync(recursive: true);
    });

    Future<String> recorded(String query) async => jsonEncode([
      for (final hit in await fixtures.search(query)) hit.toJson(),
    ]);

    test('an EMPTY cached answer for A is not a known query: '
        '"mirin or sweet sherry" is searched whole', () {
      // '2 tablespoons mirin or sweet sherry' (0524 Chicken Teriyaki). FDC
      // has no mirin record: the sweep cached 'mirin' -> [].
      db.fdcSearchCachePut('mirin', '[]');
      // The empty answer names no A, read as the line's search reads it
      // (engine.dart lineSearchFor's isCached)...
      expect(
        leftAlternative('mirin or sweet sherry', (query) {
          final answer = db.fdcSearchCacheGet(query);
          return answer != null && answer != '[]';
        }),
        isNull,
      );
      // ...and since matcher v31 (Q7 sweet wines, ruled) the line is a
      // rank-as item, read ahead of any alternative: the cached 'sherry'
      // answer under 'wine dessert sweet', flagged.
      expect(
        lineSearchFor(db, 'mirin or sweet sherry', 'mirin or sweet sherry'),
        (query: 'wine dessert sweet', answer: 'sherry'),
      );
      // '6 ounces pancetta or bacon, sliced …' (0332): pancetta (whose
      // answer is [] too) is a rewrite key since matcher v8, so A is searched
      // as its stand-in.
      db.fdcSearchCachePut('pancetta', '[]');
      expect(
        lineSearchFor(db, 'pancetta or bacon', 'pancetta or bacon'),
        (
          query: 'pork cured bacon unprepared',
          answer: 'pork cured bacon unprepared',
        ),
      );
    });

    test('a rewritten line never reads its key-form sibling', () async {
      // '⅛ teaspoon red pepper flakes' (0000): FDC answers the raw phrase
      // with bell peppers — the reason 'red pepper flakes' is rewritten.
      db.fdcSearchCachePut(
        'red pepper flake',
        await recorded('red pepper flakes'),
      );
      final query = searchQueryFor('red pepper flakes');
      expect(query, isNot('red pepper flakes'));
      expect(
        lineSearchFor(db, 'red pepper flakes', 'red pepper flake'),
        (query: query, answer: query),
      );
    });

    test('the left alternative is searched rewritten', () {
      // '1 pound linguine or spaghetti' (0337): 'linguine' is a rewrite key.
      final query = searchQueryFor('linguine');
      expect(query, isNot('linguine'));
      expect(
        lineSearchFor(db, 'linguine or spaghetti', 'linguine or spaghetti'),
        (query: query, answer: query),
      );
    });

    test("the line's own cached answer beats its key-form sibling's", () async {
      // '3 jalapeño chiles, stemmed, seeded, and minced' (Roasted Bone-In
      // Chicken Breasts, 0120): its own words searched, and the key form
      // holding a different (empty) answer. (Thai chiles were the pin until
      // matcher v14 rewrote them.)
      db
        ..fdcSearchCachePut(
          'jalapeno chiles',
          await recorded('jalapeno chiles'),
        )
        ..fdcSearchCachePut('jalapeno chile', '[]');
      expect(
        lineSearchFor(db, 'jalapeno chiles', 'jalapeno chile'),
        (query: 'jalapeno chiles', answer: 'jalapeno chiles'),
      );
      const line = IngredientLine(
        raw: '3 jalapeño chiles, stemmed, seeded, and minced',
        item: 'jalapeño chiles',
      );
      final ranked = await candidatesForLine(
        db,
        _Recording()..down = true,
        line,
        cacheOnly: true,
      );
      expect(ranked, isNotEmpty);
    });

    test("a sibling answer is ranked under the line's own words", () async {
      // Thai chiles (the pin until matcher v8, whose chile credit ranks
      // 'chil' and 'chile' alike) gave way to prunes, prunes (until v12
      // stemmed 'prunes' as 'prune') to cardamom pods, and cardamom pods
      // (rewritten to 'cardamom pods' in v21: a rewritten line never reads
      // its key's answer) to the egg of an egg-plus-yolks line, keyed
      // 'egg plus yolk': under its own word the answer leads with the whole
      // egg, under the key's with the yolk.
      final answer = await fixtures.search('egg');
      db.fdcSearchCachePut('egg plus yolk', await recorded('egg'));
      String top(String query) =>
          rankCandidates(query, answer).first.candidate.description;
      expect(top('egg'), isNot(top('egg plus yolk')));
      // Duchess Potato Casserole (0447), as its file stores it.
      const line = IngredientLine(
        raw: '1 large egg, separated, plus 2 large yolks',
        item: 'large egg',
        prep: 'separated, plus 2 large yolks',
        amounts: [Amount(measure: Measure.count, quantity: '1', primary: true)],
      );
      expect(lineKeyOf(line), 'egg plus yolk');
      for (final cacheOnly in [true, false]) {
        final ranked = await candidatesForLine(
          db,
          _Recording()..down = true,
          line,
          cacheOnly: cacheOnly,
        );
        expect(
          [for (final c in ranked) (c.candidate.fdcId, c.confidence)],
          [
            for (final c in rankCandidates('egg', answer).take(8))
              (c.candidate.fdcId, c.confidence),
          ],
          reason: 'cacheOnly: $cacheOnly',
        );
      }
    });

    test("knownFood reads the line's own answer first: the other answers' "
        'lookup (an indexed one since migration 016) runs only when that '
        'answer lacks the food', () async {
      // '5 medium garlic cloves, minced …' (0000).
      db.fdcSearchCachePut('garlic cloves', await recorded('garlic cloves'));
      const line = IngredientLine(
        raw:
            '5 medium garlic cloves, minced or pressed through a garlic press '
            '(about 5 teaspoons)',
        item: 'medium garlic cloves',
      );
      final id = (await fixtures.search('garlic cloves')).first.fdcId;
      bool scanned() => db.preparedSqlTexts.any(
        (sql) => sql.contains('FROM fdc_search_cache_foods'),
      );
      expect(knownFood(db, id, line: line)?.fdcId, id);
      expect(scanned(), isFalse);
      // No line: the scan is the only way to find it (the seam works).
      expect(knownFood(db, id)?.fdcId, id);
      expect(scanned(), isTrue);
    });

    test('a cached hit with no nutrients is not a food (negative path: the '
        'recorded answer with its top hit stripped)', () async {
      final hits = await fixtures.search('garlic cloves');
      final bare = hits.first;
      db.fdcSearchCachePut(
        'garlic cloves',
        jsonEncode([
          FdcCandidate(
            fdcId: bare.fdcId,
            description: bare.description,
            dataType: bare.dataType,
          ).toJson(),
          for (final hit in hits.skip(1)) hit.toJson(),
        ]),
      );
      const line = IngredientLine(
        raw: '5 medium garlic cloves',
        item: 'medium garlic cloves',
      );
      expect(knownFood(db, bare.fdcId, line: line), isNull);
      expect(knownFood(db, hits[1].fdcId, line: line)?.fdcId, hits[1].fdcId);
    });

    test('an equipment line never reaches FDC from the review sheet', () async {
      final provider = _Recording();
      const line = IngredientLine(
        raw: '4 (2-inch) wood chunks',
        item: '(2-inch) wood chunks',
      );
      expect(await candidatesForLine(db, provider, line), isEmpty);
      expect(provider.searched, isEmpty);
    });
  });

  test("a search hit carries the detail's nutrients rounded to fewer digits: "
      'every recorded food within 1% on energy and the macros', () async {
    final searches =
        jsonDecode(File('test/fixtures/fdc/searches.json').readAsStringSync())
            as Map<String, dynamic>;
    // Every hit of every recorded answer whose detail is recorded too.
    final foods =
        jsonDecode(File('test/fixtures/fdc/foods.json').readAsStringSync())
            as Map<String, dynamic>;
    final provider = FixtureProvider();
    var compared = 0;
    var differ = 0;
    final seen = <int>{};
    for (final query in searches.keys) {
      for (final hit in await provider.search(query)) {
        if (!foods.containsKey('${hit.fdcId}')) {
          continue;
        }
        final detail = await provider.food(hit.fdcId);
        final fromHit = hit.nutrientsPer100g;
        if (detail == null || fromHit == null || !seen.add(hit.fdcId)) {
          continue;
        }
        compared += 1;
        final numbers = {...fromHit.keys, ...detail.nutrientsPer100g.keys};
        if (numbers.any((n) => fromHit[n] != detail.nutrientsPer100g[n])) {
          differ += 1;
        }
        for (final number in const ['208', '203', '204', '205']) {
          final a = fromHit[number];
          final b = detail.nutrientsPer100g[number];
          if (a == null || b == null || b == 0) {
            continue;
          }
          expect(
            (a - b).abs() / b.abs(),
            lessThan(0.01),
            reason: '${hit.fdcId} $number: hit $a, detail $b',
          );
        }
      }
    }
    // Light brown sugar (168833): carbohydrate 98.1 in the hit, 98.09 in
    // the detail. Equal is the exception, not the rule.
    // The accuracy batch recorded seven more foods from the sweep snapshot;
    // five are also a recorded search hit (748608, 2759000, 2708167, 170931,
    // 2709794) and three of those differ in some digit. Audit 3 recorded
    // 2644288 (a hit in 'chickpeas') and its 'mustard seeds' answer holds
    // 170929: two more compared, both differ in some digit. The refix
    // recorded 169599 (gelatin, a hit in 'unsweetened'): equal in every digit.
    // Audit 4 recorded tuna (173708), allspice (171315) and lemon (2709168),
    // and a new answer holds half-and-half (2705594) as a hit: all four
    // differ in some digit. Refix 1 recorded thyme (173470), a hit in
    // 'thyme' and 'thyme leaves': it differs too. Checkpoint 5 recorded 25
    // more foods that are also a recorded hit (the juice, egg, peel,
    // sibling and bird records among them): 19 differ in some digit. Its
    // second refix recorded the skinned leg, turkey thigh and skin-on thigh
    // (173619, 174518, 2727567), all recorded hits that differ in some digit.
    // The checkpoint-5 review (matcher v9) recorded 172370, 2709682,
    // 2727583, 748236, 2709215, 2710078 and 172336 and the answers its pins
    // read from snapshot 7: eight more compared, five of them differ in some
    // digit. Its refix recorded every answer the corpus-backed suites ask
    // for from snapshot 7 (no fixture miss passes as FDC's own answer): 47
    // more compared, 32 of them differ in some digit. Checkpoint 6 (matcher
    // v10) recorded its pins' answers from snapshot 8: 9 more compared, 8
    // of them differ in some digit. The checkpoint-6 review (matcher v11)
    // recorded "Mushroom, oyster" (1999627) from snapshot 9, a hit in
    // 'oysters': it differs too. Checkpoint 7 (matcher v12) recorded
    // pickled hot peppers (2710095), avocado (2710824), egg white (747997)
    // and navel oranges (746771) from snapshot 10, and the foods its
    // repointed Indian Curry pin (0567) reads (172231, 2685581, 2707427):
    // seven more compared, four of them differ in some digit. Its review
    // (matcher v13) recorded "Prune, dried" (2709211) and "Pomegranate,
    // raw" (2709267) from snapshot 11, hits in 'prunes' and 'pomegranate
    // seeds', and the fresh ham's pork record (168367) its cured_for_fresh
    // pin reads, and the marjoram, tarragon and chervil spices (170928,
    // 170937, 171318) the R4 herbs now count on: all six differ in some
    // digit. Its second refix recorded "Crackers, whole-wheat" (172749)
    // from snapshot 11 for the Berry Fool pin, a hit in 'whole cloves': it
    // differs too. The sub-recipe refinement recorded "Egg, whole, cooked,
    // hard-boiled" (173424) and "Taco shells, baked" (172800) from snapshot
    // 11, hits in 'hard-cooked eggs' and 'home-fried taco shells': both
    // differ in some digit. Matcher v14 (checkpoint 8's portion fixes)
    // recorded the Pinot Noir, Boston butt, ancho and sun-dried chile
    // records (174835, 167849, 169396, 168570) from snapshot 12, hits in
    // 'red wine', 'pork boston butt lean and fat', 'pepper' and 'thai
    // chiles', and the plums (169949), a hit in 'red plums'; and its
    // rewrites' recorded 'bosc pear' answer holds the Bosc pear (167778):
    // five of the six differ in some digit. Matcher v15 recorded "Champagne
    // punch" (2710675) from snapshot 12 for the paren-volume pin, a hit in
    // 'champagne': equal in every digit. Its leftovers recorded "Hot pepper
    // sauce" (2710093) from snapshot 12 for the unit-only line_amount pin,
    // a hit in 'pepper': equal in every digit. Matcher v17 recorded garlic
    // powder (171325), the fresh hot pepper (2709798), green cabbage
    // (2346407), baby spinach (1999632) and iceberg (2346388) from snapshot
    // 12: four are hits ('garlic', 'pepper', 'green cabbage', 'spinach'),
    // all four differ in some digit. Its second batch recorded the
    // tenderloin roast (171748) for the capped "roast" pin, a hit in 'beef
    // tenderloin': it differs too (the French bread, 2707610, is a hit in
    // no recorded answer). Its live run (snapshot 13) recorded the 13
    // searches and 12 details it fetched, and the answers the v17 pins read
    // (tapioca 169717, spareribs 167853, and four searches): 14 more
    // compared — 12 newly recorded foods and two recorded before that are
    // hits in the new answers ('french bread' 2707610, 'iceberg lettuce'
    // 2346388); all but celery, carrots, napa and iceberg (169988, 170393,
    // 169979, 169248) differ in some digit. Matcher v18 (the density
    // guard) recorded the 12 records its pins read from snapshot 13: seven
    // are hits ('ice cream' 167575 and 168809, 'oil-packed tuna' 169384,
    // 'radishes' 170122, 'ricotta cheese' 171248, 'cream cheese' 173418,
    // 'seedless raspberry jam' 2747675) and all but the radish differ in
    // some digit. Matcher v19 (Run 050's grams) recorded the eight records
    // its pins read from snapshot 13: five are hits ('salt' 2707517,
    // 'sweetened coconut' 2707571, 'butter' 2707533, 'mcintosh apples'
    // 168816, 'hazelnuts' 2707502), all five differ in some digit.
    // Matcher v20 (Run 051's grams) recorded the three records its pins
    // read from snapshot 13: two are hits ('dutch-processed cocoa powder'
    // 169594, 'snow peas' 170010; mustard greens 169256 is in no recorded
    // answer): the cocoa differs in some digit, the peas are equal.
    // Matcher v21 recorded from snapshot 13 the answers and the cached
    // records its 198 moved rows read (and the apricot preserves, 170645,
    // and the Duchess casserole's half-and-half and nutmeg answers, and
    // the black olives, 2710090, for the below-gate marked-count pins):
    // 68 more compared, 48 of them differ in some digit. Matcher v23
    // recorded the gelatin dessert (2710310) and the coconut water (2707572)
    // for the _asPrepared keep-side pins: the coconut water is a hit (in
    // 'unsweetened' and 'unsweetened desiccated coconut'), equal in every
    // digit. Matcher v24 recorded four searches for the H5(a) pick pins (0279
    // and 0129 Indoor Pulled Chicken: 'sichuan peppercorns', 'liquid
    // smoke', 'boneless skinless chicken thighs', 'hot sauce'): one more
    // recorded food is a hit in them, equal in every digit (differ stays).
    // Matcher v25 recorded 0491 Tostadas' five searches and one record for
    // the RULE C matches-GET pin ('ground chipotle powder', 'corn
    // tortillas', 'queso fresco or feta cheese', 'avocado', 'lime wedges';
    // 'Tortilla, corn' 2707823): the tortilla is a hit, differing in some
    // digit. Matcher v27 recorded 'Tomato, roma' (1999634) for c1's zero_row
    // route pin (its confirm derives on the food; the v26 fixture miss had
    // passed silently as an outage, Run 057 O17): a hit, differing in some
    // digit; and the peppercorn pork tenderloin (168317) a v27 O3 pin picks
    // from 0279's peppercorn candidates (a hit too, differing in a digit).
    // The v27 closer recorded the Sichuan peppercorns' own record (168093)
    // for FDC's answer once an outage ends (its D2/D7 pins): a hit in
    // 'sichuan peppercorns', differing in some digit. Matcher v30 recorded
    // the three bone-in records its Q7 pins read from snapshot 13 (the rib
    // roast 168675, the back ribs 173405, the turkey thigh 171533): each a
    // hit in a recorded answer, each differing in some digit. Matcher v31
    // recorded from snapshot 13 the answers and records its A, B and C pins
    // read (and the records its re-pinned older pins moved to): 24 more
    // compared, 19 of them differ in some digit. Its round-3 closer
    // recorded the whole orange (2709171) and ground ginger (170926) for
    // the per-inch record-gate pin: two more compared, both differing in
    // some digit. Matcher v32 recorded the live step's 12 details from its
    // scratch copy: 11 are hits in a recorded answer (the egg, 171287, is
    // in none), 9 of them differing in some digit. Matcher v35 recorded
    // the portabella (169255) from the 2026-10-04 live copy: a hit in
    // 'mushrooms portabella raw', differing in some digit (niacin).
    expect(compared, 348);
    expect(differ, 262);
  });

  group('lazy food details on real corpus recipes', skip: skipIfNoCorpus, () {
    // Recipes by slug, imported into a fresh library.
    Future<(SaltDatabase, Map<String, Recipe>)> library(
      List<String> files,
    ) async {
      final tmp = Directory.systemTemp.createTempSync('salt-lazy');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final config = ServerConfig(
        dataDir: tmp.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      final db = SaltDatabase.open(config.dbPath);
      addTearDown(db.dispose);
      Directory('${tmp.path}/source/recipes').createSync(recursive: true);
      for (final name in files) {
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${tmp.path}/source/recipes/$name');
      }
      importSourceRoot(
        sourceRootPath: '${tmp.path}/source',
        db: db,
        config: config,
      );
      return (
        db,
        {
          for (final name in files)
            name.substring(5, name.length - 5): db
                .recipeByIdOrSlug(name.substring(5, name.length - 5))!
                .recipe,
        },
      );
    }

    (IngredientLine, IngredientMatchRow, int) rowIn(
      SaltDatabase db,
      Recipe recipe,
      String raw,
    ) {
      final lines = nutritionLines(recipe);
      final position = lines.indexWhere((line) => line.raw == raw);
      expect(position, isNonNegative, reason: raw);
      return (
        lines[position],
        db
            .ingredientMatchesFor(recipe.id)
            .firstWhere((row) => row.position == position),
        position,
      );
    }

    test('a food whose detail an earlier line cached keeps its portions on '
        'the next volume line', () async {
      final (db, recipes) = await library([
        '0159-julia-childs-stuffed-turkey-updated.yaml',
        '0005-best-beef-stew.yaml',
      ]);
      final provider = _Recording();
      await matchAndCompute(
        db,
        provider,
        recipes['julia-childs-stuffed-turkey-updated']!,
      );
      await matchAndCompute(db, provider, recipes['best-beef-stew']!);
      final (line, row, _) = rowIn(
        db,
        recipes['best-beef-stew']!,
        '2 tablespoons vegetable oil',
      );
      final detail = (await provider.inner.food(row.fdcId!))!;
      final expected = resolveGrams(
        amounts: line.amounts,
        food: detail,
        normalizedItem: normalizeItem(line.item ?? line.raw),
        raw: line.raw,
      )!;
      expect(expected.source, GramSource.portion);
      expect(row.gramSource, 'portion');
      expect(row.grams, expected.grams);
      expect(provider.fetched.where((id) => id == row.fdcId), hasLength(1));
    });

    // v27 (RULE A, Run 057 Opus critic 1): a target whose portion fetch
    // fails is weighed inside the one outcome — not written, counted
    // `unavailable`, never `failed` (no recipe failed).
    test('apply_to_all fetches the portions a target needs, and counts a '
        'failed fetch in `unavailable`', () async {
      final (db, recipes) = await library([
        '0013-ultimate-cream-of-tomato-soup.yaml',
        '0857-rich-chocolate-bundt-cake.yaml',
      ]);
      final soup = recipes['ultimate-cream-of-tomato-soup']!;
      final bundt = recipes['rich-chocolate-bundt-cake']!;
      final provider = _Recording();
      await matchAndCompute(db, provider, soup);
      await matchAndCompute(db, provider, bundt);
      // The review sheet's own search: a person looks up another flour.
      final pick = (await searchCandidates(
        db,
        provider,
        'whole-wheat flour',
      )).first.candidate.fdcId;
      expect(db.fdcFoodCacheGet(pick), isNull);
      const weighed = '1¾ cups (8¾ ounces) unbleached all-purpose flour';
      const spoons = '2 tablespoons unbleached all-purpose flour';
      final (_, before, position) = rowIn(db, bundt, weighed);
      expect(before.fdcId, isNot(pick));
      final target = rowIn(db, soup, spoons).$2;

      provider.down = true;
      final Object? failedRun;
      try {
        failedRun = await applyMatchOverride(db, provider, bundt, position, {
          'fdc_id': pick,
          'apply_to_all': true,
        });
      } finally {
        provider.down = false;
      }
      expect(
        failedRun,
        appliedIs(
          recipes: 0,
          lines: 0,
          failed: 0,
          completed: 0,
          unavailable: 1,
        ),
      );
      expect(rowIn(db, soup, spoons).$2.fdcId, target.fdcId);

      final applied = await applyMatchOverride(db, provider, bundt, position, {
        'fdc_id': pick,
        'apply_to_all': true,
      });
      expect(applied, appliedIs(recipes: 1, lines: 1, failed: 0, completed: 0));
      expect(rowIn(db, soup, spoons).$2.fdcId, pick);
      expect(provider.fetched, contains(pick));
      expect(db.fdcFoodCacheGet(pick), isNotNull);
    });

    test('a decision on a superseded (detail-404) food survives the next '
        'compute, and no compute asks FDC for that 404 again', () async {
      final (db, recipes) = await library([
        '0857-rich-chocolate-bundt-cake.yaml',
        '0072-skillet-tamale-pie.yaml',
      ]);
      final bundt = recipes['rich-chocolate-bundt-cake']!;
      final pie = recipes['skillet-tamale-pie']!;
      final provider = _Recording()..detail404 = true;
      await matchAndCompute(db, provider, bundt);
      await matchAndCompute(db, provider, pie);
      const flour = '1¾ cups (8¾ ounces) unbleached all-purpose flour';
      const pieFlour = '¾ cup (3¾ ounces) unbleached all-purpose flour';
      final (line, row, position) = rowIn(db, bundt, flour);
      final pick = (await candidatesForLine(
        db,
        provider,
        line,
        cacheOnly: true,
      )).firstWhere((c) => c.candidate.fdcId != row.fdcId).candidate.fdcId;
      await applyMatchOverride(db, provider, bundt, position, {
        'fdc_id': pick,
        'apply_to_all': true,
      });
      expect(rowIn(db, pie, pieFlour).$2.fdcId, pick);

      final calls = provider.fetched.length + provider.searched.length;
      await matchAndCompute(db, provider, pie);
      await matchAndCompute(db, provider, bundt);
      final after = rowIn(db, pie, pieFlour).$2;
      expect(after.fdcId, pick);
      expect(after.confidence, 1);
      expect(
        provider.fetched.length + provider.searched.length,
        calls,
        reason: 'every 404 was remembered: ${provider.fetched}',
      );
    });

    test('an override on a superseded (detail-404) food survives an edit of '
        "the line's amount: still overridden, and FDC is not asked", () async {
      final (db, recipes) = await library([
        '0857-rich-chocolate-bundt-cake.yaml',
      ]);
      final bundt = recipes.values.single;
      final provider = _Recording()..detail404 = true;
      await matchAndCompute(db, provider, bundt);
      const flour = '1¾ cups (8¾ ounces) unbleached all-purpose flour';
      final (line, row, position) = rowIn(db, bundt, flour);
      final pick = (await candidatesForLine(
        db,
        provider,
        line,
        cacheOnly: true,
      )).firstWhere((c) => c.candidate.fdcId != row.fdcId).candidate.fdcId;
      await applyMatchOverride(db, provider, bundt, position, {'fdc_id': pick});

      final lines = nutritionLines(bundt);
      db.upsertRecipe(
        bundt.copyWith(
          ingredients: [
            IngredientGroup(
              items: [
                for (final (i, l) in lines.indexed)
                  i == position
                      ? IngredientLine(
                          raw: l.raw.replaceFirst('1¾ cups', '2 cups'),
                          item: l.item,
                          prep: l.prep,
                          amounts: l.amounts,
                        )
                      : l,
              ],
            ),
          ],
        ),
        sourceSlug: db.recipeByIdOrSlug(bundt.id)!.sourceSlug,
        contentHash: 'edited-flour',
      );
      final edited = db.recipeByIdOrSlug(bundt.id)!.recipe;
      provider.fetched.clear();
      await matchAndCompute(db, provider, edited);
      final after = rowIn(
        db,
        edited,
        flour.replaceFirst('1¾ cups', '2 cups'),
      ).$2;
      expect(after.fdcId, pick);
      expect(after.status, 'overridden');
      expect(provider.fetched, isEmpty);
    });

    test(
      'a hit with no nutrients is not the food: its detail is fetched '
      '(negative path: the recorded answer with its top hit stripped)',
      () async {
        const file = '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml';
        final (db, recipes) = await library([file]);
        final mujaddara = recipes.values.single;
        final line = nutritionLines(mujaddara).firstWhere(
          (line) => line.raw == '1 teaspoon sugar',
        );
        final search = lineSearchFor(
          db,
          normalizeItem(line.item ?? line.raw),
          itemKeyFor(line.item ?? line.raw),
        );
        final provider = _Recording();
        final hits = await provider.inner.search(search.answer);
        final first = rankCandidates(search.query, hits).first.candidate.fdcId;
        final stripped = [
          for (final hit in hits)
            FdcCandidate(
              fdcId: hit.fdcId,
              description: hit.description,
              dataType: hit.dataType,
              nutrientsPer100g: hit.fdcId == first
                  ? null
                  : hit.nutrientsPer100g,
            ),
        ];
        final top = rankCandidates(search.query, stripped).first.candidate;
        expect(
          top.nutrientsPer100g,
          isNull,
          reason: 'the stripped hit ranks top',
        );
        expect(await provider.inner.food(top.fdcId), isNotNull);
        db.fdcSearchCachePut(
          search.answer,
          jsonEncode([for (final hit in stripped) hit.toJson()]),
        );
        await matchAndCompute(db, provider, mujaddara);
        final (_, row, _) = rowIn(db, mujaddara, '1 teaspoon sugar');
        expect(provider.fetched, contains(top.fdcId));
        expect(row.fdcId, top.fdcId);
      },
    );

    test("a sibling answer is ranked under the line's own words when the "
        'engine matches it', () async {
      // The egg of Duchess Potato Casserole's egg-plus-yolks line, keyed
      // 'egg plus yolk' (cardamom pods until v21 rewrote them): 'egg' and
      // 'egg plus yolk' rank apart.
      const file = '0447-duchess-potato-casserole.yaml';
      final (db, recipes) = await library([file]);
      final provider = _Recording();
      final answer = await provider.inner.search('egg');
      db.fdcSearchCachePut(
        'egg plus yolk',
        jsonEncode([for (final hit in answer) hit.toJson()]),
      );
      final casserole = recipes.values.single;
      await matchAndCompute(db, provider, casserole);
      final (_, row, _) = rowIn(
        db,
        casserole,
        '1 large egg, separated, plus 2 large yolks',
      );
      expect(provider.searched, isNot(contains('egg')));
      expect(row.fdcId, isNotNull);
      expect(
        [
          for (final c in rankCandidates('egg', answer).take(3))
            (c.candidate.fdcId, c.confidence),
        ],
        contains((row.fdcId, row.confidence)),
      );
      expect(
        row.fdcId,
        isNot(rankCandidates('egg plus yolk', answer).first.candidate.fdcId),
      );
    });
  });
}
