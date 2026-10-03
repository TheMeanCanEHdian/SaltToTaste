// RULE A at the granularity Run 056 measured (matcher v26, brief I1/I2/I6
// and I10's S17/S18/S25): a decided row's derived write is addressed by the
// row's CURRENT position (one placement, I1); a derivation that cannot run
// — FDC failing a fetch it needs, or a food no cache and no FDC answer
// holds — is ONE outcome on every path (I2: the decision stored, the
// derived fields as the last derivation left them, the recipe stale, never
// a throw for one row, no fetch a path does not read); a decided line with
// no amount derives no grams (I6). Real corpus recipes (0129 Indoor Pulled
// Chicken, 0279 Crispy Salt-and-Pepper Shrimp, 0857 Rich Chocolate Bundt
// Cake, 0318 Thick-Cut Sweet Potato Fries, 0148 Crispy Fried Chicken, 0295
// Indoor Clambake, 0711 Mujaddara) and recorded FDC answers
// (FixtureProvider), never the network. Synthesized, each a stated
// exception: the edits (a line deleted, the corpus's own "1 cup water"
// line inserted, a strain step or a dredge taken out, a title edit, an
// amount re-written: "3 teaspoons Sichuan peppercorns", "5 cups (25
// ounces) …flour", "plus 4 tablespoons reserved oil", a subsection
// renamed), a duplicated line (twins), a recipe cut to one line, the typed
// amount-less "All-purpose flour, for dredging" (no corpus coating line is
// amount-less, Run 056 S22), 0318's "Kosher salt" typed "Kosher salt
// (recipe follows)" (no corpus sub-recipe line is a held medium: M26), and
// the outage: a provider that throws (the totals' fetch too), and a
// food whose caches are emptied with FDC answering no such food.
// ignore_for_file: lines_longer_than_80_chars
import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// FDC down: every call throws, as the live provider does with its hourly
/// budget spent or the network out (NutritionProviderException).
class Outage implements NutritionProvider {
  Outage(this.inner);

  final FixtureProvider inner;
  bool down = false;

  /// Every call made while [down] (each one threw).
  int failed = 0;

  @override
  Future<List<FdcCandidate>> search(String query) =>
      down ? _fail() : inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) => down ? _fail() : inner.food(fdcId);

  Never _fail() {
    failed += 1;
    throw const NutritionProviderException('outage');
  }
}

/// A database at a known path (the critic-1 test empties its caches).
(SaltDatabase, String) pathDb() {
  final dir = Directory.systemTemp.createTempSync('salt-v26-rule-a');
  addTearDown(() => dir.deleteSync(recursive: true));
  final path = '${dir.path}/salt.db';
  final db = SaltDatabase.open(path)
    ..upsertSource(slug: 'src', name: 'Test', type: 'book');
  addTearDown(db.dispose);
  return (db, path);
}

/// [r] with its first ingredient line deleted.
Recipe withoutFirstLine(Recipe r) {
  final first = r.ingredients.first;
  return r.copyWith(
    ingredients: [
      first.copyWith(items: first.items.sublist(1)),
      ...r.ingredients.skip(1),
    ],
  );
}

/// [r] with every line [from] re-written as [to].
Recipe rewritten(Recipe r, String from, String to) {
  final parsed = parseIngredientLine(to);
  return r.copyWith(
    ingredients: [
      for (final group in r.ingredients)
        group.copyWith(
          items: [
            for (final line in group.items)
              line.raw == from
                  ? IngredientLine(
                      raw: to,
                      item: parsed.item,
                      amounts: parsed.amounts,
                    )
                  : line,
          ],
        ),
    ],
  );
}

/// The matches GET's `match` of line [position].
Future<Map<String, Object?>> getMatch(
  SaltDatabase db,
  Recipe r,
  int position,
) async {
  final body = await matchesBody(
    db,
    FixtureProvider(pending: pendingSearches),
    r,
  );
  final item = (body['items']! as List)[position] as Map<String, Object?>;
  return item['match']! as Map<String, Object?>;
}

/// A provider that runs [onSearch] once, at its first search: a save
/// during a compute's awaits.
class SaveOnFirstSearch implements NutritionProvider {
  SaveOnFirstSearch(this.inner, this.onSearch);

  final NutritionProvider inner;
  final void Function() onSearch;
  bool saved = false;

  @override
  Future<List<FdcCandidate>> search(String query) {
    if (!saved) {
      saved = true;
      onSearch();
    }
    return inner.search(query);
  }

  @override
  Future<FdcFood?> food(int fdcId) => inner.food(fdcId);
}

const flour1133Cup = '1 cup all-purpose flour, divided';
const flour0148Five = '5 cups (25 ounces) unbleached all-purpose flour';
const plus0711 =
    '1 recipe Crispy Onions, plus 3 tablespoons reserved oil (recipe follows)';

/// 0711 cut to its plus line, picked on 2710180 (42 g, the plus part).
Future<(SaltDatabase, FixtureProvider, Recipe)> picked0711() async {
  // Cut to the line, its subsections kept (the plus part reads them).
  final corpus = loadCorpusRecipe(
    '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
  );
  final r = corpus.copyWith(
    ingredients: [
      IngredientGroup(
        items: [
          for (final group in corpus.ingredients)
            ...group.items.where((line) => line.raw == plus0711),
        ],
      ),
    ],
  );
  final db = wp.tempDb();
  final provider = FixtureProvider(pending: pendingSearches);
  await d.editAndCompute(db, provider, r);
  await applyMatchOverride(db, provider, r, 0, {
    'raw': plus0711,
    'fdc_id': 2710180,
  });
  return (db, provider, r);
}

/// [r] with its Crispy Onions subsection renamed: the plus line is then a
/// sub-recipe the recipe makes apart.
Recipe apart0711(Recipe r) => r.copyWith(
  subsections: [
    for (final sub in r.subsections)
      sub.title == 'Crispy Onions'
          ? sub.copyWith(title: 'Fried Shallots')
          : sub,
  ],
);

const peppercorns0279 = '2 teaspoons Sichuan peppercorns';
const flour0857 = '1¾ cups (8¾ ounces) unbleached all-purpose flour';

void main() {
  group("I1: ONE placement — the derived write at the row's CURRENT "
      'position (Run 056 S1)', () {
    test("S1: 0129's divided liquid smoke confirmed (4.73 g), then ONE save "
        'deletes the first ingredient line AND takes the strain step out: '
        'the compute writes the confirmed row at its new position, 14.2 g '
        '`portion`, fresh (v25: looked up at the old position, nothing '
        'written, 4.73 g stamped fresh)', () async {
      final (db, provider, r) = await d.computed(
        '0129-indoor-pulled-chicken.yaml',
      );
      final i = d.at(r, d.smoke0129);
      await applyMatchOverride(db, provider, r, i, {
        'raw': d.smoke0129,
        'confirmed': true,
      });
      expect(d.rowOf(db, r, i).grams, closeTo(4.73, 0.01));
      final edited = d.unstrained0129(withoutFirstLine(r));
      final j = d.at(edited, d.smoke0129);
      expect(j, i - 1);
      await d.editAndCompute(db, provider, edited);
      final now = d.rowOf(db, edited, j);
      expect(
        (now.status, now.gramSource, now.hold),
        (
          'confirmed',
          GramSource.portion.name,
          null,
        ),
      );
      expect(now.grams, closeTo(14.2, 0.01));
      final fresh = await d.freshWrite(edited, j, {'confirmed': true});
      expect(d.shape(now), d.shape(fresh));
      expect(nutritionIsFresh(db, edited), isTrue);
    });

    test(
      'twins: 0129 with its liquid smoke line doubled (synthesized), both '
      'confirmed, then the same save — each row derives at its OWN new '
      'position (v25: the first was looked up at the old position, where '
      'its twin now sat, and wrote over the twin; the first kept 4.73 g)',
      () async {
        final corpus = loadCorpusRecipe('0129-indoor-pulled-chicken.yaml');
        final r = corpus.copyWith(
          ingredients: [
            for (final group in corpus.ingredients)
              group.copyWith(
                items: [
                  for (final line in group.items) ...[
                    line,
                    if (line.raw == d.smoke0129) line,
                  ],
                ],
              ),
          ],
        );
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        await d.editAndCompute(db, provider, r);
        final i = d.at(r, d.smoke0129);
        for (final p in [i, i + 1]) {
          await applyMatchOverride(db, provider, r, p, {
            'raw': d.smoke0129,
            'confirmed': true,
          });
        }
        final edited = d.unstrained0129(withoutFirstLine(r));
        await d.editAndCompute(db, provider, edited);
        for (final p in [i - 1, i]) {
          final fresh = await d.freshWrite(edited, p, {'confirmed': true});
          expect(
            d.shape(d.rowOf(db, edited, p)),
            d.shape(fresh),
            reason: '#$p',
          );
        }
        expect(d.rowOf(db, edited, i - 1).grams, isNot(closeTo(4.73, 0.01)));
        expect(nutritionIsFresh(db, edited), isTrue);
      },
    );

    test("a decided row moved DOWN: the corpus's own '1 cup water' inserted "
        "before 0129's confirmed smoke, the strain step taken out in the "
        'same save — written at its new position', () async {
      final (db, provider, r) = await d.computed(
        '0129-indoor-pulled-chicken.yaml',
      );
      final i = d.at(r, d.smoke0129);
      await applyMatchOverride(db, provider, r, i, {
        'raw': d.smoke0129,
        'confirmed': true,
      });
      final edited = d.unstrained0129(d.withWaterFirst(r));
      expect(d.at(edited, d.smoke0129), i + 1);
      await d.editAndCompute(db, provider, edited);
      final fresh = await d.freshWrite(edited, i + 1, {'confirmed': true});
      final now = d.rowOf(db, edited, i + 1);
      expect(d.shape(now), d.shape(fresh));
      expect(now.grams, closeTo(14.2, 0.01));
      expect(nutritionIsFresh(db, edited), isTrue);
    });
  }, skip: skipIfNoCorpus);

  group('I2: ONE "derivation unavailable" outcome on every path (Run 056 '
      'S2/O1/S29/O18, Sonnet critic 1)', () {
    test("S2: 0129's held liquid smoke confirmed during an FDC outage — the "
        'decision stored (200), the hold kept, no grams, the recipe STALE; '
        "the GET shows it as stored with the hold's words; a compute in the "
        'outage never throws and writes nothing; FDC back, the compute '
        'derives 4.73 g and stamps fresh', () async {
      final db = wp.tempDb();
      final p = Outage(FixtureProvider(pending: pendingSearches));
      final r = loadCorpusRecipe('0129-indoor-pulled-chicken.yaml');
      await d.editAndCompute(db, p, r);
      final i = d.at(r, d.smoke0129);
      expect(d.rowOf(db, r, i).hold, 'partial_pour_away');
      p.down = true;
      await applyMatchOverride(db, p, r, i, {
        'raw': d.smoke0129,
        'confirmed': true,
      });
      expect(p.failed, greaterThan(0), reason: 'the derivation needed FDC');
      final stored = d.rowOf(db, r, i);
      expect(d.shape(stored), (
        'confirmed',
        167682,
        null,
        null,
        'partial_pour_away',
      ));
      expect(nutritionIsFresh(db, r), isFalse);
      final shown = await getMatch(db, r, i);
      expect(
        (shown['status'], shown['grams'], shown['hold']),
        ('confirmed', null, 'partial_pour_away'),
      );
      final words = holdNoteOf(r, nutritionLines(r)[i], 'partial_pour_away');
      expect(words, isNotNull);
      expect(shown['hold_note'], words);
      await matchAndCompute(db, p, r);
      expect(d.shape(d.rowOf(db, r, i)), d.shape(stored));
      expect(d.rowOf(db, r, i).updatedAt, stored.updatedAt);
      expect(nutritionIsFresh(db, r), isFalse);
      p.down = false;
      await matchAndCompute(db, p, r);
      final back = d.rowOf(db, r, i);
      expect(
        (back.status, back.gramSource, back.hold),
        ('confirmed', GramSource.discarded.name, null),
      );
      expect(back.grams, closeTo(4.73, 0.01));
      expect(nutritionIsFresh(db, r), isTrue);
    });

    test("S29/O18: a PICK of 0129's smoke food during the outage — stored "
        '(200) with no grams and the hold KEPT, stale; FDC back, what a pick '
        'writes', () async {
      final db = wp.tempDb();
      final p = Outage(FixtureProvider(pending: pendingSearches));
      final r = loadCorpusRecipe('0129-indoor-pulled-chicken.yaml');
      await d.editAndCompute(db, p, r);
      final i = d.at(r, d.smoke0129);
      p.down = true;
      await applyMatchOverride(db, p, r, i, {
        'raw': d.smoke0129,
        'fdc_id': 167682,
      });
      expect(d.shape(d.rowOf(db, r, i)), (
        'overridden',
        167682,
        null,
        null,
        'partial_pour_away',
      ));
      expect(nutritionIsFresh(db, r), isFalse);
      p.down = false;
      await matchAndCompute(db, p, r);
      final fresh = await d.freshWrite(r, i, {'fdc_id': 167682});
      expect(d.shape(d.rowOf(db, r, i)), d.shape(fresh));
      expect(nutritionIsFresh(db, r), isTrue);
    });

    test("O1: 0279's below-gate \"2 teaspoons Sichuan peppercorns\" (its "
        'detail never fetched) with grams typed during an outage — 0 food '
        'requests at the PUT and at the compute (typed grams read no food), '
        'the compute never throws', () async {
      final db = wp.tempDb();
      final p = Outage(FixtureProvider(pending: pendingSearches));
      final r = loadCorpusRecipe('0279-crispy-salt-and-pepper-shrimp.yaml');
      await d.editAndCompute(db, p, r);
      final i = d.at(r, peppercorns0279);
      expect(d.rowOf(db, r, i).confidence, lessThan(0.5));
      p.down = true;
      await applyMatchOverride(db, p, r, i, {
        'raw': peppercorns0279,
        'grams': 77,
      });
      await matchAndCompute(db, p, r);
      expect(p.failed, 0);
      final row = d.rowOf(db, r, i);
      expect(
        (row.status, row.grams, row.gramSource, row.hold),
        ('overridden', 77, GramSource.override.name, null),
      );
    });

    // v27 (Run 057 O17): the outage is the real NutritionProviderException
    // ([Outage]) — a fixture miss is an Error now, never an outage.
    test("O1/O18: 0279's peppercorns CONFIRMED during an outage "
        '(the confirm needs the detail): stored as the PUT left it, stale; a compute '
        'never throws and leaves it; its amount edited ("3 teaspoons", '
        'synthesized), the GET shows the carried row AS STORED and the '
        'compute leaves it on its old text, stale', () async {
      final (db, fixture, r) = await d.computed(
        '0279-crispy-salt-and-pepper-shrimp.yaml',
      );
      final provider = Outage(fixture)..down = true;
      final i = d.at(r, peppercorns0279);
      final auto = d.rowOf(db, r, i);
      expect(auto.gramSource, GramSource.density.name);
      await applyMatchOverride(db, provider, r, i, {
        'raw': peppercorns0279,
        'confirmed': true,
      });
      final stored = d.rowOf(db, r, i);
      // The decision, with the grams the last derivation left (never
      // cleared).
      expect(
        (stored.status, stored.fdcId, stored.grams, stored.gramSource),
        ('confirmed', 168093, auto.grams, auto.gramSource),
      );
      expect(nutritionIsFresh(db, r), isFalse);
      await matchAndCompute(db, provider, r);
      expect(d.shape(d.rowOf(db, r, i)), d.shape(stored));
      expect(nutritionIsFresh(db, r), isFalse);
      const three = '3 teaspoons Sichuan peppercorns';
      final edited = rewritten(r, peppercorns0279, three);
      wp.saveRecipe(db, edited);
      final shown = await getMatch(db, edited, i);
      expect(
        (shown['status'], shown['grams'], shown['gram_source']),
        ('confirmed', stored.grams, stored.gramSource),
      );
      expect(shown['carried_from'], peppercorns0279);
      await matchAndCompute(db, provider, edited);
      final now = d.rowOf(db, edited, i);
      expect((now.raw, now.grams), (peppercorns0279, stored.grams));
      expect(nutritionIsFresh(db, edited), isFalse);
      // A person's confirm on the carried line, FDC still failing: stored
      // on the OLD text (the amount still reads as edited, for the next
      // derivation); grams typed now are typed for the line as it reads.
      await applyMatchOverride(db, provider, edited, i, {
        'raw': three,
        'confirmed': true,
      });
      expect(d.rowOf(db, edited, i).raw, peppercorns0279);
      await applyMatchOverride(db, provider, edited, i, {
        'raw': three,
        'grams': 9,
      });
      final typed = d.rowOf(db, edited, i);
      expect(
        (typed.raw, typed.grams, typed.gramSource),
        (three, 9, GramSource.override.name),
      );
      await matchAndCompute(db, provider, edited);
      expect(d.shape(d.rowOf(db, edited, i)), d.shape(typed));
    });

    test(
      "typed grams of the OLD amount are never revived: 0279's "
      'peppercorns typed 77 g, the amount edited ("3 teaspoons", '
      'synthesized), then confirmed during an outage (the detail it '
      'needs, Run 057 O17: the real exception) — the row stays on its old '
      'text, and the next compute still reads the amount as edited',
      () async {
        final (db, fixture, r) = await d.computed(
          '0279-crispy-salt-and-pepper-shrimp.yaml',
        );
        final provider = Outage(fixture);
        final i = d.at(r, peppercorns0279);
        await applyMatchOverride(db, provider, r, i, {
          'raw': peppercorns0279,
          'grams': 77,
        });
        const three = '3 teaspoons Sichuan peppercorns';
        final edited = rewritten(r, peppercorns0279, three);
        wp.saveRecipe(db, edited);
        provider.down = true;
        await applyMatchOverride(db, provider, edited, i, {
          'raw': three,
          'confirmed': true,
        });
        final row = d.rowOf(db, edited, i);
        expect(
          (row.raw, row.status, row.grams),
          (peppercorns0279, 'confirmed', 77),
        );
        expect(nutritionIsFresh(db, edited), isFalse);
      },
    );

    // v27 (RULE A, Opus critic 2): "no such food" with no cache holding it
    // is not an outage — the decision is derived to the `food_gone` hold
    // (out of the totals, in `check`; no grams derived), and the recipe is
    // fresh-and-held (partial), never left stale for a sweep to ask again.
    test(
      "Sonnet critic 1: 0857's confirmed \"1¾ cups (8¾ ounces)\" flour "
      '(248 g by its own weight), its food then in no cache and FDC '
      'answering no such food — the food_gone hold, the recipe held',
      () async {
        final (db, path) = pathDb();
        final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
        await d.editAndCompute(
          db,
          FixtureProvider(pending: pendingSearches),
          r,
        );
        final i = d.at(r, flour0857);
        await applyMatchOverride(
          db,
          FixtureProvider(pending: pendingSearches),
          r,
          i,
          {'raw': flour0857, 'confirmed': true},
        );
        final confirmed = d.rowOf(db, r, i);
        expect(confirmed.grams, closeTo(248.06, 0.01));
        expect(confirmed.gramSource, GramSource.weight.name);
        final id = confirmed.fdcId!;
        sqlite3.open(path)
          ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
          ..execute(
            'DELETE FROM fdc_search_cache '
            "WHERE response LIKE '%\"fdc_id\":' || ? || ',%'",
            [id],
          )
          ..dispose();
        expect(knownFood(db, id), isNull);
        final gone = FixtureProvider(
          pending: pendingSearches,
          superseded: {id},
        );
        await matchAndCompute(db, gone, r);
        final now = d.rowOf(db, r, i);
        expect(knownFood(db, id), isNull, reason: 'still in no cache');
        expect(
          (now.status, now.fdcId, now.grams, now.gramSource, now.hold),
          ('confirmed', id, null, null, 'food_gone'),
        );
        expect(nutritionIsFresh(db, r), isTrue);
        expect(db.nutritionFor(r.id)!.status, 'partial');
        final shown = await getMatch(db, r, i);
        expect(
          (shown['status'], shown['grams'], shown['hold']),
          ('confirmed', null, 'food_gone'),
        );
      },
    );
  }, skip: skipIfNoCorpus);

  group('I6: a decided line with NO amount derives no grams (Run 056 '
      'O13/S22)', () {
    // The decision and what it derives, at the PUT, the GET and a compute.
    Future<void> expectEverywhere(
      SaltDatabase db,
      NutritionProvider provider,
      Recipe r,
      (String, int?, double?, String?, String?) shape,
      String? note,
    ) async {
      for (final path in ['PUT', 'compute']) {
        if (path == 'compute') {
          await matchAndCompute(db, provider, r);
        }
        expect(d.shape(d.rowOf(db, r, 0)), shape, reason: path);
        expect((await getMatch(db, r, 0))['hold_note'], note, reason: path);
      }
    }

    test("0318's real \"Kosher salt\" (cut to its line; a wholly poured-away "
        'medium): a pick is 0 g `discarded`, "poured away after your pick"; '
        'a confirm 0 g `discarded`, "poured away after your confirm" — v25 '
        'stored 0 g `unmeasured` with "eaten part counted"', () async {
      final r = d.oneLine(
        '0318-thick-cut-sweet-potato-fries.yaml',
        'Kosher salt',
      );
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      await d.editAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'raw': 'Kosher salt',
        'fdc_id': 173468,
      });
      await expectEverywhere(db, provider, r, (
        'overridden',
        173468,
        0,
        GramSource.discarded.name,
        null,
      ), 'poured away after your pick');
      await applyMatchOverride(db, provider, r, 0, {
        'raw': 'Kosher salt',
        'confirmed': true,
      });
      await expectEverywhere(db, provider, r, (
        'confirmed',
        173468,
        0,
        GramSource.discarded.name,
        null,
      ), 'poured away after your confirm');
    });

    test('M26 (A35): a person\'s pick on 0318\'s held "Kosher salt" (a '
        'wholly poured-away medium), the line then typed "Kosher salt (recipe '
        'follows)" (synthesized: no corpus sub-recipe line is a held medium) '
        '— the decision is carried to a SUB-RECIPE reference, gated to the 0 '
        'g sub-recipe row, and its `hold_note` says nothing: the GET shows '
        'what the compute writes, not "poured away after your pick"', () async {
      const raw = 'Kosher salt (recipe follows)';
      final r = d.oneLine(
        '0318-thick-cut-sweet-potato-fries.yaml',
        'Kosher salt',
      );
      final edited = rewritten(r, 'Kosher salt', raw);
      expect(isSubRecipeReference(raw), isTrue);
      final line = nutritionLines(edited).single;
      expect(
        discardedMediumOf(edited, line, normalizeItem(lineItemOf(line))),
        isNotNull,
      );
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      await d.editAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'raw': 'Kosher salt',
        'fdc_id': 173468,
      });
      expect(await d.noteOf(db, r, 0), 'poured away after your pick');
      wp.saveRecipe(db, edited);
      final shown = await getMatch(db, edited, 0);
      expect(shown['carried_from'], 'Kosher salt');
      expect(shown['hold_note'], isNull);
      await matchAndCompute(db, provider, edited);
      expect(d.rowOf(db, edited, 0).description, subRecipeNote);
      expect(await d.noteOf(db, edited, 0), isNull);
    });

    test('S22: 0148 with its flour typed amount-less "All-purpose flour, for '
        'dredging" (synthesized: no corpus coating line is amount-less) — a '
        'pick keeps the coating hold with no grams; a confirm is 0 g '
        '`discarded`, "poured away after your confirm"', () async {
      const raw = 'All-purpose flour, for dredging';
      final r = rewritten(
        d.oneLine('0148-crispy-fried-chicken.yaml', d.flour0148),
        d.flour0148,
        raw,
      );
      for (final (body, shape, note) in [
        (
          {'fdc_id': 789890},
          ('overridden', 789890, null, null, 'coating'),
          holdNoteOf(r, nutritionLines(r).single, 'coating'),
        ),
        (
          {'confirmed': true},
          ('confirmed', 789890, 0.0, GramSource.discarded.name, null),
          'poured away after your confirm',
        ),
      ]) {
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        await d.editAndCompute(db, provider, r);
        await applyMatchOverride(db, provider, r, 0, {'raw': raw, ...body});
        await expectEverywhere(db, provider, r, shape, note);
      }
    });

    test("0857's unheld \"Confectioners' sugar, for dusting\": a pick stays "
        "with no grams (`no_grams`), a confirm keeps the engine's 0 g "
        '`unmeasured` — left where it is', () async {
      const raw = 'Confectioners’ sugar, for dusting';
      final r = d.oneLine('0857-rich-chocolate-bundt-cake.yaml', raw);
      for (final (body, shape) in [
        (
          {'fdc_id': 169656},
          ('overridden', 169656, null, null, null),
        ),
        (
          {'confirmed': true},
          ('confirmed', null, 0.0, GramSource.unmeasured.name, null),
        ),
      ]) {
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        await d.editAndCompute(db, provider, r);
        final auto = d.rowOf(db, r, 0);
        await applyMatchOverride(db, provider, r, 0, {'raw': raw, ...body});
        await expectEverywhere(db, provider, r, (
          shape.$1,
          shape.$2 ?? auto.fdcId,
          shape.$3,
          shape.$4,
          shape.$5,
        ), null);
      }
    });
  }, skip: skipIfNoCorpus);

  group("I10: RULE A's note arms and guard terms (Run 056 S17/S18/S25, "
      'O18)', () {
    test(
      "S17(a): grams typed on 1133's DIVIDED flour, its amount then "
      'edited (¾ to 1 cup, synthesized; not computed) — the GET shows the '
      'typed grams and NO resolve note (`!keepTyped` in `resolves`)',
      () async {
        final (db, provider, r) = await d.computed(
          '1133-chicken-francese.yaml',
        );
        final i = d.at(r, d.flour1133);
        await applyMatchOverride(db, provider, r, i, {
          'raw': d.flour1133,
          'grams': 60,
        });
        final edited = rewritten(r, d.flour1133, flour1133Cup);
        wp.saveRecipe(db, edited);
        final shown = await getMatch(db, edited, i);
        expect(
          (shown['grams'], shown['gram_source'], shown['hold']),
          (60, GramSource.override.name, null),
        );
        expect(shown['carried_from'], d.flour1133);
        expect(shown['hold_note'], isNull);
      },
    );

    test("S17(b): 0148's flour skipped, its amount then edited (5 cups, "
        'synthesized; not computed) — the GET shows the skip with NO note '
        '(`|| skipped`)', () async {
      final (db, provider, r) = await d.computed(
        '0148-crispy-fried-chicken.yaml',
      );
      final i = d.at(r, d.flour0148);
      await applyMatchOverride(db, provider, r, i, {
        'raw': d.flour0148,
        'skipped': true,
      });
      final edited = rewritten(r, d.flour0148, flour0148Five);
      wp.saveRecipe(db, edited);
      final shown = await getMatch(db, edited, i);
      expect(shown['status'], 'skipped');
      expect(shown['hold_note'], isNull);
    });

    test(
      "S17(c): 0295's in-the-shell mussels (a LINE hold, no medium) "
      'confirmed — NO "eaten part counted" note (`held` is a medium hold)',
      () async {
        const mussels = '2 pounds mussels, scrubbed and debearded';
        final r = d.oneLine('0295-indoor-clambake.yaml', mussels);
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        await d.editAndCompute(db, provider, r);
        await applyMatchOverride(db, provider, r, 0, {
          'raw': mussels,
          'confirmed': true,
        });
        final shown = await getMatch(db, r, 0);
        expect(shown['status'], 'confirmed');
        expect(shown['grams'], isNotNull);
        expect(shown['hold_note'], isNull);
      },
    );

    test(
      "S18: grams typed on 0148's flour, then a re-pick — the pick clears "
      'the typed grams and the dredge holds it again, through a compute',
      () async {
        final (db, provider, r) = await d.computed(
          '0148-crispy-fried-chicken.yaml',
        );
        final i = d.at(r, d.flour0148);
        await applyMatchOverride(db, provider, r, i, {
          'raw': d.flour0148,
          'grams': 60,
        });
        await applyMatchOverride(db, provider, r, i, {
          'raw': d.flour0148,
          'fdc_id': 789890,
        });
        const held = ('overridden', 789890, null, null, 'coating');
        expect(d.shape(d.rowOf(db, r, i)), held);
        await matchAndCompute(db, provider, r);
        expect(d.shape(d.rowOf(db, r, i)), held);
      },
    );

    test("S25: 0711's picked plus-line oil, its subsection renamed (a "
        "sub-recipe made apart; not computed) — the GET shows the pick's "
        "status, food and description with the sub-recipe's 0 g "
        '(withDerived, not the gated row) and no note; the compute writes '
        'the same', () async {
      final (db, provider, r) = await picked0711();
      final pick = d.rowOf(db, r, 0);
      expect(pick.grams, 42);
      final apart = apart0711(r);
      wp.saveRecipe(db, apart);
      Future<void> expectPick() async {
        final shown = await getMatch(db, apart, 0);
        expect(
          (
            shown['status'],
            shown['fdc_id'],
            shown['description'],
            shown['confidence'],
            shown['grams'],
            shown['gram_source'],
            shown['hold_note'],
          ),
          (
            'overridden',
            2710180,
            pick.description,
            pick.confidence,
            0,
            GramSource.unmeasured.name,
            null,
          ),
        );
      }

      await expectPick();
      await matchAndCompute(db, provider, apart);
      final now = d.rowOf(db, apart, 0);
      expect(
        (now.status, now.fdcId, now.description, now.confidence, now.grams),
        ('overridden', 2710180, pick.description, pick.confidence, 0),
      );
      await expectPick();
    });

    test(
      'S25/O18: the same pick CARRIED by an amount edit ("plus 4 '
      'tablespoons", synthesized) into a sub-recipe made apart — the GET '
      'shows what the compute then writes (the gated row, carried)',
      () async {
        final (db, provider, r) = await picked0711();
        final carried = apart0711(
          rewritten(r, plus0711, plus0711.replaceFirst('plus 3', 'plus 4')),
        );
        wp.saveRecipe(db, carried);
        final shown = await getMatch(db, carried, 0);
        expect(shown['carried_from'], plus0711);
        await matchAndCompute(db, provider, carried);
        final now = d.rowOf(db, carried, 0);
        expect(
          (
            shown['status'],
            shown['fdc_id'],
            shown['grams'],
            shown['gram_source'],
          ),
          (now.status, now.fdcId, now.grams, now.gramSource),
        );
        expect((now.status, now.fdcId), isNot(('overridden', 2710180)));
      },
    );

    test("S25/O18: the orphan write's fresh() gate — 0148's flour picked, "
        'its amount edited (5 cups, synthesized), and a title edit saved '
        "during the compute's awaits: the carried row is NOT written (it "
        'keeps its old text), the recipe stale', () async {
      final db = wp.tempDb();
      final fixtures = FixtureProvider(pending: pendingSearches);
      final r = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
      wp.saveRecipe(db, r);
      final i = d.at(r, d.flour0148);
      await applyMatchOverride(db, fixtures, r, i, {
        'raw': d.flour0148,
        'fdc_id': 789890,
      });
      final edited = rewritten(r, d.flour0148, flour0148Five);
      wp.saveRecipe(db, edited);
      final saving = SaveOnFirstSearch(fixtures, () {
        wp.saveRecipe(db, d.retitled(edited));
      });
      await matchAndCompute(db, saving, edited);
      expect(saving.saved, isTrue, reason: 'the compute searched');
      expect(d.rowOf(db, edited, i).raw, d.flour0148);
      expect(nutritionIsFresh(db, edited), isFalse);
    });
  }, skip: skipIfNoCorpus);

  // v27 (RULE A): the totals are CACHE-ONLY — they never fetch; v28 (Run
  // 058 S2): a PUT's plain recompute that meets a food no cache holds
  // resolves it first (one request), so with FDC up nothing is dropped;
  // with FDC down the decided row is left out and UNDERIVED (its
  // `derived_seq` cleared): the recipe reads stale, and the next compute
  // derives it (one request while FDC is down).
  group('I2: the TOTALS read of a food no cache holds — the row underived '
      '(v27: cache-only totals)', () {
    test("0857's confirmed flour (248 g) on a food in NO cache, FDC DOWN: the "
        'compute and a PUT on another line never throw — the row stays as '
        'derived, its food left out of the totals, the recipe stale — and '
        'with FDC back the next compute counts it, fresh', () async {
      final (db, path) = pathDb();
      final r = loadCorpusRecipe('0857-rich-chocolate-bundt-cake.yaml');
      await d.editAndCompute(db, FixtureProvider(pending: pendingSearches), r);
      final i = d.at(r, flour0857);
      await applyMatchOverride(
        db,
        FixtureProvider(pending: pendingSearches),
        r,
        i,
        {'raw': flour0857, 'confirmed': true},
      );
      final confirmed = d.rowOf(db, r, i);
      expect(confirmed.grams, closeTo(248.06, 0.01));
      final id = confirmed.fdcId!;
      final full = db.nutritionFor(r.id)!.totalGrams;
      sqlite3.open(path)
        ..execute('DELETE FROM fdc_food_cache WHERE fdc_id = ?', [id])
        ..execute(
          'DELETE FROM fdc_search_cache '
          "WHERE response LIKE '%\"fdc_id\":' || ? || ',%'",
          [id],
        )
        ..dispose();
      expect(knownFood(db, id), isNull);
      expect(nutritionIsFresh(db, r), isTrue);
      final outage = Outage(FixtureProvider(pending: pendingSearches))
        ..down = true;
      // A PUT first (a plain recompute that would keep the fresh stamp):
      // typed grams on the salt read no food; the flour's food is not the
      // PUT's own line's (v29, Run 059 S13: a PUT resolves its own line
      // only — no request) — the decision stored, the flour left out, the
      // recipe stale.
      const salt = '1 teaspoon table salt';
      final saltBefore = d.rowOf(db, r, d.at(r, salt)).grams!;
      await applyMatchOverride(db, outage, r, d.at(r, salt), {
        'raw': salt,
        'grams': 6,
      });
      expect(
        outage.failed,
        0,
        reason: 'the PUT resolves its own line only (v29)',
      );
      expect(d.rowOf(db, r, i).derivedSeq, isNull, reason: 'underived');
      expect(d.rowOf(db, r, d.at(r, salt)).grams, 6);
      expect(nutritionIsFresh(db, r), isFalse);
      expect(db.nutritionFor(r.id)!.status, 'partial');
      // The compute during the outage: no throw — the failure returned for
      // the job loops — ONE request for the underived row, the row as
      // derived.
      final failure = await matchAndCompute(db, outage, r);
      expect(failure, isA<NutritionProviderException>());
      expect(outage.failed, 1);
      expect(d.shape(d.rowOf(db, r, i)), d.shape(confirmed));
      expect(nutritionIsFresh(db, r), isFalse);
      expect(db.nutritionFor(r.id)!.status, 'partial');
      expect(
        db.nutritionFor(r.id)!.totalGrams,
        closeTo(full! - 248.06 + 6 - saltBefore, 0.2),
      );
      outage.down = false;
      await matchAndCompute(db, outage, r);
      expect(nutritionIsFresh(db, r), isTrue);
      expect(db.nutritionFor(r.id)!.status, 'complete');
    });
  }, skip: skipIfNoCorpus);
}
