// Run 051 B/C: the write paths. A person's decided row whose line a save
// edited to the same ingredient (B1–B3), the never-computed stamp (B4), the
// layout sequence every write checks (C1), a deleted recipe (B6), the basis
// read at stamp time (B7). Real corpus lines (the recipe named on each),
// recorded FDC answers (FixtureProvider), no corpus needed. Synthesized, a
// stated exception: the one-line test recipe holding a corpus line, the
// amount edits named on each test ("3 cups", "12 cups", "1 cup", the
// amountless "onion, chopped"), typed grams, and the saves a test makes
// during an await (a gated provider).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// FixtureProvider whose NEXT call first runs [onCall] (once): what lands
/// during that await of the caller.
class Gated implements NutritionProvider {
  Gated(this.inner);
  final NutritionProvider inner;
  Future<void> Function()? onCall;
  Future<void> _fire() async {
    final hook = onCall;
    onCall = null;
    if (hook != null) {
      await hook();
    }
  }

  @override
  Future<List<FdcCandidate>> search(String query) async {
    await _fire();
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    await _fire();
    return inner.food(fdcId);
  }
}

/// 0405 Acquacotta with only the lines [raws] (its own, in that order).
Recipe acquacotta(List<String> raws) {
  final acqua = loadCorpusRecipe(
    '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
  );
  final byRaw = {
    for (final group in acqua.ingredients)
      for (final line in group.items) line.raw: line,
  };
  return acqua.copyWith(
    ingredients: [
      IngredientGroup(
        group: acqua.ingredients.first.group,
        items: [for (final raw in raws) byRaw[raw] ?? lineOf(raw)],
      ),
    ],
  );
}

void saveRecipe(SaltDatabase db, Recipe recipe) => db.upsertRecipe(
  recipe,
  sourceSlug: 'src',
  contentHash: contentHashOf(recipe),
);

String dump(SaltDatabase db, String id) => [
  for (final r in db.ingredientMatchesFor(id))
    '${r.position}:${r.raw}:${r.status}:${r.fdcId}:${r.grams}',
].join(' | ');

const onion = '1 large onion, chopped coarse';
const celery = '2 celery ribs, chopped coarse';
const oil = '½ cup extra-virgin olive oil';

IngredientLine lineOf(String raw) {
  final parsed = parseIngredientLine(raw);
  return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
}

SaltDatabase tempDb() {
  final dir = Directory.systemTemp.createTempSync('salt-writepath');
  addTearDown(() => dir.deleteSync(recursive: true));
  final db = SaltDatabase.open('${dir.path}/salt.db')
    ..upsertSource(slug: 'src', name: 'Test', type: 'book');
  addTearDown(db.dispose);
  return db;
}

/// Recipe [id] of the lines [raws], saved (over any earlier version).
Recipe saveLines(
  SaltDatabase db,
  List<String> raws, {
  String id = 'r',
  int? serves,
}) {
  final recipe = Recipe(
    id: id,
    title: id,
    slug: id,
    source: const RecipeSource(name: 'Test', type: 'book'),
    serves: serves == null ? null : Serves(min: serves, max: serves),
    ingredients: [
      IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
    ],
  );
  db.upsertRecipe(
    recipe,
    sourceSlug: 'src',
    contentHash: 'h${raws.join('|')}$serves',
  );
  return recipe;
}

Recipe save(SaltDatabase db, String raw) => saveLines(db, [raw]);

IngredientMatchRow row(SaltDatabase db, [int position = 0]) =>
    db.ingredientMatchesFor('r').singleWhere((r) => r.position == position);

void main() {
  group('B1 (editedDecisionRow): one outcome for an edited decided line', () {
    test(
      'O11: "2 cups vegetable oil for frying" (Chicken Schnitzel, 0116) '
      'skipped, edited to "3 cups" and computed: the skipped row stays at '
      'the poured-away 0 g, and the un-skip counts 0 g, never 672 g',
      () async {
        final db = tempDb();
        final provider = FixtureProvider();
        final two = save(db, '2 cups vegetable oil for frying');
        await matchAndCompute(db, provider, two);
        expect((row(db).grams, row(db).gramSource), (0, 'discarded'));
        await applyMatchOverride(db, provider, two, 0, {'skipped': true});
        final three = save(db, '3 cups vegetable oil for frying');
        await matchAndCompute(db, provider, three);
        expect(
          (row(db).status, row(db).grams, row(db).gramSource),
          ('skipped', 0, 'discarded'),
        );
        await applyMatchOverride(db, provider, three, 0, {'skipped': false});
        expect((row(db).grams, row(db).gramSource), (0, 'discarded'));
        expect(db.nutritionFor('r')!.totalGrams, 0);
      },
    );

    test(
      'O12: the same oil typed at 20 g, skipped, edited to "3 cups": the '
      'typed 20 g stay through the compute and come back on the un-skip',
      () async {
        final db = tempDb();
        final provider = FixtureProvider();
        final two = save(db, '2 cups vegetable oil for frying');
        await matchAndCompute(db, provider, two);
        await applyMatchOverride(db, provider, two, 0, {
          'confirmed': true,
          'grams': 20,
        });
        await applyMatchOverride(db, provider, two, 0, {'skipped': true});
        final three = save(db, '3 cups vegetable oil for frying');
        await matchAndCompute(db, provider, three);
        expect((row(db).grams, row(db).gramSource), (20, 'override'));
        await applyMatchOverride(db, provider, three, 0, {'skipped': false});
        expect(db.nutritionFor('r')!.totalGrams, 20);
      },
    );

    for (final (from, to) in [
      // A grams-classified frying oil: no "for frying" in the text (Steak
      // Frites' "3 quarts peanut oil", 0464; "2 quarts vegetable oil", 1098;
      // "3 quarts" synthesized).
      ('2 quarts vegetable oil', '3 quarts vegetable oil'),
      // Its "for frying" twin (1084; 0316 / 0526 / …).
      (
        '1½ quarts vegetable oil for frying',
        '2 quarts vegetable oil for frying',
      ),
    ]) {
      test('S9: "$from" confirmed at a typed 30 g, edited to "$to" (two real '
          'lines) and computed: the 30 g stay, a medium by the outcome read '
          'with its grams', () async {
        final db = tempDb();
        final provider = FixtureProvider();
        final before = save(db, from);
        await matchAndCompute(db, provider, before);
        expect(row(db).grams, 0);
        await applyMatchOverride(db, provider, before, 0, {
          'confirmed': true,
          'grams': 30,
        });
        final after = save(db, to);
        await matchAndCompute(db, provider, after);
        expect(
          (row(db).raw, row(db).grams, row(db).gramSource),
          (to, 30, 'override'),
        );
        // Skipped through the same edit back: kept, and the un-skip counts it.
        await applyMatchOverride(db, provider, after, 0, {'skipped': true});
        final back = save(db, from);
        await matchAndCompute(db, provider, back);
        await applyMatchOverride(db, provider, back, 0, {'skipped': false});
        expect(db.nutritionFor('r')!.totalGrams, 30);
      });
    }

    test('S10: "1 onion, chopped fine" (31 corpus lines) typed at 40 g, '
        'rewritten to "1 onion, chopped" (Quinoa and Vegetable Stew, 0012) — '
        'the same amount: the typed 40 g stay, skipped or not', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final fine = save(db, '1 onion, chopped fine');
      await matchAndCompute(db, provider, fine);
      await applyMatchOverride(db, provider, fine, 0, {
        'confirmed': true,
        'grams': 40,
      });
      final chopped = save(db, '1 onion, chopped');
      await matchAndCompute(db, provider, chopped);
      expect((row(db).grams, row(db).gramSource), (40, 'override'));
      await applyMatchOverride(db, provider, chopped, 0, {'skipped': true});
      final again = save(db, '1 onion, chopped fine');
      await matchAndCompute(db, provider, again);
      expect(
        (row(db).status, row(db).grams, row(db).gramSource),
        ('skipped', 40, 'override'),
      );
      await applyMatchOverride(db, provider, again, 0, {'skipped': false});
      expect(db.nutritionFor('r')!.totalGrams, 40);
    });

    test('S15: "1 teaspoon grated lemon zest" (six recipes) typed at 3 g, '
        'skipped, edited to "2 (2-inch) strips lemon zest" (another real '
        'line) — since matcher v31 (Q6) a strip weighs 0.8 g an inch, so the '
        'row stores the edited line its own 3.20 g (until v31: no grams, no '
        'source), and the un-skip never revives the typed 3 g', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      const grated = '1 teaspoon grated lemon zest';
      const strips = '2 (2-inch) strips lemon zest';
      expect(lineKeyOf(lineOf(strips)), lineKeyOf(lineOf(grated)));
      final one = save(db, grated);
      await matchAndCompute(db, provider, one);
      await applyMatchOverride(db, provider, one, 0, {
        'confirmed': true,
        'grams': 3,
      });
      await applyMatchOverride(db, provider, one, 0, {'skipped': true});
      final edited = save(db, strips);
      await matchAndCompute(db, provider, edited);
      expect(
        (row(db).status, row(db).grams?.toStringAsFixed(2), row(db).gramSource),
        ('skipped', '3.20', 'piece'),
      );
      await applyMatchOverride(db, provider, edited, 0, {'skipped': false});
      expect(
        (row(db).grams?.toStringAsFixed(2), row(db).gramSource),
        ('3.20', 'piece'),
      );
      expect(db.nutritionFor('r')!.totalGrams, closeTo(3.2, 1e-9));
    });

    for (final skip in [true, false]) {
      test('B3 (O5): "10 cups Vanilla Frosting (recipe follows)" (Rainbow '
          'Cake, 1201) picked on "Butter, without salt" at a typed 500 g'
          '${skip ? ', then skipped' : ''}, edited to "12 cups": the pick '
          '${skip ? 'and the skip stand' : 'stands'}, never the 0 g '
          "sub-recipe row; the grams are the 12 cups' own", () async {
        final db = tempDb();
        final provider = FixtureProvider();
        final cake = save(db, '10 cups Vanilla Frosting (recipe follows)');
        await matchAndCompute(db, provider, cake);
        await applyMatchOverride(db, provider, cake, 0, {
          'fdc_id': 173430,
          'grams': 500,
        });
        if (skip) {
          await applyMatchOverride(db, provider, cake, 0, {'skipped': true});
        }
        final twelve = save(db, '12 cups Vanilla Frosting (recipe follows)');
        await matchAndCompute(db, provider, twelve);
        final got = row(db);
        expect(
          (got.status, got.fdcId),
          (skip ? 'skipped' : 'overridden', 173430),
        );
        expect(got.gramSource, isNot('override'));
        expect(got.grams, greaterThan(500));
      });
    }
    test('B3: a SKIP stands ahead of the sub-recipe rule — "4 Easy-Peel '
        'Hard-Cooked Eggs (this page), halved lengthwise" (Gado-Gado, 1192) '
        'skipped, edited to "1 recipe Easy-Peel Hard-Cooked Eggs (recipe '
        'follows)" (0731\'s line, the same key): still skipped, on the egg '
        '(a confirm there is the 0 g sub-recipe, v14 A1)', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final four = save(
        db,
        '4 Easy-Peel Hard-Cooked Eggs (this page), halved lengthwise',
      );
      await matchAndCompute(db, provider, four);
      final egg = row(db).fdcId;
      await applyMatchOverride(db, provider, four, 0, {'skipped': true});
      final deviled = save(
        db,
        '1 recipe Easy-Peel Hard-Cooked Eggs (recipe follows)',
      );
      await matchAndCompute(db, provider, deviled);
      expect((row(db).status, row(db).fdcId), ('skipped', egg));
    });
  });

  group("B2: a person's write in the stale window (saved, not computed)", () {
    /// The grams a fresh pick of 173468 gives "1 cup extra-virgin olive oil".
    Future<double> cupGrams() async {
      final db = tempDb();
      final provider = FixtureProvider();
      final cup = save(db, '1 cup extra-virgin olive oil');
      await matchAndCompute(db, provider, cup);
      await applyMatchOverride(db, provider, cup, 0, {'fdc_id': 173468});
      return row(db).grams!;
    }

    for (final verb in ['skip then un-skip', 'a bare confirm']) {
      test('S1: "½ cup extra-virgin olive oil" (Acquacotta, 0405) picked on '
          '173468 at a typed 3 g, saved as "1 cup", then $verb before any '
          "compute: the row carries the cup's grams, never the 3 g", () async {
        final want = await cupGrams();
        final db = tempDb();
        final provider = FixtureProvider();
        final half = save(db, '½ cup extra-virgin olive oil');
        await matchAndCompute(db, provider, half);
        await applyMatchOverride(db, provider, half, 0, {
          'fdc_id': 173468,
          'grams': 3,
        });
        final cup = save(db, '1 cup extra-virgin olive oil');
        const raw = '1 cup extra-virgin olive oil';
        if (verb == 'a bare confirm') {
          await applyMatchOverride(db, provider, cup, 0, {
            'raw': raw,
            'confirmed': true,
          });
        } else {
          await applyMatchOverride(db, provider, cup, 0, {
            'raw': raw,
            'skipped': true,
          });
          expect(row(db).grams, closeTo(want, 0.01));
          await applyMatchOverride(db, provider, cup, 0, {
            'raw': raw,
            'skipped': false,
          });
        }
        expect((row(db).raw, row(db).fdcId), (raw, 173468));
        expect(row(db).gramSource, isNot('override'));
        expect(row(db).grams, closeTo(want, 0.01));
        expect(db.nutritionFor('r')!.totalGrams, closeTo(want, 0.05));
      });
    }
  });

  group(
    'C1: the layout sequence every write checks (ABA)',
    skip: skipIfNoCorpus,
    () {
      for (final notes in [false, true]) {
        test('O1${notes ? ' (the revert also edits notes and category)' : ''}: '
            'a compute of 0405 [oil, onion, celery] awaits; meanwhile a save '
            'drops the oil, a pick on celery lays the rows out for it, and a '
            'save puts the oil back — the compute writes nothing more, stamps '
            'no hash, and the pick stands', () async {
          final db = tempDb();
          final provider = Gated(FixtureProvider(pending: pendingSearches));
          final v0 = acquacotta([onion, celery]);
          saveRecipe(db, v0);
          await matchAndCompute(db, provider, v0);
          final v1 = acquacotta([oil, onion, celery]);
          saveRecipe(db, v1);
          final v2 = acquacotta([onion, celery]);
          provider.onCall = () async {
            saveRecipe(db, v2);
            await applyMatchOverride(db, provider, v2, 1, {
              'raw': celery,
              'fdc_id': 173468,
              'grams': 5,
            });
            saveRecipe(
              db,
              notes ? v1.copyWith(category: 'Soups', notes: 'An edit.') : v1,
            );
          };
          await matchAndCompute(db, provider, v1);
          final picked = db
              .ingredientMatchesFor(v1.id)
              .where((r) => r.status == 'overridden')
              .toList();
          expect(
            [for (final r in picked) (r.raw, r.fdcId, r.grams)],
            [(celery, 173468, 5)],
            reason: dump(db, v1.id),
          );
          expect(db.nutritionFor(v1.id)!.ingredientsHash, '');
          // The next compute lays the rows out on the oil's return: the pick
          // rides with celery to position 2.
          await matchAndCompute(db, provider, v1);
          final after = db.ingredientMatchesFor(v1.id);
          expect(
            (after[2].raw, after[2].status, after[2].fdcId),
            (celery, 'overridden', 173468),
          );
          expect(
            db.nutritionFor(v1.id)!.ingredientsHash,
            ingredientsHashOf(v1),
          );
        });
      }

      test('Opus critic 2: a pick on onion (0405 [celery, onion], celery '
          'skipped) awaits its food; meanwhile a save swaps the lines, a layout '
          'moves the rows for it, and a save reverts — the pick lands on onion, '
          'the celery skip stands', () async {
        final db = tempDb();
        final provider = Gated(FixtureProvider(pending: pendingSearches));
        final v0 = acquacotta([celery, onion]);
        saveRecipe(db, v0);
        await matchAndCompute(db, provider, v0);
        await applyMatchOverride(db, provider, v0, 0, {'skipped': true});
        final swapped = acquacotta([onion, celery]);
        provider.onCall = () async {
          saveRecipe(db, swapped);
          layoutMatchRows(db, swapped);
          saveRecipe(db, v0);
        };
        await applyMatchOverride(db, provider, v0, 1, {
          'raw': onion,
          'fdc_id': 173468,
          'grams': 5,
        });
        final rows = db.ingredientMatchesFor(v0.id);
        expect(
          [for (final r in rows) (r.raw, r.status)],
          [(celery, 'skipped'), (onion, 'overridden')],
          reason: dump(db, v0.id),
        );
        expect(rows[1].grams, 5);
      });

      test("S16: a save deleting the line during the pick's await is a 409 "
          'line_moved (never a RangeError), and a deleted recipe a 404 (B6); '
          'nothing is written', () async {
        final db = tempDb();
        final provider = Gated(FixtureProvider(pending: pendingSearches));
        final v0 = acquacotta([celery, onion]);
        saveRecipe(db, v0);
        await matchAndCompute(db, provider, v0);
        provider.onCall = () async => saveRecipe(db, acquacotta([celery]));
        await expectLater(
          applyMatchOverride(db, provider, v0, 1, {
            'raw': onion,
            'fdc_id': 173468,
          }),
          throwsA(isA<LineMovedException>()),
        );
        expect(db.decisionFor(lineKeyOf(lineOf(onion))), isNull);
        // (A fresh database: the food is not cached, so the pick awaits it.)
        final other = tempDb();
        saveRecipe(other, v0);
        await matchAndCompute(other, provider, v0);
        provider.onCall = () async => other.deleteRecipe(v0.id);
        await expectLater(
          applyMatchOverride(other, provider, v0, 1, {
            'raw': onion,
            'fdc_id': 173468,
          }),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('S7: an apply-to-all of "Oil, olive" awaits a target\'s portions; '
          'meanwhile a save of that recipe drops its oil and a layout moves the '
          "onion skip onto the oil's position — the write is refused, counted "
          '`gone` (the oil line is gone from the recipe as stored: v24, Run '
          '054 S3 — `moved` before), and the skip stands', () async {
        final db = tempDb();
        final provider = Gated(FixtureProvider(pending: pendingSearches));
        Recipe b(List<String> raws) => acquacotta(raws).copyWith(id: 'b');
        final b0 = b([oil, onion, celery]);
        saveRecipe(db, b0);
        await matchAndCompute(db, provider, b0);
        await applyMatchOverride(db, provider, b0, 1, {'skipped': true});
        // A search hit stands in (no portions): the target's grams fetch.
        final full = (await FixtureProvider().food(173468))!;
        final standIn = FdcFood(
          fdcId: full.fdcId,
          description: full.description,
          dataType: full.dataType,
          nutrientsPer100g: full.nutrientsPer100g,
          portions: const [],
        );
        final b1 = b([onion, celery]);
        provider.onCall = () async {
          saveRecipe(db, b1);
          layoutMatchRows(db, b1);
        };
        final applied = await applyDecisionToOthers(
          db,
          provider,
          itemKey: lineKeyOf(lineOf(oil)),
          decided: standIn,
          excluding: (recipeId: 'a', position: 0),
        );
        expect((applied.lines, applied.moved, applied.gone), (0, 0, 1));
        final rows = db.ingredientMatchesFor('b');
        expect(
          [for (final r in rows) (r.raw, r.status)],
          [(onion, 'skipped'), (celery, 'auto')],
          reason: dump(db, 'b'),
        );
      });

      test('C1: a pick on onion awaits its food; meanwhile a save swaps the '
          'lines, a person skips onion there, and a save reverts — the row '
          'the layout now gives onion is not the one the pick read: 409 '
          'line_moved, the skip stands', () async {
        final db = tempDb();
        final provider = Gated(FixtureProvider(pending: pendingSearches));
        final v0 = acquacotta([celery, onion]);
        saveRecipe(db, v0);
        await matchAndCompute(db, provider, v0);
        final swapped = acquacotta([onion, celery]);
        provider.onCall = () async {
          saveRecipe(db, swapped);
          await applyMatchOverride(db, provider, swapped, 0, {
            'raw': onion,
            'skipped': true,
          });
          saveRecipe(db, v0);
        };
        await expectLater(
          applyMatchOverride(db, provider, v0, 1, {
            'raw': onion,
            'fdc_id': 173468,
          }),
          throwsA(isA<LineMovedException>()),
        );
        final rows = db.ingredientMatchesFor(v0.id);
        expect(
          [for (final r in rows) (r.raw, r.status)],
          [(celery, 'auto'), (onion, 'skipped')],
          reason: dump(db, v0.id),
        );
      });

      test('C1, a layout that moves no row: a compute of 0405 [oil, celery] '
          'awaits the oil; meanwhile a save edits celery\'s amount ("3 celery '
          'ribs", synthesized), a skip of it lays the rows on those lines, and '
          'a save reverts — the lines changed under the rows, so the compute '
          'writes nothing more and the skip stands', () async {
        final db = tempDb();
        final provider = Gated(FixtureProvider(pending: pendingSearches));
        final v0 = acquacotta([onion, celery]);
        saveRecipe(db, v0);
        await matchAndCompute(db, provider, v0);
        final v1 = acquacotta([oil, celery]);
        saveRecipe(db, v1);
        const three = '3 celery ribs, chopped coarse';
        final v2 = acquacotta([oil, three]);
        provider.onCall = () async {
          saveRecipe(db, v2);
          await applyMatchOverride(db, provider, v2, 1, {
            'raw': three,
            'skipped': true,
          });
          saveRecipe(db, v1);
        };
        await matchAndCompute(db, provider, v1);
        final at1 = db
            .ingredientMatchesFor(v1.id)
            .singleWhere(
              (r) => r.position == 1,
            );
        expect(
          (at1.raw, at1.status),
          (three, 'skipped'),
          reason: dump(db, v1.id),
        );
        expect(db.nutritionFor(v1.id)!.ingredientsHash, '');
      });
      test("E3 (Opus critic 2 #2): 0405's \"½ cup\" and \"¼ cup "
          'extra-virgin olive oil", the second edited to "¾ cup" (0856\'s '
          'line) and not computed, the first picked: the offer counts that '
          'row, and the apply writes it under the "¾ cup" text — offer == '
          'receipt', () async {
        final db = tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        const quarter = '¼ cup extra-virgin olive oil';
        const threeQuarters = '¾ cup extra-virgin olive oil';
        final v0 = acquacotta([oil, quarter]);
        saveRecipe(db, v0);
        await matchAndCompute(db, provider, v0);
        final v1 = acquacotta([oil, threeQuarters]);
        saveRecipe(db, v1);
        await applyMatchOverride(db, provider, v1, 0, {
          'raw': oil,
          'fdc_id': 173468,
        });
        final offer =
            ((await matchesBody(db, provider, v1))['items']! as List).first
                as Map<String, Object?>;
        expect((offer['others'], offer['others_lines']), (1, 1));
        final applied = await applyMatchOverride(db, provider, v1, 0, {
          'raw': oil,
          'confirmed': true,
          'apply_to_all': true,
        });
        expect((applied!.recipes, applied.lines, applied.moved), (1, 1, 0));
        final edited = db.ingredientMatchesFor(v1.id)[1];
        expect((edited.raw, edited.fdcId), (threeQuarters, 173468));
      });
    },
  );

  group('B4–B7: the stamp', skip: skipIfNoCorpus, () {
    test('B4: 0405 saved and never computed, its first line skipped: the '
        'totals stamp no hash, so the stale scope revisits it, and its '
        'compute fills every row', () async {
      final db = tempDb();
      final acqua = loadCorpusRecipe(
        '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
      );
      saveRecipe(db, acqua);
      await applyMatchOverride(db, FixtureProvider(), acqua, 0, {
        'skipped': true,
      });
      expect(db.nutritionFor(acqua.id)!.ingredientsHash, '');
      expect(bulkScopeIds(db, BulkScope.stale), [acqua.id]);
      await matchAndCompute(
        db,
        FixtureProvider(pending: pendingSearches),
        acqua,
      );
      expect(
        db.ingredientMatchesFor(acqua.id).length,
        nutritionLines(acqua).length,
      );
      expect(db.ingredientMatchesFor(acqua.id).first.status, 'skipped');
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    });

    test(
      "B5 (S2): a save during a compute job's await cuts its writes "
      'off; the job computes the saved recipe again before it ends',
      () async {
        final db = tempDb();
        final provider = Gated(FixtureProvider(pending: pendingSearches));
        final v1 = acquacotta([oil]);
        saveRecipe(db, v1);
        final v2 = acquacotta([oil, onion]);
        provider.onCall = () async => saveRecipe(db, v2);
        final job = startRecipeComputeJob(db, provider, v1);
        while (recipeComputeJobId(v1.id) != null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(db.nutritionJob(job)!['status'], 'done');
        expect(
          [for (final r in db.ingredientMatchesFor(v1.id)) r.raw],
          [oil, onion],
        );
        expect(db.nutritionFor(v1.id)!.ingredientsHash, ingredientsHashOf(v2));
      },
    );

    test("B6: a recipe deleted during its compute's await: the compute "
        'stops cleanly — no row, no totals, no foreign-key error', () async {
      final db = tempDb();
      final provider = Gated(FixtureProvider(pending: pendingSearches));
      final v1 = acquacotta([oil, onion]);
      saveRecipe(db, v1);
      provider.onCall = () async => db.deleteRecipe(v1.id);
      await matchAndCompute(db, provider, v1);
      expect(db.ingredientMatchesFor(v1.id), isEmpty);
      expect(db.nutritionFor(v1.id), isNull);
    });

    test('DB guard (v20 verifier D-1): the guarded upserts themselves refuse a '
        'stale layout sequence inside their transaction — a row written for '
        '0405 [onion] under the sequence before a relayout lands nothing, '
        'under the current one it lands (both upsertIngredientMatch and '
        'upsertIngredientMatchIfUndecided)', () {
      final db = tempDb();
      final v0 = acquacotta([onion, celery]);
      saveRecipe(db, v0);
      layoutMatchRows(db, v0);
      final before = db.layoutOf(v0.id).seq;
      // A relayout for a different line list bumps the sequence.
      final v1 = acquacotta([celery, onion]);
      saveRecipe(db, v1);
      layoutMatchRows(db, v1);
      final now = db.layoutOf(v1.id).seq;
      expect(now, isNot(before));
      IngredientMatchRow rowAt(int position) => IngredientMatchRow(
        recipeId: v1.id,
        position: position,
        raw: position == 0 ? celery : onion,
        itemKey: position == 0 ? 'celery' : 'onion',
        fdcId: null,
        description: null,
        dataType: null,
        confidence: 0,
        grams: null,
        gramSource: null,
        status: 'unmatched',
      );
      expect(db.upsertIngredientMatch(rowAt(0), layoutSeq: before), isFalse);
      expect(
        db.upsertIngredientMatchIfUndecided(rowAt(1), layoutSeq: before),
        isFalse,
      );
      expect(db.ingredientMatchesFor(v1.id), isEmpty);
      expect(db.upsertIngredientMatch(rowAt(0), layoutSeq: now), isTrue);
      expect(
        db.upsertIngredientMatchIfUndecided(rowAt(1), layoutSeq: now),
        isTrue,
      );
      expect(db.ingredientMatchesFor(v1.id).map((r) => r.position), [0, 1]);
    });

    test('B7: a first compute of 0405 [oil] serving 4 awaits; meanwhile a '
        'save serves 8 (no line changes): the totals are stamped under 8, '
        "the stored recipe's basis", () async {
      final db = tempDb();
      final provider = Gated(FixtureProvider(pending: pendingSearches));
      final four = acquacotta([
        oil,
      ]).copyWith(serves: const Serves(min: 4, max: 4));
      saveRecipe(db, four);
      provider.onCall = () async => saveRecipe(
        db,
        four.copyWith(serves: const Serves(min: 8, max: 8)),
      );
      await matchAndCompute(db, provider, four);
      final stamped = db.nutritionFor(four.id)!;
      expect(stamped.servingBasis, 8);
      expect(stamped.ingredientsHash, ingredientsHashOf(four));
    });
  });
}
