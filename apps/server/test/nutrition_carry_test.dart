import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Match rows are keyed by POSITION. Before 2026-09-07 an edit above a
/// decided line — insert, delete, reorder — moved the line out from under
/// its row and the compute re-resolved it as `auto`: the confirm, the
/// re-pick, the hand-set weight and the skip were all lost (reproduced on
/// the Bundt cake, survey 2026-09-04). Now a decided row follows its line by
/// text, the nth repeated line keeps the nth row, and an amount edit on a
/// decided line keeps the food and the status while the grams are
/// re-derived. Real corpus recipes, recorded FDC payloads.
void main() {
  group('decisions follow their lines', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late ServerConfig config;
    late SaltDatabase db;
    late FixtureProvider provider;
    late Recipe bundt;
    late Recipe acquacotta;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt-carry-test');
      config = ServerConfig(
        dataDir: tempDir.path,
        logLevel: Level.WARNING,
        trustProxy: false,
      );
      db = SaltDatabase.open(config.dbPath);
      final sourceRoot = Directory('${tempDir.path}/source')
        ..createSync(recursive: true);
      Directory('${sourceRoot.path}/recipes').createSync();
      for (final name in [
        '0857-rich-chocolate-bundt-cake.yaml',
        '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
      ]) {
        File(
          '$corpusRecipesDir/$name',
        ).copySync('${sourceRoot.path}/recipes/$name');
      }
      importSourceRoot(sourceRootPath: sourceRoot.path, db: db, config: config);
      provider = FixtureProvider();
      bundt = db.recipeByIdOrSlug('rich-chocolate-bundt-cake')!.recipe;
      acquacotta = db
          .recipeByIdOrSlug('acquacotta-tuscan-white-bean-and-escarole-soup')!
          .recipe;
      for (final recipe in [bundt, acquacotta]) {
        await matchAndCompute(db, provider, recipe);
      }
    });

    tearDownAll(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    List<int> positionsOf(Recipe recipe, String word) => [
      for (final (i, line) in nutritionLines(recipe).indexed)
        if (line.raw.contains(word)) i,
    ];

    int positionOf(Recipe recipe, String word) {
      final positions = positionsOf(recipe, word);
      expect(positions, isNotEmpty, reason: '$word must be a real line');
      return positions.first;
    }

    IngredientMatchRow rowAt(Recipe recipe, int position) => db
        .ingredientMatchesFor(recipe.id)
        .firstWhere((row) => row.position == position);

    IngredientLine lineFrom(String raw) {
      final parsed = parseIngredientLine(raw);
      return IngredientLine(
        raw: raw,
        item: parsed.item,
        prep: parsed.prep,
        amounts: parsed.amounts,
      );
    }

    /// Stores [recipe] with its top-level lines replaced, recomputes, and
    /// returns the stored recipe.
    Future<Recipe> store(Recipe recipe, List<IngredientLine> lines) async {
      final edited = recipe.copyWith(
        ingredients: [IngredientGroup(items: lines)],
      );
      db.upsertRecipe(
        edited,
        sourceSlug: db.recipeByIdOrSlug(recipe.id)!.sourceSlug,
        contentHash: 'edit-${DateTime.now().microsecondsSinceEpoch}',
      );
      final reloaded = db.recipeByIdOrSlug(recipe.id)!.recipe;
      await matchAndCompute(db, provider, reloaded);
      return reloaded;
    }

    Future<int> otherFoodFor(Recipe recipe, int position, int notThis) async {
      for (final candidate in await candidatesForLine(
        db,
        provider,
        nutritionLines(recipe)[position],
        cacheOnly: true,
      )) {
        if (candidate.candidate.fdcId != notThis &&
            await cachedFood(db, provider, candidate.candidate.fdcId) != null) {
          return candidate.candidate.fdcId;
        }
      }
      fail('no other recorded food for the line');
    }

    late int eggsAlt;
    late int sourCreamFood;

    test('setup: a re-pick, a confirm and a skip on three lines', () async {
      final eggs = positionOf(bundt, 'eggs');
      final sourCream = positionOf(bundt, 'sour cream');
      final soda = positionOf(bundt, 'baking soda');
      eggsAlt = await otherFoodFor(bundt, eggs, rowAt(bundt, eggs).fdcId!);
      await applyMatchOverride(db, provider, bundt, eggs, {'fdc_id': eggsAlt});
      sourCreamFood = rowAt(bundt, sourCream).fdcId!;
      await applyMatchOverride(db, provider, bundt, sourCream, {
        'confirmed': true,
      });
      await applyMatchOverride(db, provider, bundt, soda, {'skipped': true});
      expect(rowAt(bundt, eggs).status, 'overridden');
      expect(rowAt(bundt, sourCream).status, 'confirmed');
      expect(rowAt(bundt, soda).status, 'skipped');
    });

    void expectDecisions(Recipe recipe) {
      final eggs = rowAt(recipe, positionOf(recipe, 'eggs'));
      expect(eggs.status, 'overridden');
      expect(eggs.fdcId, eggsAlt);
      final sourCream = rowAt(recipe, positionOf(recipe, 'sour cream'));
      expect(sourCream.status, 'confirmed');
      expect(sourCream.fdcId, sourCreamFood);
      expect(
        rowAt(recipe, positionOf(recipe, 'baking soda')).status,
        'skipped',
      );
    }

    test('a line inserted ABOVE: every decision follows its line', () async {
      final before = positionOf(bundt, 'eggs');
      bundt = await store(bundt, [
        lineFrom('2 tablespoons sugar'),
        ...nutritionLines(bundt),
      ]);
      expect(positionOf(bundt, 'eggs'), before + 1);
      expectDecisions(bundt);
      expect(rowAt(bundt, 0).status, 'auto', reason: 'the new line');
    });

    test('a line deleted ABOVE: every decision follows its line', () async {
      bundt = await store(bundt, nutritionLines(bundt).sublist(1));
      expectDecisions(bundt);
    });

    test('a line moved to the end keeps its decision there', () async {
      final lines = [...nutritionLines(bundt)];
      final eggs = lines.removeAt(positionOf(bundt, 'eggs'));
      bundt = await store(bundt, [...lines, eggs]);
      expect(positionOf(bundt, 'eggs'), lines.length);
      expectDecisions(bundt);
    });

    test('the nth repeated line keeps the nth row', () async {
      // Acquacotta lists "Salt and pepper" twice, word for word.
      final salts = positionsOf(acquacotta, 'Salt and pepper');
      expect(salts, hasLength(2), reason: 'listed twice');
      final lines = nutritionLines(acquacotta);
      expect(lines[salts[0]].raw, lines[salts[1]].raw, reason: 'same text');
      await applyMatchOverride(db, provider, acquacotta, salts[1], {
        'skipped': true,
      });
      expect(rowAt(acquacotta, salts[0]).status, isNot('skipped'));
      acquacotta = await store(acquacotta, [
        lineFrom('2 tablespoons sugar'),
        ...lines,
      ]);
      final after = positionsOf(acquacotta, 'Salt and pepper');
      expect(after, [salts[0] + 1, salts[1] + 1]);
      expect(rowAt(acquacotta, after[0]).status, isNot('skipped'));
      expect(rowAt(acquacotta, after[1]).status, 'skipped');
    });

    test(
      'an amount edit on a re-picked line keeps the food and the status; '
      'the grams follow the new amount, a hand-typed weight does not',
      () async {
        final position = positionOf(bundt, 'eggs');
        final before = rowAt(bundt, position);
        expect(before.raw, startsWith('5 large'));
        expect(before.grams, isNotNull);
        final lines = [...nutritionLines(bundt)];
        lines[position] = lineFrom(
          before.raw.replaceFirst('5 large', '6 large'),
        );
        bundt = await store(bundt, lines);
        var after = rowAt(bundt, position);
        expect(after.status, 'overridden');
        expect(after.fdcId, eggsAlt);
        expect(after.grams, closeTo(before.grams! * 6 / 5, 0.01));
        expect(after.gramSource, before.gramSource);

        await applyMatchOverride(db, provider, bundt, position, {
          'grams': 999,
        });
        expect(rowAt(bundt, position).gramSource, 'override');
        lines[position] = lineFrom(
          after.raw.replaceFirst('6 large', '7 large'),
        );
        bundt = await store(bundt, lines);
        after = rowAt(bundt, position);
        expect(after.status, 'overridden');
        expect(after.fdcId, eggsAlt);
        expect(after.grams, closeTo(before.grams! * 7 / 5, 0.01));
        expect(after.gramSource, isNot('override'), reason: 'typed for 6');
      },
    );

    test('an amount edit on a skipped line keeps the skip', () async {
      final position = positionOf(bundt, 'baking soda');
      final raw = rowAt(bundt, position).raw;
      final lines = [...nutritionLines(bundt)];
      lines[position] = lineFrom(raw.replaceFirst(RegExp(r'^\S+'), '2'));
      bundt = await store(bundt, lines);
      expect(rowAt(bundt, position).status, 'skipped');
      expect(rowAt(bundt, position).raw, startsWith('2 '));
    });
  });
}
