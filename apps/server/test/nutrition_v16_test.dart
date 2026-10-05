// Real corpus lines and steps wrap across adjacent literals.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';
import 'support/pinned_corpus_text.dart';

/// Matcher v16 (the Run 048 union): the pairing laid out before any write
/// (identity by alignment, one transaction, no demotion), held media that
/// keep a person's resolution through an edit, a confirm and an un-skip,
/// the weighed line on the pick and on apply_to_all, and the restored
/// grams guards. Real corpus lines and steps as strings (recipe named on
/// each; [pinnedCorpusText] proves each exists), FDC answers recorded from
/// sweep snapshot 12. A guard no corpus line exercises is pinned on a
/// synthesized input, said so where it is.
void main() {
  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v16');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    return db;
  }

  Recipe recipeOf(
    List<List<String>> groups, {
    List<String> steps = const [],
    String title = 'r',
    String id = 'r',
    List<Subsection> subsections = const [],
    SaltDatabase? db,
  }) {
    final recipe = Recipe(
      id: id,
      title: title,
      slug: id,
      source: const RecipeSource(name: 'Test', type: 'book'),
      ingredients: [
        for (final raws in groups)
          IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
      ],
      steps: [
        for (final (i, text) in steps.indexed)
          RecipeStep(number: i + 1, text: text),
      ],
      subsections: subsections,
    );
    db?.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'h$id');
    return recipe;
  }

  Subsection subsectionOf(String title, List<String> raws) => Subsection(
    title: title,
    kind: 'variation',
    ingredients: [
      IngredientGroup(items: [for (final raw in raws) lineOf(raw)]),
    ],
  );

  MatchBucket bucketOf(IngredientMatchRow row) => matchBucketFor(
    status: row.status,
    fdcId: row.fdcId,
    grams: row.grams,
    confidence: row.confidence,
    hold: row.hold,
    gramSource: row.gramSource,
  );

  IngredientMatchRow rowAt(SaltDatabase db, int position, {String id = 'r'}) =>
      db.ingredientMatchesFor(id).singleWhere((r) => r.position == position);

  /// A whole corpus recipe imported as the importer stores it.
  (SaltDatabase, Recipe) imported(String file) {
    final dir = Directory.systemTemp.createTempSync('salt-v16-corpus');
    addTearDown(() => dir.deleteSync(recursive: true));
    final config = ServerConfig(
      dataDir: dir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    final db = SaltDatabase.open(config.dbPath);
    addTearDown(db.dispose);
    final root = Directory('${dir.path}/source')..createSync(recursive: true);
    Directory('${root.path}/recipes').createSync();
    File('$corpusRecipesDir/$file').copySync('${root.path}/recipes/$file');
    importSourceRoot(sourceRootPath: root.path, db: db, config: config);
    return (db, db.recipeByIdOrSlug(db.allRecipeIds().single)!.recipe);
  }

  /// [r] with the first line reading [raw] replaced by [to], or deleted
  /// when [to] is null — an edit a person makes (synthesized: a stated
  /// exception, the recipe itself real).
  Recipe editFirst(Recipe r, String raw, String? to) {
    var done = false;
    return r.copyWith(
      ingredients: [
        for (final group in r.ingredients)
          group.copyWith(
            items: [
              for (final line in group.items)
                if (!done && line.raw == raw)
                  if (to case final text?)
                    (() {
                      done = true;
                      return lineOf(text);
                    })()
                  else
                    ...(() {
                      done = true;
                      return const <IngredientLine>[];
                    })()
                else
                  line,
            ],
          ),
      ],
    );
  }

  String layout(SaltDatabase db, {String id = 'r'}) => [
    for (final row in db.ingredientMatchesFor(id))
      '${row.position} ${row.status} ${row.fdcId} ${row.grams}',
  ].join('\n');

  group('T: the pairing — identity by alignment, laid out in one transaction '
      'before any await, no demotion', () {
    const acquacotta =
        '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml';
    const sp = 'Salt and pepper';

    for (final (verb, to) in [('edited', 'Salt'), ('deleted', null)]) {
      test("T0: Acquacotta (0405) — the first 'Salt and pepper' (5) $verb "
          '(the edit synthesized: a stated exception): the pick on the '
          'second copy stays on it', () async {
        final (db, r) = imported(acquacotta);
        final provider = FixtureProvider(pending: pendingSearches);
        await matchAndCompute(db, provider, r);
        await applyMatchOverride(db, provider, r, 18, {
          'fdc_id': 173468,
          'grams': 5,
        });
        final edited = editFirst(r, sp, to);
        final at = to == null ? 17 : 18;
        expect(nutritionLines(edited)[at].raw, sp);
        await matchAndCompute(db, provider, edited);
        final row = rowAt(db, at, id: r.id);
        expect(
          (row.raw, row.status, row.fdcId, row.grams),
          (sp, 'overridden', 173468, 5),
        );
        expect(
          db.ingredientMatchesFor(r.id).where((x) => x.fdcId == 173468),
          hasLength(1),
        );
      }, skip: skipIfNoCorpus);
    }

    // 0405's line twice, a stated trim; its olive oil the line put above.
    const oil = '½ cup extra-virgin olive oil';

    test('T1: two decided twins (3 g, 7 g) and a line inserted above: both '
        'decisions move down one, in order', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(db: db, [
        [sp, sp],
      ]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'fdc_id': 173468,
        'grams': 3,
      });
      await applyMatchOverride(db, provider, r, 1, {
        'fdc_id': 173468,
        'grams': 7,
      });
      await matchAndCompute(
        db,
        provider,
        recipeOf(db: db, [
          [oil, sp, sp],
        ]),
      );
      expect((rowAt(db, 1).grams, rowAt(db, 2).grams), (3, 7));
      expect(
        (rowAt(db, 1).status, rowAt(db, 2).status),
        (
          'overridden',
          'overridden',
        ),
      );
    });

    test('T1: two decided twins (3 g, 7 g) and the line above them deleted: '
        'both move up one, in order', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(db: db, [
        [oil, sp, sp],
      ]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 1, {
        'fdc_id': 173468,
        'grams': 3,
      });
      await applyMatchOverride(db, provider, r, 2, {
        'fdc_id': 173468,
        'grams': 7,
      });
      await matchAndCompute(
        db,
        provider,
        recipeOf(db: db, [
          [sp, sp],
        ]),
      );
      expect(layout(db), '0 overridden 173468 3.0\n1 overridden 173468 7.0');
    });

    test(
      'T1: three copies — the rule row, a pick, a skip — and a line '
      'inserted above: each moves down one, the rule row re-derived',
      () async {
        final db = tempDb();
        final provider = FixtureProvider();
        final r = recipeOf(db: db, [
          [sp, sp, sp],
        ]);
        await matchAndCompute(db, provider, r);
        await applyMatchOverride(db, provider, r, 1, {
          'fdc_id': 173468,
          'grams': 3,
        });
        await applyMatchOverride(db, provider, r, 2, {'skipped': true});
        await matchAndCompute(
          db,
          provider,
          recipeOf(db: db, [
            [oil, sp, sp, sp],
          ]),
        );
        expect(
          [for (final x in db.ingredientMatchesFor('r').skip(1)) x.status],
          ['confirmed', 'overridden', 'skipped'],
        );
        expect(rowAt(db, 1).fdcId, isNull);
        expect((rowAt(db, 2).fdcId, rowAt(db, 2).grams), (173468, 3));
      },
    );

    test("T2: FDC failing at the re-derive (the inserted line's search "
        'throws) leaves both decided twins intact at their new positions — '
        'the layout is one transaction before any await', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(db: db, [
        [sp, sp],
      ]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'fdc_id': 173468,
        'grams': 3,
      });
      await applyMatchOverride(db, provider, r, 1, {'skipped': true});
      provider.failWith = 'API key rejected';
      await expectLater(
        matchAndCompute(
          db,
          provider,
          recipeOf(db: db, [
            [oil, sp, sp],
          ]),
        ),
        throwsA(isA<NutritionProviderException>()),
      );
      expect(
        [for (final x in db.ingredientMatchesFor('r')) (x.position, x.status)],
        [(1, 'overridden'), (2, 'skipped')],
      );
      expect(rowAt(db, 1).grams, 3);
    });

    test("T2: a person's skip written during the compute's first await (a "
        'synthesized interleaving, a stated exception) survives: no '
        'demotion write, every engine write after an await guarded', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(db: db, [
        [sp, sp],
      ]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 1, {
        'fdc_id': 173468,
        'grams': 3,
      });
      final running = matchAndCompute(
        db,
        provider,
        recipeOf(db: db, [
          [oil, sp, sp],
        ]),
      );
      // The layout ran synchronously: the pick is already at 2.
      expect(rowAt(db, 2).fdcId, 173468);
      db.upsertIngredientMatch(
        IngredientMatchRow(
          recipeId: 'r',
          position: 1,
          raw: sp,
          itemKey: rowAt(db, 2).itemKey,
          fdcId: null,
          description: null,
          dataType: null,
          confidence: 1,
          grams: null,
          gramSource: null,
          status: 'skipped',
        ),
      );
      await running;
      expect(
        layout(db).split('\n').skip(1).join('\n'),
        '1 skipped null null\n2 overridden 173468 3.0',
      );
    });

    for (final (verb, first) in [
      ('a pick', {'fdc_id': 173468, 'grams': 3}),
      ('the rule row', null),
    ]) {
      test("T: the alignment leaves the last copy's skip on no line (two "
          '"Salt" lines put above, the oil moved below the first copy, the '
          'last copy deleted: synthesized, a stated exception) — the layout '
          'deletes it, so the aligned first copy ($verb) is never refused '
          'at its new position', () async {
        final db = tempDb();
        final provider = FixtureProvider();
        final r = recipeOf(db: db, [
          [sp, oil, sp],
        ]);
        await matchAndCompute(db, provider, r);
        if (first != null) {
          await applyMatchOverride(db, provider, r, 0, first);
        }
        await applyMatchOverride(db, provider, r, 2, {'skipped': true});
        await matchAndCompute(
          db,
          provider,
          recipeOf(db: db, [
            ['Salt', 'Salt', sp, oil],
          ]),
        );
        final row = rowAt(db, 2);
        expect(
          (row.status, row.fdcId),
          first == null ? ('confirmed', null) : ('overridden', 173468),
        );
        expect(
          db.ingredientMatchesFor('r').map((x) => x.status),
          isNot(contains('skipped')),
        );
      });
    }

    test('T: a leftover line takes the leftover row of its text at its own '
        'position before nth order — a reorder the alignment cannot keep '
        '("Salt" moved to the top, the oil and one copy deleted: '
        'synthesized, a stated exception) leaves the 7 g copy, which never '
        'moved, its own', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(db: db, [
        [sp, oil, sp, 'Salt'],
      ]);
      await matchAndCompute(db, provider, r);
      await applyMatchOverride(db, provider, r, 0, {
        'fdc_id': 173468,
        'grams': 3,
      });
      await applyMatchOverride(db, provider, r, 2, {
        'fdc_id': 173468,
        'grams': 7,
      });
      await matchAndCompute(
        db,
        provider,
        recipeOf(db: db, [
          ['Salt', 'Pepper', sp],
        ]),
      );
      expect((rowAt(db, 2).status, rowAt(db, 2).grams), ('overridden', 7));
    });
  });

  group("H: a held medium keeps a person's resolution through an amount "
      'edit, a confirm and an un-skip', () {
    // Sesame-Lemon Cucumber Salad (0052): its salt line and first step.
    const cucumberSalt = '1 tablespoon table salt';
    const cucumberStep =
        'Toss the cucumbers with the salt in a colander set over a large '
        'bowl. Weight the cucumbers with a gallon-sized zipper-lock bag '
        'filled with water; drain for 1 to 3 hours. Rinse and pat dry.';
    // The amount edit: synthesized, a stated exception.
    const edited = '2 tablespoons table salt';

    Future<(SaltDatabase, FixtureProvider, Recipe)> cucumber() async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(
        db: db,
        [
          [cucumberSalt],
        ],
        steps: [cucumberStep],
      );
      await matchAndCompute(db, provider, r);
      expect(rowAt(db, 0).hold, 'discarded_medium');
      return (db, provider, r);
    }

    Recipe editedOf(SaltDatabase db) => recipeOf(
      db: db,
      [
        [edited],
      ],
      steps: [cucumberStep],
    );

    for (final (verb, body, want) in [
      ('a bare confirm', {'confirmed': true}, (0, 'discarded')),
      ('a pick', {'fdc_id': 173468}, (0, 'discarded')),
      ('typed grams', {'confirmed': true, 'grams': 2}, (2, 'override')),
    ]) {
      test(
        'H1: 0052 — $verb, then the amount edited: the row keeps its '
        'grams ${want.$1} (${want.$2}), its hold resolved (RULE A), '
        'counted; the sheet fills no portion from the poured-away amount',
        () async {
          final (db, provider, r) = await cucumber();
          await applyMatchOverride(db, provider, r, 0, body);
          final e = editedOf(db);
          await matchAndCompute(db, provider, e);
          final row = rowAt(db, 0);
          // RULE A (v25, Run 055 I1): the decision resolves the hold — a
          // confirm or a pick on a wholly poured-away line is 0 g with no
          // hold, typed grams answer it — at the PUT and every compute.
          expect(
            (row.grams, row.gramSource, row.hold),
            (want.$1, want.$2, null),
          );
          expect(bucketOf(row), MatchBucket.counted);
          final item =
              ((await matchesBody(db, provider, e))['items']! as List).single
                  as Map;
          final portions = item['portions'] as List;
          expect(portions, isNotEmpty);
          expect([
            for (final x in portions) (x as Map)['fill'],
          ], everyElement(isNull));
        },
      );
    }

    test('H1: the sheet fills no portion on a held line the engine holds, '
        'before any decision (0052)', () async {
      final (db, provider, r) = await cucumber();
      final item =
          ((await matchesBody(db, provider, r))['items']! as List).single
              as Map;
      expect(
        [for (final x in item['portions'] as List) (x as Map)['fill']],
        everyElement(isNull),
      );
    });

    test(
      'H2: typed eaten grams (2 g) survive a bare re-confirm (0052)',
      () async {
        final (db, provider, r) = await cucumber();
        await applyMatchOverride(db, provider, r, 0, {
          'confirmed': true,
          'grams': 2,
        });
        await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
        expect((rowAt(db, 0).grams, rowAt(db, 0).gramSource), (2, 'override'));
      },
    );

    test(
      'H0: typed eaten grams (2 g) survive a skip and an un-skip (0052) — '
      "as the person's counted row since matcher v18 (Run 049: an `auto` "
      'row, held, that the next compute re-derived; '
      'nutrition_v18_test H2 pins the recompute)',
      () async {
        final (db, provider, r) = await cucumber();
        await applyMatchOverride(db, provider, r, 0, {
          'confirmed': true,
          'grams': 2,
        });
        await applyMatchOverride(db, provider, r, 0, {'skipped': true});
        await applyMatchOverride(db, provider, r, 0, {'skipped': false});
        final row = rowAt(db, 0);
        expect(
          (row.status, row.grams, row.gramSource, row.hold),
          ('overridden', 2, 'override', null),
        );
      },
    );
  });

  group('P11, H0: the sub-recipe gate on a confirm and a pick — before the '
      'food, and never over grams a person typed', () {
    // Rainbow Cake (1201): the frosting the recipe makes apart.
    const frosting = '10 cups Vanilla Frosting (recipe follows)';

    Future<(SaltDatabase, FixtureProvider, Recipe)> cake() async {
      final db = tempDb();
      final provider = FixtureProvider();
      // v41: with 1201's own section — the section rule row.
      final r = recipeOf(
        db: db,
        [
          [frosting],
        ],
        subsections: const [Subsection(title: 'Vanilla Frosting')],
      );
      await matchAndCompute(db, provider, r);
      expect(rowAt(db, 0).description, subRecipeNote);
      return (db, provider, r);
    }

    test('P11: a pick of "Butter, without salt" (173430) with no grams is '
        'refused (v41 S14: it would derive to the 0 g sub-recipe, a silent '
        'no-op), the line left the 0 g sub-recipe, never 2,082 g of butter '
        '(1201)', () async {
      final (db, provider, r) = await cake();
      await expectLater(
        applyMatchOverride(db, provider, r, 0, {'fdc_id': 173430}),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            notRoutedMessage,
          ),
        ),
      );
      final row = rowAt(db, 0);
      expect((row.fdcId, row.grams, row.description), (null, 0, subRecipeNote));
    });

    test('P11: a bare confirm of an auto row an older engine left on the '
        'butter with 2,270 g (synthesized: a stated exception) is the 0 g '
        'sub-recipe (1201)', () async {
      final (db, provider, r) = await cake();
      db.upsertIngredientMatch(
        rowAt(db, 0).copyWith(
          fdcId: 173430,
          description: 'Butter, without salt',
          dataType: 'SR Legacy',
          confidence: 0.9,
          grams: 2270,
          gramSource: 'density',
          status: 'auto',
        ),
      );
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      final row = rowAt(db, 0);
      expect((row.fdcId, row.grams, row.description), (null, 0, subRecipeNote));
    });

    test('H0: grams a person typed with a pick (500 g; synthesized: a stated '
        'exception) survive a later bare confirm (1201)', () async {
      final (db, provider, r) = await cake();
      await applyMatchOverride(db, provider, r, 0, {
        'fdc_id': 173430,
        'grams': 500,
      });
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      final row = rowAt(db, 0);
      expect(
        (row.status, row.fdcId, row.grams, row.gramSource),
        (
          'confirmed',
          173430,
          500,
          'override',
        ),
      );
    });
  });

  group('W: every write path weighs the weighed line', () {
    test('W1: a pick on a plus line whose eaten part is a medium the compute '
        "zeroes stays zeroed — Mujaddara's (0711) plus line with its reserve "
        'at 2 cups (synthesized: a stated exception; the subsection real) is '
        'frying oil by its mass, 0 g poured away on the pick too', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(
        db: db,
        [
          [
            '1 recipe Crispy Onions, plus 2 cups reserved oil (recipe '
                'follows)',
          ],
        ],
        subsections: [
          subsectionOf('Crispy Onions', [
            '2 pounds onions, halved and sliced crosswise into '
                '¼-inch-thick pieces',
            '2 teaspoons salt',
            '1½ cups vegetable oil',
          ]),
        ],
      );
      await matchAndCompute(db, provider, r);
      final computed = rowAt(db, 0);
      expect((computed.grams, computed.gramSource), (0, 'discarded'));
      await applyMatchOverride(db, provider, r, 0, {
        'fdc_id': computed.fdcId,
      });
      final row = rowAt(db, 0);
      expect(
        (row.status, row.grams, row.gramSource),
        (
          'overridden',
          0,
          'discarded',
        ),
      );
    });

    test('W2: an apply-to-all reaching a same-food plus line weighs its eaten '
        'part — "1 recipe Garlic Oil (recipe follows), plus 2 tablespoons '
        'garlic oil" over a subsection of 0405\'s "½ cup extra-virgin olive '
        'oil", in two recipes (synthesized: a stated exception) — 28 g of '
        '"Olive oil" (2710186), never the whole recipe\'s 140 g', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      const line =
          '1 recipe Garlic Oil (recipe follows), plus 2 tablespoons garlic '
          'oil';
      Recipe garlicOil(String id) => recipeOf(
        db: db,
        id: id,
        [
          [line],
        ],
        subsections: [
          subsectionOf('Garlic Oil', ['½ cup extra-virgin olive oil']),
        ],
      );
      final a = garlicOil('a');
      final b = garlicOil('b');
      expect(namesSecondFood(line), isFalse);
      await matchAndCompute(db, provider, a);
      await matchAndCompute(db, provider, b);
      await applyMatchOverride(db, provider, a, 0, {
        'fdc_id': 2710186,
        'apply_to_all': true,
      });
      final row = rowAt(db, 0, id: 'b');
      expect((row.fdcId, row.grams), (2710186, rowAt(db, 0, id: 'a').grams));
      expect(row.grams, 28);
    });
  });

  group("G: the grams guards restored for other libraries' lines — each on "
      'a synthesized line (no corpus line reaches it: a stated exception) '
      'over a recorded record', () {
    Future<GramResolution?> grams(String raw, int? fdcId) async {
      final food = fdcId == null ? null : await FixtureProvider().food(fdcId);
      return lineGrams(tempDb(), lineOf(raw), food);
    }

    test('G1: a portion must LEAD with the unit — "2 slices plums" on '
        '"Plums, raw" (169949, "cup, sliced" 165 g) and "2 slices almonds" '
        'on "Nuts, almonds" (170567, "cup, sliced") weigh nothing, never two '
        'cups', () async {
      expect(await grams('2 slices plums', 169949), isNull);
      expect(await grams('2 slices almonds', 170567), isNull);
    });

    test('G2: a volume paren saying "each" is per item — "8 Swiss chard '
        'leaves, torn (about 1 cup each)" is 8 cups (288 g on 169991), and '
        'an adjectival one too — "8 (about 1 cup; torn) Swiss chard leaves"; '
        'Hearty Chicken Noodle Soup\'s (0002) "(about 2 cups; optional)" '
        "stays the line's 2 cups, 72 g", () async {
      final each = await grams(
        '8 Swiss chard leaves, torn (about 1 cup each)',
        169991,
      );
      expect(each!.grams, closeTo(288.0, 0.1));
      final adjectival = await grams(
        '8 (about 1 cup; torn) Swiss chard leaves',
        169991,
      );
      expect(adjectival!.grams, closeTo(288.0, 0.1));
      final total = await grams(
        '4–6 Swiss chard leaves, ribs removed, torn into 1-inch pieces '
        '(about 2 cups; optional)',
        169991,
      );
      expect(total!.grams, 72);
    });

    test('P7: the teaspoon arm — "1 envelope (2¼ teaspoons; see note) '
        'instant or rapid-rise yeast" (Multigrain Bread\'s, 0809, with a '
        'note the parser leaves in the paren) is 2¼ teaspoons, 7.1 g, by '
        'the yeast density', () async {
      final g = await grams(
        '1 envelope (2¼ teaspoons; see note) instant or rapid-rise yeast',
        null,
      );
      expect(g!.grams, closeTo(7.1, 0.01));
      expect(g.basis, '2¼ teaspoon ≈ 11 mL');
    });

    test('G4: the in-item ounces — "1 15-ounce can chickpeas, rinsed" on '
        '2644288 is 425 g from the printed weight — and a litre paren — "1 '
        '(1-liter) bottle dry white wine" on 175112 (no bottle portion) is '
        '1,000 mL, 990 g', () async {
      final can = await grams('1 15-ounce can chickpeas, rinsed', 2644288);
      expect(can!.grams, closeTo(425.24, 0.01));
      final bottle = await grams('1 (1-liter) bottle dry white wine', 175112);
      expect(bottle!.grams, 990);
    });

    test('G5: flake and coarse sea salt pack like kosher salt — "2 '
        'tablespoons flake sea salt" (0227) 21.3 g, "2 teaspoons coarse sea '
        'salt, divided" (0805) 7.1 g on "Salt, table" — while fine and '
        'plain sea salt weigh as table salt, 6.0 g a teaspoon', () async {
      expect(
        (await grams('2 tablespoons flake sea salt', 173468))!.grams,
        closeTo(21.29, 0.01),
      );
      expect(
        (await grams('2 teaspoons coarse sea salt, divided', 173468))!.grams,
        closeTo(7.10, 0.01),
      );
      // "flaky": synthesized, the corpus writes "flake".
      expect(
        (await grams('½ teaspoon flaky sea salt', 173468))!.grams,
        closeTo(1.77, 0.01),
      );
      for (final raw in ['1 teaspoon fine sea salt', '1 teaspoon sea salt']) {
        expect((await grams(raw, 173468))!.grams, closeTo(6.01, 0.01));
      }
    });

    test('G3: "Do not drain slaw" drains nothing — a quick-pickle slaw\'s '
        'vinegar, sugar and salt stay eaten, never a salt bath', () {
      final r = recipeOf(
        [
          ['1 cup cider vinegar', '1 tablespoon sugar', '1½ teaspoons salt'],
        ],
        steps: [
          'Whisk vinegar, water, sugar, and salt in large bowl until sugar '
              'is dissolved. Add cabbage, onion, and carrot and toss to '
              'combine. Cover and refrigerate for at least 1 hour. Do not '
              'drain slaw; serve with its dressing.',
        ],
      );
      expect(
        [
          for (final line in nutritionLines(r))
            discardedMediumOf(r, line, normalizeItem(lineItemOf(line))),
        ],
        [null, null, null],
      );
    });
  });

  group('P3, P4, P5: the apply, un-skip and re-attach terms', () {
    test('P3: an apply-to-all lands a marked count its food weighs as that '
        'count — "8 Home-Fried Taco Shells (recipe follows)" (Ground Beef '
        'Tacos, 0478) in two recipes, one left on "Vegetable oil, NFS" by an '
        'older engine (synthesized: a stated exception): the pick of "Taco '
        'shells, baked" (172800) on the other gives it 8 shells\' grams, '
        'never the 0 g sub-recipe', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      const raw = '8 Home-Fried Taco Shells (recipe follows)';
      final a = recipeOf(db: db, id: 'a', [
        [raw],
      ]);
      final b = recipeOf(db: db, id: 'b', [
        [raw],
      ]);
      await matchAndCompute(db, provider, a);
      await matchAndCompute(db, provider, b);
      final counted = rowAt(db, 0, id: 'b').grams;
      expect(counted, greaterThan(0));
      db.upsertIngredientMatch(
        rowAt(db, 0, id: 'a').copyWith(
          fdcId: 2710180,
          description: 'Vegetable oil, NFS',
          confidence: 0.3,
          clearGrams: true,
          clearGramSource: true,
        ),
      );
      await applyMatchOverride(db, provider, b, 0, {
        'fdc_id': 172800,
        'apply_to_all': true,
      });
      final row = rowAt(db, 0, id: 'a');
      expect((row.fdcId, row.grams), (172800, counted));
    });

    // Classic Guacamole's (0471) citrus rule line: the engine counts the
    // juice on "Lime juice, raw".
    const lime = '¼ teaspoon grated lime zest plus 1½–2 tablespoons juice';

    test("P4: an un-skip keeps a person's food on a rule line — a pick of "
        '"Lime, raw" (2709170), skipped and un-skipped, is never moved to '
        "the rule's juice record", () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(db: db, [
        [lime],
      ]);
      await matchAndCompute(db, provider, r);
      expect(rowAt(db, 0).fdcId, 168156);
      await applyMatchOverride(db, provider, r, 0, {'fdc_id': 2709170});
      await applyMatchOverride(db, provider, r, 0, {'skipped': true});
      await applyMatchOverride(db, provider, r, 0, {'skipped': false});
      expect((rowAt(db, 0).status, rowAt(db, 0).fdcId), ('auto', 2709170));
    });

    test('P5: an amount edit of a confirmed line keeps no LINE hold but a '
        "medium's — Cioppino's (0108) \"1 pound mussels, scrubbed and "
        'debearded", confirmed, then "2 pounds" (synthesized: a stated '
        'exception): confirmed, no in_shell hold (the clams before v40, '
        'counted since on their shell yield)', () async {
      final db = tempDb();
      final provider = FixtureProvider();
      final r = recipeOf(db: db, [
        ['1 pound mussels, scrubbed and debearded'],
      ]);
      await matchAndCompute(db, provider, r);
      expect(rowAt(db, 0).hold, 'in_shell');
      await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
      await matchAndCompute(
        db,
        provider,
        recipeOf(db: db, [
          ['2 pounds mussels, scrubbed and debearded'],
        ]),
      );
      final row = rowAt(db, 0);
      expect((row.status, row.fdcId, row.hold), ('confirmed', 2706350, null));
      expect(row.grams, closeTo(907.18, 0.01));
    });
  });

  test("P9: a bare confirm reads the WEIGHED line's detector — a plus line "
      'whose eaten part is a quarter cup of salt no step rubs on, a held '
      'salt bath ("1 recipe Seasoned Salt, plus ¼ cup kosher salt (recipe '
      'follows)" over a subsection of "2 tablespoons kosher salt"), its row '
      'left on "Salt, table" with no grams and no hold by an older engine '
      '(all synthesized: a stated exception), confirms to 0 g poured away, '
      'never the quarter cup', () async {
    final db = tempDb();
    final provider = FixtureProvider();
    final r = recipeOf(
      db: db,
      [
        ['1 recipe Seasoned Salt, plus ¼ cup kosher salt (recipe follows)'],
      ],
      subsections: [
        subsectionOf('Seasoned Salt', ['2 tablespoons kosher salt']),
      ],
    );
    await matchAndCompute(db, provider, r);
    final eaten = weighedLine(r, nutritionLines(r).single);
    expect(heldMediumLine(r, eaten), isTrue);
    expect(heldMediumLine(r, nutritionLines(r).single), isFalse);
    db.upsertIngredientMatch(
      rowAt(db, 0).copyWith(
        fdcId: 173468,
        description: 'Salt, table',
        dataType: 'SR Legacy',
        confidence: 0.9,
        clearGrams: true,
        clearGramSource: true,
        status: 'auto',
      ),
    );
    await applyMatchOverride(db, provider, r, 0, {'confirmed': true});
    final row = rowAt(db, 0);
    expect((row.fdcId, row.grams, row.gramSource), (173468, 0, 'discarded'));
  });
}
