// Run 052's write-path fixes (matcher v22): the freshness stamp names its
// layout (F1, O1/S2), apply-to-all's targets and its write (F3, S1, Opus
// critic 3, O14, Sonnet critic 2, S8), the pairing's key (F5, O4/O9/S14),
// one compute step for both job loops (F6, S5/O5), the orphan write (O3), a
// deleted target (O6), the global layout seq (Opus critic 1) and the GET's
// carried row (Opus critic 2). Real corpus lines (0405 Acquacotta, 0132,
// 0751, 0856, 0162), recorded FDC answers (FixtureProvider), never the
// network. Synthesized, a stated exception: the small test recipes holding
// corpus lines, the edits each test names (an amount edit, a line deleted
// or inserted, a duplicated line), and the saves a test makes during an
// await (a gated provider).
// ignore_for_file: lines_longer_than_80_chars
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

void main() {
  group('F1: the stamp names its layout', () {
    test('O1: 0405 computed; a save deletes line 1, a person skips line 0 '
        '(the layout drops the celery row), the original saved back — the '
        'recipe is STALE and in the stale scope, never fresh with a line '
        'that has no row', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final x = loadCorpusRecipe(
        '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
      );
      wp.saveRecipe(db, x);
      await matchAndCompute(db, provider, x);
      expect(nutritionIsFresh(db, x), isTrue);
      final first = x.ingredients.first;
      final y = x.copyWith(
        ingredients: [
          first.copyWith(items: [...first.items]..removeAt(1)),
          ...x.ingredients.skip(1),
        ],
      );
      wp.saveRecipe(db, y);
      await applyMatchOverride(db, provider, y, 0, {
        'raw': nutritionLines(y)[0].raw,
        'skipped': true,
      });
      wp.saveRecipe(db, x);
      expect(db.nutritionFor(x.id)!.ingredientsHash, ingredientsHashOf(x));
      expect(nutritionIsFresh(db, x), isFalse);
      expect(nutritionBody(db, x, forAdmin: true)['status'], 'stale');
      expect(bulkScopeIds(db, BulkScope.stale), [x.id]);
    }, skip: skipIfNoCorpus);

    test('S2: [oil, onion, celery] computed; saved as [onion, celery], a '
        'confirm on onion (the layout drops the oil row); saved back — '
        'stale, in the stale scope', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final v0 = wp.saveLines(db, [wp.oil, wp.onion, wp.celery]);
      await matchAndCompute(db, provider, v0);
      final v1 = wp.saveLines(db, [wp.onion, wp.celery]);
      await applyMatchOverride(db, provider, v1, 0, {'confirmed': true});
      final v2 = wp.saveLines(db, [wp.oil, wp.onion, wp.celery]);
      expect(db.ingredientMatchesFor('r'), hasLength(2));
      expect(nutritionIsFresh(db, v2), isFalse);
      expect(nutritionBody(db, v2, forAdmin: true)['status'], 'stale');
      expect(bulkScopeIds(db, BulkScope.stale), ['r']);
      // The stale sweep's compute restores the row and stamps fresh.
      await computeUntilFresh(db, provider, v2);
      expect(db.ingredientMatchesFor('r'), hasLength(3));
      expect(nutritionIsFresh(db, v2), isTrue);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    });
  });

  test('F1: no stamp is fresh with a line that has no row — a computed '
      '[oil, onion, celery] whose celery row is gone (deleted directly, '
      'synthesized: no layout ran) recomputes stale', () async {
    final db = wp.tempDb();
    final provider = FixtureProvider(pending: pendingSearches);
    final r = wp.saveLines(db, [wp.oil, wp.onion, wp.celery]);
    await matchAndCompute(db, provider, r);
    expect(nutritionIsFresh(db, r), isTrue);
    db.deleteIngredientMatchesFrom('r', 2);
    await recomputeTotals(db, provider, r);
    expect(nutritionIsFresh(db, r), isFalse);
  });

  group('F3: apply-to-all finds its targets where the layout put them', () {
    const quarter = '¼ cup extra-virgin olive oil';
    const threeQuarters = '¾ cup extra-virgin olive oil';
    String rows(SaltDatabase db, String id) => wp.dump(db, id);

    test('S1: twins [½ cup oil, ½ cup oil] computed, line 1 skipped; a save '
        'deletes line 0 and edits the other to ¾ cup; apply-to-all from '
        "'o' reaches the auto twin — the skip the layout carried stands, "
        'the reached row is gone', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r0 = wp.saveLines(db, [wp.oil, wp.oil]);
      await matchAndCompute(db, provider, r0);
      await applyMatchOverride(db, provider, r0, 1, {'skipped': true});
      wp.saveLines(db, [threeQuarters]);
      final o = wp.saveLines(db, [wp.oil], id: 'o');
      await matchAndCompute(db, provider, o);
      final applied = await applyMatchOverride(db, provider, o, 0, {
        'raw': wp.oil,
        'fdc_id': 173468,
        'apply_to_all': true,
      });
      expect(db.ingredientMatchesFor('r').single.status, 'skipped');
      expect(
        (applied!.lines, applied.gone, applied.decided, applied.moved),
        (0, 1, 0, 0),
      );
    });

    test('Opus critic 3: twins [¼, ¼] computed, line 1 skipped; saved as '
        '[¾]; apply-to-all from a ½ cup recipe — the skip stands', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final r0 = wp.saveLines(db, [quarter, quarter]);
      await matchAndCompute(db, provider, r0);
      await applyMatchOverride(db, provider, r0, 1, {
        'raw': quarter,
        'skipped': true,
      });
      wp.saveLines(db, [threeQuarters]);
      final a = wp.saveLines(db, [wp.oil], id: 'a');
      await matchAndCompute(db, provider, a);
      await applyMatchOverride(db, provider, a, 0, {
        'raw': wp.oil,
        'fdc_id': 173468,
        'apply_to_all': true,
      });
      final row = db.ingredientMatchesFor('r').single;
      expect(
        (row.raw, row.status),
        (quarter, 'skipped'),
        reason: rows(db, 'r'),
      );
    });

    test('O14 / Sonnet critic 2: a sibling a save only SHIFTED (b = [¼ cup '
        'oil] computed, saved as [onion, ¼ cup oil], not computed) is '
        'written where the layout put it, and the receipt equals the '
        'offer', () async {
      final db = wp.tempDb();
      final provider = FixtureProvider(pending: pendingSearches);
      final a = wp.saveLines(db, [wp.oil], id: 'a');
      await matchAndCompute(db, provider, a);
      await matchAndCompute(db, provider, wp.saveLines(db, [quarter], id: 'b'));
      wp.saveLines(db, [wp.onion, quarter], id: 'b');
      await applyMatchOverride(db, provider, a, 0, {
        'raw': wp.oil,
        'fdc_id': 173468,
      });
      final offer =
          ((await matchesBody(db, provider, a))['items']! as List).first
              as Map<String, Object?>;
      expect(offer['others_lines'], 1);
      final applied = await applyMatchOverride(db, provider, a, 0, {
        'raw': wp.oil,
        'confirmed': true,
        'apply_to_all': true,
      });
      expect((applied!.recipes, applied.lines), (1, 1));
      final oilRow = db
          .ingredientMatchesFor('b')
          .singleWhere((r) => r.position == 1);
      expect((oilRow.raw, oilRow.fdcId), (quarter, 173468));
    });

    test(
      'S8: a target whose line became another ingredient (b saved with '
      "'1 cup all-purpose flour' over its onion) is gone, never written",
      () async {
        final db = wp.tempDb();
        final provider = FixtureProvider();
        final a = wp.saveLines(db, [wp.onion], id: 'a');
        final b = wp.saveLines(db, [wp.onion], id: 'b');
        await matchAndCompute(db, provider, a);
        await matchAndCompute(db, provider, b);
        wp.saveLines(db, ['1 cup all-purpose flour'], id: 'b');
        final food = (await provider.food(173468))!;
        final res = await applyDecisionToOthers(
          db,
          provider,
          itemKey: lineKeyOf(wp.lineOf(wp.onion)),
          decided: food,
          excluding: (recipeId: 'a', position: 0),
        );
        expect((res.lines, res.gone), (0, 1));
        expect(
          db.ingredientMatchesFor('b').where((r) => r.fdcId == 173468),
          isEmpty,
        );
      },
    );

    test(
      'a target recipe laid out anew between the reach and its turn (c '
      "saved with an onion above its ¼ cup oil and laid out during b's "
      'await): its row is found where the layout put it and written',
      () async {
        final db = wp.tempDb();
        final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
        for (final id in ['b', 'c']) {
          await matchAndCompute(
            db,
            provider,
            wp.saveLines(db, [quarter], id: id),
          );
        }
        final full = (await FixtureProvider().food(173468))!;
        final standIn = FdcFood(
          fdcId: full.fdcId,
          description: full.description,
          dataType: full.dataType,
          nutrientsPer100g: full.nutrientsPer100g,
          portions: const [],
        );
        provider.onCall = () async {
          layoutMatchRows(db, wp.saveLines(db, [wp.onion, quarter], id: 'c'));
        };
        final applied = await applyDecisionToOthers(
          db,
          provider,
          itemKey: lineKeyOf(wp.lineOf(quarter)),
          decided: standIn,
          excluding: (recipeId: 'a', position: 0),
        );
        expect((applied.lines, applied.moved, applied.gone), (2, 0, 0));
        expect(
          db.ingredientMatchesFor('c').single,
          isA<IngredientMatchRow>()
              .having((r) => r.position, 'position', 1)
              .having((r) => r.fdcId, 'fdcId', 173468),
        );
      },
    );

    test("S8's key guard: 0463's '4 (8- to 10-ounce) strip steaks, …' (key "
        "'strip steak') retyped through the editor's parse as 2 steaks "
        "(key 'steak', its text's own key: the layout carries the row, the "
        "same head noun) is not reached by a 'strip steak' decision: the "
        "line's key now names another decision", () async {
      final db = wp.tempDb();
      final corpus = loadCorpusRecipe(
        '0463-steak-au-poivre-with-brandied-cream-sauce.yaml',
      );
      final line = nutritionLines(
        corpus,
      ).firstWhere((l) => l.raw.contains('strip steaks'));
      Recipe holding(String id, IngredientLine l) {
        final r = wp
            .saveLines(db, [l.raw], id: id)
            .copyWith(
              ingredients: [
                IngredientGroup(items: [l]),
              ],
            );
        wp.saveRecipe(db, r);
        return r;
      }

      holding('a', line);
      final b = holding('b', line);
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: 'b',
          position: 0,
          raw: line.raw,
          itemKey: lineKeyOf(line),
          fdcId: 748608,
          description: null,
          dataType: null,
          confidence: 0.5,
          grams: null,
          gramSource: null,
          status: 'auto',
        ),
      );
      layoutMatchRows(db, b);
      final retyped = wp.lineOf(
        '2 (8- to 10-ounce) strip steaks, ¾ to 1 inch thick, trimmed',
      );
      expect((lineKeyOf(line), lineKeyOf(retyped)), ('strip steak', 'steak'));
      holding('b', retyped);
      final res = await applyDecisionToOthers(
        db,
        FixtureProvider(),
        itemKey: 'strip steak',
        decided: (await FixtureProvider().food(173468))!,
        excluding: (recipeId: 'a', position: 0),
      );
      expect((res.lines, res.gone), (0, 1));
      expect(db.ingredientMatchesFor('b').single.fdcId, 748608);
    }, skip: skipIfNoCorpus);

    test("O6: a target recipe deleted during the apply's await is gone, "
        'not moved', () async {
      final db = wp.tempDb();
      final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
      final b0 = wp.acquacotta([wp.oil, wp.onion, wp.celery]).copyWith(id: 'b');
      wp.saveRecipe(db, b0);
      await matchAndCompute(db, provider, b0);
      final full = (await FixtureProvider().food(173468))!;
      final standIn = FdcFood(
        fdcId: full.fdcId,
        description: full.description,
        dataType: full.dataType,
        nutrientsPer100g: full.nutrientsPer100g,
        portions: const [],
      );
      provider.onCall = () async => db.deleteRecipe('b');
      final applied = await applyDecisionToOthers(
        db,
        provider,
        itemKey: lineKeyOf(wp.lineOf(wp.oil)),
        decided: standIn,
        excluding: (recipeId: 'a', position: 0),
      );
      expect((applied.lines, applied.moved, applied.gone), (0, 0, 1));
    }, skip: skipIfNoCorpus);

    test("D1: a person's skip of a target line during the apply's own "
        "portion fetch stands — the call site's write is undecided-only "
        "(a and b both '1 large onion, chopped coarse'; the decided food "
        'is a portion-less hit, so the target fetches its detail)', () async {
      final db = wp.tempDb();
      final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
      final a = wp.saveLines(db, [wp.onion], id: 'a');
      final b = wp.saveLines(db, [wp.onion], id: 'b');
      await matchAndCompute(db, provider, a);
      await matchAndCompute(db, provider, b);
      const hit = FdcFood(
        fdcId: 173468,
        description: 'hit',
        dataType: 'SR Legacy',
        nutrientsPer100g: {},
        portions: [],
      );
      var fired = false;
      provider.onCall = () async {
        fired = true;
        await applyMatchOverride(db, provider, b, 0, {
          'raw': wp.onion,
          'skipped': true,
        });
      };
      final res = await applyDecisionToOthers(
        db,
        provider,
        itemKey: lineKeyOf(wp.lineOf(wp.onion)),
        decided: hit,
        excluding: (recipeId: 'a', position: 0),
      );
      expect(fired, isTrue, reason: 'the hook ran inside the apply');
      expect(db.ingredientMatchesFor('b').single.status, 'skipped');
      expect((res.lines, res.decided), (0, 1));
    });
  });

  test("F3, the class at the DB write: the engine's guarded upsert never "
      'replaces a DECIDED row, whatever its text (a skipped ½ cup row; an '
      'engine row of the ¾ cup text written at its position)', () {
    final db = wp.tempDb();
    final r = wp.saveLines(db, ['¾ cup extra-virgin olive oil']);
    IngredientMatchRow at(String raw, String status) => IngredientMatchRow(
      recipeId: r.id,
      position: 0,
      raw: raw,
      fdcId: 748608,
      description: null,
      dataType: null,
      confidence: 1,
      grams: 54.4,
      gramSource: 'volume',
      status: status,
    );
    db.upsertIngredientMatch(at(wp.oil, 'skipped'));
    expect(
      db.upsertIngredientMatchIfUndecided(
        at('¾ cup extra-virgin olive oil', 'auto'),
      ),
      isFalse,
    );
    expect(wp.row(db).status, 'skipped');
  });

  test('O3: [onion, ½ cup oil] computed, the oil skipped; saved as [celery, '
      "1 cup oil]; during the compute's first await a person un-skips the "
      'oil line — the un-skip stands', () async {
    final db = wp.tempDb();
    final pr = wp.Gated(FixtureProvider(pending: pendingSearches));
    const cup = '1 cup extra-virgin olive oil';
    final v1 = wp.saveLines(db, [wp.onion, wp.oil]);
    await matchAndCompute(db, pr, v1);
    await applyMatchOverride(db, pr, v1, 1, {'skipped': true});
    final v2 = wp.saveLines(db, [wp.celery, cup]);
    pr.onCall = () async {
      await applyMatchOverride(db, pr, v2, 1, {'raw': cup, 'skipped': false});
    };
    await matchAndCompute(db, pr, v2);
    final oil = wp.row(db, 1);
    expect((oil.raw, oil.status == 'skipped'), (cup, false));
  });

  group('F5: the stored key is the key', () {
    test("O4: 0132's chicken-breast line (picked, 777 g typed) retyped as "
        "0162's '1 (5- to 7-pound) whole bone-in, skin-on turkey breast, "
        "trimmed' — the editor keys it 'whole bone-in', as its old text "
        'reads; the pick is dropped, never carried to the turkey', () {
      final db = wp.tempDb();
      final r = loadCorpusRecipe(
        '0132-pan-roasted-chicken-breasts-with-sage-vermouth-sauce.yaml',
      );
      wp.saveRecipe(db, r);
      final lines = nutritionLines(r);
      final c = lines.indexWhere((l) => l.raw.contains('chicken breasts'));
      for (final (p, l) in lines.indexed) {
        db.upsertIngredientMatch(
          IngredientMatchRow(
            recipeId: r.id,
            position: p,
            raw: l.raw,
            fdcId: p == c ? 173468 : null,
            description: null,
            dataType: null,
            confidence: 0,
            grams: p == c ? 777 : null,
            gramSource: p == c ? 'override' : null,
            status: p == c ? 'overridden' : 'auto',
            itemKey: lineKeyOf(l),
          ),
        );
      }
      layoutMatchRows(db, r);
      const turkey =
          '1 (5- to 7-pound) whole bone-in, skin-on turkey breast, trimmed';
      final e = r.copyWith(
        ingredients: [
          for (final g in r.ingredients)
            g.copyWith(
              items: [
                for (final l in g.items)
                  l.raw.contains('chicken breasts') ? wp.lineOf(turkey) : l,
              ],
            ),
        ],
      );
      wp.saveRecipe(db, e);
      expect(lineKeyOf(nutritionLines(e)[c]), 'whole bone-in');
      layoutMatchRows(db, e);
      expect(
        db.ingredientMatchesFor(r.id).where((x) => x.position == c),
        isEmpty,
      );
    }, skip: skipIfNoCorpus);

    test("O9: 0751's skipped '8 large slices high-quality hearty white "
        "sandwich bread or challah' edited through the editor (its curated "
        'item kept) to 10 slices keeps the skip via the stored key', () {
      final r = loadCorpusRecipe('0751-french-toast.yaml');
      final line = nutritionLines(r).firstWhere(
        (l) =>
            l.raw ==
            '8 large slices high-quality hearty white sandwich bread or challah',
      );
      const edited =
          '10 large slices high-quality hearty white sandwich bread or challah';
      final next = IngredientLine(
        raw: edited,
        item: line.item,
        prep: line.prep,
        amounts: line.amounts,
      );
      final skip = IngredientMatchRow(
        recipeId: r.id,
        position: 0,
        raw: line.raw,
        itemKey: lineKeyOf(line),
        fdcId: null,
        description: null,
        dataType: null,
        confidence: 0,
        grams: null,
        gramSource: null,
        status: 'skipped',
      );
      final paired = pairRowsToLines([skip], [next], laidOut: [line.raw]);
      expect(paired.single?.status, 'skipped');
    }, skip: skipIfNoCorpus);
  });

  test('F6 (S5/O5): a save and a Compute request while a BULK sweep computes '
      'the recipe — the request re-attaches to the sweep, and the sweep '
      'computes the stored recipe again: rows for every line, fresh', () async {
    final db = wp.tempDb();
    final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
    final v1 = wp.acquacotta([wp.oil]);
    wp.saveRecipe(db, v1);
    final v2 = wp.acquacotta([wp.oil, wp.onion]);
    int? request;
    provider.onCall = () async {
      wp.saveRecipe(db, v2);
      request = startRecipeComputeJob(db, provider, v2);
    };
    final bulk = startBulkJob(db, provider)!;
    while (bulkJobRunning || recipeComputeJobId(v1.id) != null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(request, bulk);
    expect(db.nutritionJob(bulk)!['status'], 'done');
    expect(
      [for (final r in db.ingredientMatchesFor(v1.id)) r.raw],
      [wp.oil, wp.onion],
    );
    expect(nutritionIsFresh(db, v2), isTrue);
  }, skip: skipIfNoCorpus);

  test('Opus critic 1: the layout seq is global — a recipe deleted and '
      're-created under its id (and laid out once) during a compute never '
      'repeats the seq the compute read: stale, never fresh with a row '
      'missing', () async {
    final db = wp.tempDb();
    final provider = wp.Gated(FixtureProvider(pending: pendingSearches));
    final v = wp.acquacotta([wp.oil, wp.onion]);
    wp.saveRecipe(db, v);
    await applyMatchOverride(db, provider, v, 1, {
      'skipped': true,
      'raw': wp.onion,
    });
    final before = db.layoutOf(v.id).seq;
    provider.onCall = () async {
      db.deleteRecipe(v.id);
      wp.saveRecipe(db, v);
      layoutMatchRows(db, v);
      expect(db.layoutOf(v.id).seq, greaterThan(before));
    };
    await matchAndCompute(db, provider, v);
    final rows = db.ingredientMatchesFor(v.id).length;
    expect(nutritionIsFresh(db, v) && rows < 2, isFalse);
    expect(nutritionIsFresh(db, v), isFalse);
  }, skip: skipIfNoCorpus);

  test('Opus critic 2: the GET shows a decision an amount edit carried — '
      '½ cup oil picked 173468 with 3 g typed, saved as 1 cup, not '
      "computed: the pick with its status, the new line's grams, "
      'carried_from the old text; the offer reads its food', () async {
    final db = wp.tempDb();
    final provider = FixtureProvider(pending: pendingSearches);
    const cup = '1 cup extra-virgin olive oil';
    final a = wp.saveLines(db, [wp.oil]);
    await matchAndCompute(db, provider, a);
    await applyMatchOverride(db, provider, a, 0, {
      'raw': wp.oil,
      'fdc_id': 173468,
      'grams': 3,
    });
    // Another recipe's row already counted on that food: no offer reaches it.
    final b = wp.saveLines(db, ['¼ cup extra-virgin olive oil'], id: 'b');
    db.upsertIngredientMatch(
      IngredientMatchRow(
        recipeId: 'b',
        position: 0,
        raw: b.ingredients.single.items.single.raw,
        itemKey: lineKeyOf(b.ingredients.single.items.single),
        fdcId: 173468,
        description: null,
        dataType: null,
        confidence: 0.95,
        grams: 54,
        gramSource: 'volume',
        status: 'auto',
      ),
    );
    final edited = wp.saveLines(db, [cup]);
    final item =
        ((await matchesBody(db, provider, edited))['items']! as List).single
            as Map<String, Object?>;
    final match = item['match']! as Map<String, Object?>;
    expect(
      (match['status'], match['fdc_id'], match['carried_from']),
      ('overridden', 173468, wp.oil),
    );
    expect(match['grams'], isNot(3.0));
    expect(item['others_lines'], 0);
    // Nothing was written by the GET.
    expect(wp.row(db).raw, wp.oil);
  });
}
