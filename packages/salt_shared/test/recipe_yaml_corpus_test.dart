/// P0 gate: the recipe YAML codec must decode, round-trip, and derive
/// servings for the entire real extraction corpus (1,198 recipes).
library;

import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'corpus.dart';

RecipeDecodeResult _decode(String name) =>
    RecipeYamlCodec.decode(corpusFile(name).readAsStringSync());

void main() {
  // Corpus-backed: skip (not fail) when the ATK corpus is absent — e.g. CI.
  if (!corpusAvailable) {
    test(
      'corpus-backed tests (skipped: corpus absent)',
      () {},
      skip: 'ATK corpus not present; set SALT_CORPUS_DIR',
    );
    return;
  }
  // Decoded once and shared by every test in this suite (and any other suite
  // in the same process) — the corpus is 1,198 files, so repeat passes are
  // the dominant cost of this gate.
  late CorpusDecode corpus;

  setUpAll(() {
    corpus = decodeCorpus();
  });

  group('corpus', () {
    test('all files decode without errors', () {
      final total = corpus.results.length + corpus.failures.length;
      expect(total, expectedCorpusSize);

      final warningCounts = <String, int>{};
      for (final result in corpus.results.values) {
        for (final warning in result.warnings) {
          final type = warning.split(':').first.trim();
          warningCounts[type] = (warningCounts[type] ?? 0) + 1;
        }
      }

      print('decoded ${corpus.results.length}/$total files');
      print(
        'aggregate warning counts by type: '
        '${warningCounts.isEmpty ? '(none)' : warningCounts}',
      );
      if (corpus.failures.isNotEmpty) {
        print('DECODE FAILURES (${corpus.failures.length}):');
        corpus.failures.forEach((name, error) => print('$name: $error'));
      }
      expect(corpus.failures, isEmpty);
    });

    test('round-trip parse -> emit -> parse is model-equal', () {
      final mismatches = <String>[];
      corpus.results.forEach((name, result) {
        final original = result.recipe;
        try {
          final reparsed = RecipeYamlCodec.decode(
            RecipeYamlCodec.encode(original),
          ).recipe;
          if (reparsed != original) {
            mismatches.add(
              '$name: differing top-level fields: '
              '${_differingFields(original, reparsed)}',
            );
          }
        } catch (error) {
          mismatches.add('$name: re-decode threw: $error');
        }
      });

      if (mismatches.isNotEmpty) {
        print('ROUND-TRIP MISMATCHES (${mismatches.length}):');
        mismatches.forEach(print);
      }
      expect(mismatches, isEmpty);
    });

    test('servings coverage', () {
      // Every non-blank `servings` string must be understood as exactly one
      // of two things, because they are two different facts:
      //   serves     — how many people it feeds  (`SERVES 4 TO 6`)
      //   yield-only — how many units it makes   (`MAKES 4 BURGERS`)
      // A yield is deliberately NOT a serving count, so `serves` is null for
      // those; parseYieldCount must still read the count, or we have simply
      // lost the number. Anything neither parser understands is a regression.
      var parsed = 0;
      var nullServings = 0;
      final yieldOnly = <String>[];
      final unparseable = <String>[];
      corpus.results.forEach((name, result) {
        final recipe = result.recipe;
        if (recipe.servings == null) {
          nullServings++;
        } else if (recipe.serves != null) {
          parsed++;
        } else if (parseYieldCount(recipe.servings) != null) {
          yieldOnly.add('$name: ${recipe.servings}');
        } else {
          unparseable.add('$name: ${recipe.servings}');
        }
      });

      print(
        'servings coverage: total=${corpus.results.length} '
        'parsed=$parsed null=$nullServings '
        'yield-only=${yieldOnly.length} '
        'unparseable=${unparseable.length}',
      );
      if (unparseable.isNotEmpty) {
        print('UNPARSEABLE SERVINGS (${unparseable.length}):');
        unparseable.forEach(print);
      }
      expect(
        unparseable,
        isEmpty,
        reason:
            'the servings parser was built from the corpus vocabulary — a '
            'value neither parseServings nor parseYieldCount understands is '
            'a regression (see printed list)',
      );
      // Pin the split itself: if parseServings ever regains its old habit of
      // reading a yield as a serving count, `parsed` climbs, `yieldOnly`
      // falls, and this fails — which is exactly the bug the backfill undid.
      expect(
        yieldOnly,
        hasLength(173),
        reason:
            'the corpus has 173 yield-only recipes (`MAKES 4 BURGERS`); a '
            'change here means parseServings is reading yields as servings '
            'again, or parseYieldCount stopped reading them at all',
      );
    });
  });

  group('targeted: 0857-rich-chocolate-bundt-cake', () {
    late Recipe recipe;

    setUpAll(() {
      recipe = _decode('0857-rich-chocolate-bundt-cake.yaml').recipe;
    });

    test('v1 upgrade stamps schema_version 2 and derives serves', () {
      expect(recipe.schemaVersion, 2);
      expect(recipe.servings, 'SERVES 12');
      expect(recipe.serves, const Serves(min: 12, max: 12));
      expect(recipe.times.isEmpty, isTrue);
    });

    test("butter quantity is the string '12'", () {
      final butter = recipe.ingredients.first.items.first;
      expect(butter.raw, startsWith('12 tablespoons'));
      expect(butter.amounts.single.quantity, '12');
    });

    test('flour line has dual amounts: volume primary, weight secondary', () {
      final flour = recipe.ingredients.first.items.firstWhere(
        (line) => line.raw.contains('unbleached all-purpose flour'),
      );
      expect(flour.amounts, hasLength(2));
      expect(flour.amounts[0].measure, Measure.volume);
      expect(flour.amounts[0].primary, isTrue);
      expect(flour.amounts[0].quantity, '1 3/4');
      expect(flour.amounts[1].measure, Measure.weight);
      expect(flour.amounts[1].primary, isFalse);
      expect(flour.amounts[1].quantity, '8 3/4');
    });

    test("isbn is the string '9781954210110'", () {
      expect(recipe.source.isbn, '9781954210110');
    });

    test('subsections is empty (present-but-empty list)', () {
      expect(recipe.subsections, isEmpty);
    });
  });

  group('targeted: 0038-foolproof-vinaigrette (prose-only subsections)', () {
    late Recipe recipe;

    setUpAll(() {
      recipe = _decode('0038-foolproof-vinaigrette.yaml').recipe;
    });

    test('prose-only subsection has null (omitted) sub-recipe fields', () {
      expect(recipe.subsections, isNotEmpty);
      for (final subsection in recipe.subsections) {
        expect(subsection.ingredients, isNull);
        expect(subsection.steps, isNull);
        expect(subsection.servings, isNull);
        expect(subsection.title, isNotNull);
      }
    });

    test('sub-recipe fields stay null (omitted) after round-trip', () {
      final encoded = RecipeYamlCodec.encode(recipe);
      final reparsed = RecipeYamlCodec.decode(encoded).recipe;
      expect(reparsed, recipe);
      for (final subsection in reparsed.subsections) {
        expect(subsection.ingredients, isNull);
        expect(subsection.steps, isNull);
      }
    });
  });

  group('targeted: 0020-sweet-potato-soup (full sub-recipes)', () {
    late Recipe recipe;

    setUpAll(() {
      recipe = _decode('0020-sweet-potato-soup.yaml').recipe;
    });

    test('subsections are full sub-recipes with non-null ingredients', () {
      expect(recipe.subsections, hasLength(3));
      for (final subsection in recipe.subsections) {
        expect(subsection.ingredients, isNotNull);
        expect(subsection.ingredients, isNotEmpty);
        // Present-but-empty steps list survives (distinct from null).
        expect(subsection.steps, isNotNull);
        expect(subsection.steps, isEmpty);
        expect(subsection.servings, isNotNull);
      }
      final croutons = recipe.subsections.first;
      expect(croutons.title, 'Buttery Rye Croutons');
      expect(croutons.ingredients!.first.items, hasLength(4));
    });

    test('technique step image path is set', () {
      final technique = recipe.techniques.single;
      expect(technique.heading, 'PUTTING PEELS TO WORK');
      expect(
        technique.steps.single.image,
        'images/0020-sweet-potato-soup-technique-01-01.jpg',
      );
    });

    test('hero image is null', () {
      expect(recipe.images.hero, isNull);
    });

    test('sub-recipe shape survives round-trip', () {
      final reparsed = RecipeYamlCodec.decode(
        RecipeYamlCodec.encode(recipe),
      ).recipe;
      expect(reparsed, recipe);
      expect(reparsed.subsections.first.ingredients, isNotNull);
      expect(reparsed.subsections.first.steps, isEmpty);
    });
  });

  group('P0 review regressions', () {
    late String bundtText;

    setUpAll(() {
      bundtText = corpusFile(
        '0857-rich-chocolate-bundt-cake.yaml',
      ).readAsStringSync();
    });

    test('schema_version spellings 1, \'1\', and 1.0 all upgrade to v2', () {
      for (final spelling in ['1', "'1'", '1.0']) {
        final result = RecipeYamlCodec.decode(
          'schema_version: $spelling\n$bundtText',
        );
        expect(
          result.recipe.schemaVersion,
          2,
          reason: 'schema_version: $spelling must upgrade',
        );
        expect(
          result.recipe.serves,
          const Serves(min: 12, max: 12),
          reason: 'serves must be derived for schema_version: $spelling',
        );
      }
    });

    test('schema_version above 2 warns in any spelling', () {
      for (final spelling in ['3', "'3'", '3.0']) {
        final result = RecipeYamlCodec.decode(
          'schema_version: $spelling\n$bundtText',
        );
        expect(
          result.warnings,
          anyElement(contains('unsupported schema_version: 3')),
          reason: 'schema_version: $spelling must warn',
        );
      }
    });

    test('unrecognizable schema_version warns and is treated as v1', () {
      final result = RecipeYamlCodec.decode(
        'schema_version: banana\n$bundtText',
      );
      expect(
        result.warnings,
        anyElement(contains('unrecognizable schema_version: banana')),
      );
      expect(result.recipe.schemaVersion, 2);
      expect(result.recipe.serves, isNotNull);
    });

    test(
      'hand-edited unquoted scalars decode as strings (mapper coercion)',
      () {
        // A hand-edit can drop the quotes YAML needs to keep these strings;
        // the codec relies on dart_mappable's String decoder accepting any
        // scalar via toString(). This test pins that behavior.
        final edited = bundtText
            .replaceFirst("isbn: '9781954210110'", 'isbn: 9781954210110')
            .replaceFirst(
              "extracted_at: '2026-06-30'",
              'extracted_at: 20260630',
            )
            .replaceFirst("quantity: '12'", 'quantity: 12');
        expect(edited, isNot(bundtText), reason: 'replacements must apply');
        final recipe = RecipeYamlCodec.decode(edited).recipe;
        expect(recipe.source.isbn, '9781954210110');
        expect(recipe.extraction!.extractedAt, '20260630');
        expect(
          recipe.ingredients.first.items.first.amounts.single.quantity,
          '12',
        );
      },
    );

    test('every toMap field survives encode (no silent field drops)', () {
      // encode() derives its document from toMap(), so a newly added model
      // field cannot be silently dropped. Exercise all v2 extras at once.
      final base = _decode('0857-rich-chocolate-bundt-cake.yaml').recipe;
      final full = base.copyWith(
        times: const RecipeTimes(prep: 20, cook: 50, total: 190),
        images: const RecipeImages(
          hero: 'images/0857-rich-chocolate-bundt-cake-hero.jpg',
          gallery: ['images/extra-1.jpg'],
          credit: 'https://example.com/photo',
        ),
        source: base.source.copyWith(url: 'https://example.com/recipe'),
        notes: 'Shared note.',
      );
      final reparsed = RecipeYamlCodec.decode(RecipeYamlCodec.encode(full));
      expect(reparsed.recipe, full);
      expect(reparsed.warnings, isEmpty);

      final encodedKeys = RecipeYamlCodec.decode(
        RecipeYamlCodec.encode(full),
      ).recipe.toMap();
      for (final key in full.toMap().keys) {
        expect(
          encodedKeys.containsKey(key),
          isTrue,
          reason: 'field $key lost in encode round-trip',
        );
      }
    });

    test('emitted extracted_at stays quoted (PyYAML would read a date)', () {
      final recipe = _decode('0857-rich-chocolate-bundt-cake.yaml').recipe;
      final emitted = RecipeYamlCodec.encode(recipe);
      expect(emitted, contains("extracted_at: '2026-06-30'"));
    });
  });
}

/// Names the top-level fields whose encoded values differ between [a] and
/// [b], for round-trip failure diagnosis.
List<String> _differingFields(Recipe a, Recipe b) {
  final mapA = a.toMap();
  final mapB = b.toMap();
  final keys = <String>{...mapA.keys, ...mapB.keys};
  final differing = <String>[];
  for (final key in keys) {
    final Object? valueA = mapA[key];
    final Object? valueB = mapB[key];
    if ('$valueA' != '$valueB') differing.add(key);
  }
  return differing;
}
