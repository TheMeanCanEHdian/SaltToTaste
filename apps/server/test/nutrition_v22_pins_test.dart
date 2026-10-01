// Run 052's pin-vacuity findings (F9), server half: each a real killing
// test on corpus lines (synthesized edits stated where made). The pairing
// cases come from a 4,000-seed twin-heavy probe over 0405's lines (scratch,
// deleted): each is a seed where the named mutant pairs differently.
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

IngredientMatchRow rowFor(int position, IngredientLine line, String status) =>
    IngredientMatchRow(
      recipeId: 'r',
      position: position,
      raw: line.raw,
      itemKey: lineKeyOf(line),
      fdcId: null,
      description: null,
      dataType: null,
      confidence: 0,
      grams: null,
      gramSource: null,
      status: status,
    );

void main() {
  group(
    'the layout cost tie-breaks (Run 052 S12/O12), on 0405 lines',
    () {
      late List<IngredientLine> all;
      setUpAll(() {
        all = nutritionLines(
          loadCorpusRecipe(
            '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
          ),
        );
      });

      // Rows laid out on 0405's lines [v0] with [statuses] (c confirmed, o
      // overridden, a auto, s skipped), the recipe saved as [v1]: the row
      // positions each new line takes.
      List<Object> pair(List<int> v0, String statuses, List<int> v1) {
        const names = {
          'c': 'confirmed',
          'o': 'overridden',
          'a': 'auto',
          's': 'skipped',
        };
        final rows = [
          for (final (i, at) in v0.indexed)
            rowFor(i, all[at], names[statuses[i]]!),
        ];
        return [
          for (final row in pairRowsToLines(
            rows,
            [for (final at in v1) all[at]],
            laidOut: [for (final at in v0) all[at].raw],
          ))
            row?.position ?? '-',
        ];
      }

      test('the moved term: rows stay at their own positions (a layout is '
          'its own next layout) — probe seed 57', () {
        expect(pair([3, 3, 5, 5, 4], 'cooas', [5, 3, 5, 4]), [3, 1, 2, 4]);
      }, skip: skipIfNoCorpus);

      test('moved before drift — probe seed 429', () {
        expect(
          pair([4, 1, 4, 4, 4], 'oosac', [1, 4, 5, 4, 4, 4]),
          [1, 2, '-', 3, 4, 0],
        );
      }, skip: skipIfNoCorpus);

      test(
        'strict < : a full tie keeps the in-order seed — probe seed 466',
        () {
          expect(pair([3, 5, 2, 5, 4], 'coooa', [2, 3, 5, 4]), [2, 0, 1, 4]);
        },
        skip: skipIfNoCorpus,
      );
    },
    skip: skipIfNoCorpus,
  );

  test("the exact-text fit term (Run 052 S9): 0028's keyless line "
      '"(about ¾ cup)", skipped and saved unchanged, keeps its skip', () {
    final line = nutritionLines(
      loadCorpusRecipe('0028-hearty-minestrone.yaml'),
    ).firstWhere((l) => l.raw == '(about ¾ cup)');
    expect(lineKeyOf(line), isEmpty);
    expect(
      [
        for (final row in pairRowsToLines([rowFor(0, line, 'skipped')], [line]))
          row?.position,
      ],
      [0],
    );
  }, skip: skipIfNoCorpus);

  test("the ' or ' split of the head-noun rule (Run 052 O10): \"1 cup dry "
      'white wine or dry vermouth" (Mushroom Risotto) keeps the wine key\'s '
      "density on 2710689 — an alternative's head is the key's", () async {
    const raw = '1 cup dry white wine or dry vermouth';
    final parsed = parseIngredientLine(raw);
    final g = lineGrams(
      wp.tempDb(),
      IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts),
      await FixtureProvider().food(2710689),
    );
    expect(g?.source, GramSource.density);
    expect(g?.grams, closeTo(234.22, 0.01));
  });

  group("editedDecisionRow's no-food branch (Run 052 S10/O11): the decided "
      'food 173468 no cache holds and FDC 404s', () {
    // A typed 5 g on 0090-style "½ teaspoon table salt" (a real line
    // shape; the row is written directly, the edits are synthesized).
    Future<IngredientMatchRow> afterEdit(String to, {bool typed = true}) async {
      final db = wp.tempDb();
      final provider = FixtureProvider(superseded: {173468});
      const from = '½ teaspoon table salt';
      final v0 = wp.saveLines(db, [from]);
      layoutMatchRows(db, v0);
      final line = nutritionLines(v0).single;
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: 'r',
          position: 0,
          raw: from,
          itemKey: lineKeyOf(line),
          fdcId: 173468,
          description: 'Salt, table',
          dataType: 'SR Legacy',
          confidence: 1,
          grams: typed ? 5 : 3.0,
          gramSource: typed ? 'override' : 'density',
          status: typed ? 'overridden' : 'confirmed',
        ),
      );
      final v1 = wp.saveLines(db, [to]);
      await matchAndCompute(db, provider, v1);
      return db.ingredientMatchesFor('r').single;
    }

    test('an amount edit clears the typed grams', () async {
      final row = await afterEdit('¾ teaspoon table salt');
      expect((row.fdcId, row.grams, row.gramSource), (173468, null, null));
    });

    test('a prep-only rewrite keeps them', () async {
      final row = await afterEdit('½ teaspoon table salt, divided');
      expect((row.grams, row.gramSource), (5, 'override'));
    });

    test('untyped grams are never kept, even on the same amount', () async {
      final row = await afterEdit(
        '½ teaspoon table salt, divided',
        typed: false,
      );
      expect((row.grams, row.gramSource), (null, null));
    });
  });

  test("the matches GET pairs with the layout's texts (Run 052 S4/S11): "
      'laid out on [½ cup oil, ½ cup oil] with the first row a skip still '
      'carrying its ¾ cup text, a save deletes line 1 — the GET shows line '
      '0 the skip the next layout gives it, not the second row', () async {
    // Real corpus lines; the rows are written directly (a stated
    // exception: the skip's stale text is a mid-edit state — a pairing
    // probe over these lines, scratch, found it).
    const three = '¾ cup extra-virgin olive oil';
    const half = '½ cup extra-virgin olive oil';
    final db = wp.tempDb();
    final v0 = wp.saveLines(db, [half, half]);
    layoutMatchRows(db, v0);
    IngredientMatchRow row(int p, String raw, String status) =>
        IngredientMatchRow(
          recipeId: 'r',
          position: p,
          raw: raw,
          itemKey: lineKeyOf(wp.lineOf(raw)),
          fdcId: null,
          description: null,
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: status,
        );
    db
      ..upsertIngredientMatch(row(0, three, 'skipped'))
      ..upsertIngredientMatch(row(1, half, 'auto'));
    final v1 = wp.saveLines(db, [half]);
    final item =
        ((await matchesBody(db, FixtureProvider(), v1))['items']! as List)
                .single
            as Map<String, Object?>;
    expect((item['match']! as Map)['status'], 'skipped');
    layoutMatchRows(db, v1);
    expect(db.ingredientMatchesFor('r').single.status, 'skipped');
  });

  test('the basis is read from the STORED recipe at stamp time (Run 052 '
      "S13): 0816's yield saved as 44 cookies (synthesized) while a first "
      'compute of the 22-cookie copy runs stamps per 44', () async {
    final db = wp.tempDb();
    final r = loadCorpusRecipe('0816-molasses-spice-cookies.yaml');
    expect((r.serves, parseYieldCount(r.servings)?.min), (null, 22));
    wp.saveRecipe(db, r.copyWith(servings: 'MAKES ABOUT 44 COOKIES'));
    await recomputeTotals(db, FixtureProvider(), r);
    expect(db.nutritionFor(r.id)!.servingBasis, 44);
  }, skip: skipIfNoCorpus);

  test(
    'the compute re-run stops at maxComputePasses (Run 052 S13): a '
    'save during every pass leaves it stale, and the loop ends at 3',
    () async {
      final db = wp.tempDb();
      final inner = FixtureProvider(pending: <String>{});
      var saves = 0;
      // Each search saves the recipe with a new line (synthesized words FDC
      // answers with no hits), so every pass's stamp is stale.
      final provider = _OnSearch(inner, () {
        saves++;
        final word = 'zq${String.fromCharCode(97 + saves)}';
        inner.pending.add(word);
        wp.saveLines(db, ['½ teaspoon table salt', '1 cup $word']);
      });
      final v0 = wp.saveLines(db, ['½ teaspoon table salt', '1 cup zqa']);
      inner.pending.add('zqa');
      expect(await computeUntilFresh(db, provider, v0), maxComputePasses);
      expect(maxComputePasses, 3);
      expect(nutritionIsFresh(db, db.recipeByIdOrSlug('r')!.recipe), isFalse);
    },
  );

  group("O13's survivors", () {
    test('sameMatchRow is the whole identity: a row differing only in its '
        'text, its food or its grams is another row', () {
      final line = wp.lineOf('½ teaspoon table salt');
      final a = rowFor(0, line, 'overridden').copyWith(fdcId: 173468, grams: 3);
      expect(sameMatchRow(a, a.copyWith()), isTrue);
      expect(
        sameMatchRow(a, a.copyWith(raw: '¾ teaspoon table salt')),
        isFalse,
      );
      expect(sameMatchRow(a, a.copyWith(fdcId: 746784)), isFalse);
      expect(sameMatchRow(a, a.copyWith(grams: 4)), isFalse);
    });

    test("the receipt's wire carries `moved`", () {
      final json = appliedJson((
        recipes: 1,
        lines: 1,
        failed: 0,
        completed: 0,
        completedRecipes: const [],
        moved: 2,
        decided: 0,
        gone: 0,
        failedLines: 0,
      ));
      expect(json['moved'], 2);
    });

    test('a layout of a recipe deleted meanwhile keeps no layout (and no '
        'foreign-key failure)', () {
      final db = wp.tempDb()
        ..relayoutIngredientMatches(
          'gone',
          drop: const {},
          moves: const {},
          lines: const ['½ teaspoon table salt'],
        );
      expect(db.layoutOf('gone').seq, 0);
    });

    test("editedDecisionRow re-keys the carried row to its line: 0463's "
        "'strip steaks' pick, retyped through the editor's parse (key "
        "'steak', synthesized edit), stores the line's key", () async {
      final db = wp.tempDb();
      final corpus = loadCorpusRecipe(
        '0463-steak-au-poivre-with-brandied-cream-sauce.yaml',
      );
      final line = nutritionLines(
        corpus,
      ).firstWhere((l) => l.raw.contains('strip steaks'));
      final v0 = wp
          .saveLines(db, [line.raw])
          .copyWith(
            ingredients: [
              IngredientGroup(items: [line]),
            ],
          );
      wp.saveRecipe(db, v0);
      layoutMatchRows(db, v0);
      db.upsertIngredientMatch(
        rowFor(0, line, 'skipped'),
      );
      final retyped = wp.lineOf(
        '2 (8- to 10-ounce) strip steaks, ¾ to 1 inch thick, trimmed',
      );
      final v1 = v0.copyWith(
        ingredients: [
          IngredientGroup(items: [retyped]),
        ],
      );
      wp.saveRecipe(db, v1);
      await matchAndCompute(db, FixtureProvider(), v1);
      final row = db.ingredientMatchesFor('r').single;
      expect((row.status, row.itemKey), ('skipped', 'steak'));
    }, skip: skipIfNoCorpus);
  });
}

class _OnSearch implements NutritionProvider {
  _OnSearch(this.inner, this.onSearch);
  final NutritionProvider inner;
  final void Function() onSearch;

  @override
  Future<List<FdcCandidate>> search(String query) {
    onSearch();
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) => inner.food(fdcId);
}
