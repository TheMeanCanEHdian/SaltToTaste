// The pairing's same-ingredient carries (pairRowsToLines) under edits of
// MORE than one line in one save — the pairing oracle
// (pairing_oracle_test.dart) explains every edit as ONE op, so it never
// reaches them. Real data: 0405 Acquacotta's lines and 0856's "¾ cup
// extra-virgin olive oil"; the edits (two changes in one save, and "1 cup
// extra-virgin olive oil", 0405's "¼ cup" line with its amount changed) are
// synthesized, a stated exception. Also what the oracle cannot interleave: a
// save and a person's write while a compute of the PREVIOUS version awaits
// FDC, and the matches GET between a save and the next compute.
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

void main() {
  const oilHalf = '½ cup extra-virgin olive oil';
  const oilQuarter = '¼ cup extra-virgin olive oil';

  /// 0405 computed, a person's 3 g pick on line [picked]; then [edit]
  /// saved and computed. The positions and raws of the decided rows.
  Future<List<(int, String)>> pickThenEdit(
    int picked,
    List<IngredientGroup> Function(List<IngredientGroup> groups) edit,
  ) async {
    final dir = Directory.systemTemp.createTempSync('salt-pairing');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db')
      ..upsertSource(slug: 'src', name: 'Test', type: 'book');
    addTearDown(db.dispose);
    final provider = FixtureProvider(pending: pendingSearches);
    final acqua = loadCorpusRecipe(
      '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
    );
    for (final r in [
      acqua,
      acqua.copyWith(ingredients: edit(acqua.ingredients)),
    ]) {
      db.upsertRecipe(r, sourceSlug: 'src', contentHash: contentHashOf(r));
      await matchAndCompute(db, provider, r);
      if (identical(r, acqua)) {
        expect(nutritionLines(r)[4].raw, oilHalf);
        expect(nutritionLines(r)[17].raw, oilQuarter);
        await applyMatchOverride(db, provider, r, picked, {
          'fdc_id': 173468,
          'grams': 3,
        });
      }
    }
    return [
      for (final row in db.ingredientMatchesFor(acqua.id))
        if (row.status == 'overridden') (row.position, row.raw),
    ];
  }

  IngredientLine threeQuarter() => loadCorpusRecipe('0856-olive-oil-cake.yaml')
      .ingredients
      .expand((g) => g.items)
      .firstWhere((l) => l.raw == '¾ cup extra-virgin olive oil');
  IngredientLine amountEdit(IngredientLine line, String raw) {
    final parsed = parseIngredientLine(raw);
    return line.copyWith(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  test('the SOUP "½ cup" oil (picked) moved to the end of TOAST and edited '
      'to "¾ cup" in one save keeps its pick, on its new line only', () async {
    final decided = await pickThenEdit(4, (groups) {
      final [soup, toast] = groups;
      return [
        soup.copyWith(items: [...soup.items]..removeAt(4)),
        toast.copyWith(items: [...toast.items, threeQuarter()]),
      ];
    });
    expect(decided, [(18, '¾ cup extra-virgin olive oil')]);
  }, skip: skipIfNoCorpus);

  test('both oil lines amount-edited in one save ("½ cup" → "¾ cup", the '
      'picked "¼ cup" → "1 cup"): the pick stays on its own line, never on '
      'the first line of its ingredient', () async {
    final decided = await pickThenEdit(17, (groups) {
      final [soup, toast] = groups;
      return [
        soup.copyWith(items: [...soup.items]..[4] = threeQuarter()),
        toast.copyWith(
          items: [...toast.items]
            ..[1] = amountEdit(toast.items[1], '1 cup extra-virgin olive oil'),
        ),
      ];
    });
    expect(decided, [(17, '1 cup extra-virgin olive oil')]);
  }, skip: skipIfNoCorpus);

  test('the bread deleted AND the "¼ cup" oil edited to "Salt and pepper" in '
      'one save: the pick on the untouched "Salt and pepper" stays on it, '
      'never on the edited line (S5 in a two-edit save)', () async {
    final decided = await pickThenEdit(18, (groups) {
      final [soup, toast] = groups;
      final saltAndPepper = toast.items[2];
      return [
        soup,
        toast.copyWith(items: [saltAndPepper, saltAndPepper]),
      ];
    });
    expect(decided, [(17, 'Salt and pepper')]);
  }, skip: skipIfNoCorpus);

  // A save and a person's write while a compute of the previous version
  // awaits FDC (a synthesized interleaving of 0405's own lines).
  group('a compute of a version saved over', () {
    const sp = 'Salt and pepper';
    late SaltDatabase db;
    late _Hooked provider;
    late Recipe acqua;
    late Map<String, IngredientLine> byRaw;
    setUp(() {
      final dir = Directory.systemTemp.createTempSync('salt-pairing');
      addTearDown(() => dir.deleteSync(recursive: true));
      db = SaltDatabase.open('${dir.path}/salt.db')
        ..upsertSource(slug: 'src', name: 'Test', type: 'book');
      addTearDown(db.dispose);
      provider = _Hooked(FixtureProvider(pending: pendingSearches));
      acqua = loadCorpusRecipe(
        '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
      );
      byRaw = {
        for (final g in acqua.ingredients)
          for (final l in g.items) l.raw: l,
      };
    });
    Recipe version(List<String> raws) => acqua.copyWith(
      ingredients: [
        IngredientGroup(
          group: acqua.ingredients.first.group,
          items: [for (final r in raws) byRaw[r]!],
        ),
      ],
    );
    void save(Recipe r) =>
        db.upsertRecipe(r, sourceSlug: 'src', contentHash: contentHashOf(r));
    List<String> decisions(String id) => [
      for (final r in db.ingredientMatchesFor(id))
        if (r.status == 'skipped' || r.status == 'overridden')
          '${r.position}:${r.status}',
    ];

    test(
      "writes nothing once the recipe is saved over: the person's "
      'skip and the pick the new layout moved past its old end stand',
      () async {
        final v0 = version([sp, sp]);
        save(v0);
        await matchAndCompute(db, provider, v0);
        await applyMatchOverride(db, provider, v0, 1, {
          'fdc_id': 173468,
          'grams': 5,
        });
        final v1 = version([oilHalf, sp, sp]);
        final v2 = version([oilQuarter, oilHalf, sp, sp]);
        save(v1);
        Future<void>? put;
        provider.onCall = () {
          save(v2);
          put = applyMatchOverride(db, provider, v2, 1, {'skipped': true});
        };
        await matchAndCompute(db, provider, v1);
        expect(put, isNotNull, reason: 'the v1 compute never asked FDC');
        await put;
        await matchAndCompute(db, provider, v2);
        expect(decisions(v2.id), ['1:skipped', '3:overridden']);
      },
      skip: skipIfNoCorpus,
    );

    // P1 (Run 050): several edits in one save, then the compute. The rows
    // each decided line ends on: 'position:raw:status:grams'.
    List<String> decided(String id) => [
      for (final r in db.ingredientMatchesFor(id))
        if (r.status == 'skipped' || r.status == 'overridden')
          '${r.position}:${r.raw}:${r.status}:${r.grams}',
    ];
    const onion = '1 large onion, chopped coarse';
    const celery = '2 celery ribs, chopped coarse';

    test('Case A (Sonnet): the ½ cup oil deleted and the picked ¼ cup moved '
        'up in one save — the pick and its typed 5 g stay on it', () async {
      final v0 = version([oilHalf, sp, oilQuarter]);
      save(v0);
      await matchAndCompute(db, provider, v0);
      await applyMatchOverride(db, provider, v0, 2, {
        'fdc_id': 173468,
        'grams': 5,
      });
      final v1 = version([oilQuarter, sp]);
      save(v1);
      await matchAndCompute(db, provider, v1);
      expect(decided(v1.id), ['0:$oilQuarter:overridden:5.0']);
    }, skip: skipIfNoCorpus);

    test('Case B (Sonnet): the ¼ cup oil moved up and the ½ cup amount '
        'edited to "1 cup" in one save — the untouched line keeps its 9 g, '
        'the edited one its pick', () async {
      final v0 = version([onion, oilHalf, celery, oilQuarter]);
      save(v0);
      await matchAndCompute(db, provider, v0);
      for (final (at, g) in [(1, 3), (3, 9)]) {
        await applyMatchOverride(db, provider, v0, at, {
          'fdc_id': 173468,
          'grams': g,
        });
      }
      final oilOne = amountEdit(
        byRaw[oilHalf]!,
        '1 cup extra-virgin olive oil',
      );
      final v1 = acqua.copyWith(
        ingredients: [
          IngredientGroup(
            group: acqua.ingredients.first.group,
            items: [byRaw[onion]!, byRaw[oilQuarter]!, oilOne, byRaw[celery]!],
          ),
        ],
      );
      save(v1);
      await matchAndCompute(db, provider, v1);
      final rows = decided(v1.id);
      expect(rows, hasLength(2));
      expect(rows.first, '1:$oilQuarter:overridden:9.0');
      expect(rows.last, startsWith('2:${oilOne.raw}:overridden:'));
    }, skip: skipIfNoCorpus);

    test('the swap (Opus): the onion deleted, ½ → ¾ and ¼ → 1 cup, lemon '
        'appended in one save — the skip and the pick stay on their own '
        'oils', () async {
      const lemon = 'Lemon wedges';
      final v0 = version([onion, oilHalf, oilQuarter]);
      save(v0);
      await matchAndCompute(db, provider, v0);
      await applyMatchOverride(db, provider, v0, 1, {'skipped': true});
      await applyMatchOverride(db, provider, v0, 2, {
        'fdc_id': 173468,
        'grams': 3,
      });
      final threeQ = amountEdit(
        byRaw[oilHalf]!,
        '¾ cup extra-virgin olive oil',
      );
      final one = amountEdit(
        byRaw[oilQuarter]!,
        '1 cup extra-virgin olive oil',
      );
      final v1 = acqua.copyWith(
        ingredients: [
          IngredientGroup(
            group: acqua.ingredients.first.group,
            items: [threeQ, one, byRaw[lemon]!],
          ),
        ],
      );
      save(v1);
      await matchAndCompute(db, provider, v1);
      final rows = decided(v1.id);
      expect(rows.first, startsWith('0:${threeQ.raw}:skipped:'));
      expect(rows.last, startsWith('1:${one.raw}:overridden:'));
      expect(rows, hasLength(2));
    }, skip: skipIfNoCorpus);

    // P2 (Run 050): the gate reads the nutrition inputs (ingredientsHashOf),
    // not the whole document; a tripped gate never stamps the totals fresh.
    bool stale(Recipe r) =>
        db.nutritionFor(r.id)!.ingredientsHash != ingredientsHashOf(r);

    test('a tags-only save during the first compute blocks nothing: every '
        'line gets its row and the totals are fresh', () async {
      final v0 = version([oilHalf, sp, oilQuarter]);
      save(v0);
      final tagged = v0.copyWith(tags: [...v0.tags, 'weeknight']);
      provider.onCall = () => save(tagged);
      await matchAndCompute(db, provider, v0);
      expect(db.recipeByIdOrSlug(v0.id)!.recipe.tags, contains('weeknight'));
      expect(db.ingredientMatchesFor(v0.id), hasLength(3));
      expect(stale(tagged), isFalse);
    }, skip: skipIfNoCorpus);

    test('a lines save during a compute stops its writes and leaves the '
        'totals stale — even when a second save puts the lines back', () async {
      final v0 = acqua;
      final [soup, ...rest] = acqua.ingredients;
      final v1 = acqua.copyWith(
        ingredients: [
          soup.copyWith(items: soup.items.skip(1).toList()),
          ...rest,
        ],
      );
      save(v0);
      // The revert lands a few provider calls later, after a write.
      void Function() later(int calls, void Function() then) =>
          () => calls == 0 ? then() : provider.onCall = later(calls - 1, then);
      provider.onCall = () {
        save(v1);
        provider.onCall = later(3, () => save(v0));
      };
      await matchAndCompute(db, provider, v0);
      expect(db.recipeByIdOrSlug(v0.id)!.recipe, v0);
      expect(
        db.ingredientMatchesFor(v0.id).length,
        lessThan(nutritionLines(v0).length),
      );
      expect(stale(v0), isTrue);
    }, skip: skipIfNoCorpus);

    test("P5 (Run 050): the matches GET's apply-to-all offer counts the "
        "recipe's own rows as the layout places them — 0405 with a line "
        'inserted at the top, before the next compute, offers every line '
        'what it offered before the save', () async {
      save(acqua);
      await matchAndCompute(db, provider, acqua);
      Future<Map<String, Object?>> offers(Recipe r) async => {
        for (final i
            in ((await matchesBody(db, provider, r))['items']! as List)
                .cast<Map<String, Object?>>())
          i['raw']! as String: (i['others'], i['others_lines']),
      };
      final before = await offers(acqua);
      final [soup, ...rest] = acqua.ingredients;
      final v1 = acqua.copyWith(
        ingredients: [
          soup.copyWith(items: [threeQuarter(), ...soup.items]),
          ...rest,
        ],
      );
      save(v1);
      final after = await offers(v1);
      expect(after.remove(threeQuarter().raw), isNotNull);
      expect(after, before);
      // The critic's line: its only same-ingredient row is its own, never
      // an "other" (before the save or after it).
      expect(before['10 (½-inch-thick) slices thick-crusted country bread'], (
        0,
        0,
      ));
    }, skip: skipIfNoCorpus);

    test('the matches GET shows each line its own row before the next '
        'compute', () async {
      final v0 = version([oilHalf, sp]);
      save(v0);
      await matchAndCompute(db, provider, v0);
      await applyMatchOverride(db, provider, v0, 1, {
        'fdc_id': 173468,
        'grams': 5,
      });
      final v1 = version([oilQuarter, oilHalf, sp]);
      save(v1);
      // The GET pairs in memory and writes nothing (Run 050): the stored
      // rows are the same rows, at the same positions, after it.
      List<String> stored() => [
        for (final r in db.ingredientMatchesFor(v1.id))
          [
            r.position,
            r.raw,
            r.fdcId,
            r.grams,
            r.gramSource,
            r.status,
            r.itemKey,
          ].join('|'),
      ];
      final before = stored();
      final items = (await matchesBody(db, provider, v1))['items']! as List;
      expect(stored(), before);
      final status = [
        for (final i in items.cast<Map<String, Object?>>())
          (i['match'] as Map<String, Object?>?)?['status'],
      ];
      expect(status, [null, 'auto', 'overridden']);
    }, skip: skipIfNoCorpus);
  });
}

/// [FixtureProvider] running [onCall] once, at its next call (an await of
/// the compute).
class _Hooked implements NutritionProvider {
  _Hooked(this.inner);
  final FixtureProvider inner;
  void Function()? onCall;

  void _fire() {
    final hook = onCall;
    onCall = null;
    hook?.call();
  }

  @override
  Future<List<FdcCandidate>> search(String query) async {
    _fire();
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    _fire();
    return inner.food(fdcId);
  }
}
