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
      final items = (await matchesBody(db, provider, v1))['items']! as List;
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
