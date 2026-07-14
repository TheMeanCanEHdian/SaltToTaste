/// P0 gate: the recipe YAML codec must decode, round-trip, and derive
/// servings for the entire real extraction corpus (1,198 recipes).
library;

import 'dart:io';

import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

const String _corpusDir =
    '/Users/drivard/Documents/Claude Projects/Recipe Extraction/'
    'The Complete America_s Test Kitchen TV Show Cookbook 2001–2023/recipes';

const int _expectedCorpusSize = 1198;

/// The corpus files, sorted by path for deterministic output.
List<File> _corpusFiles() {
  final dir = Directory(_corpusDir);
  expect(
    dir.existsSync(),
    isTrue,
    reason: 'corpus directory not found: $_corpusDir',
  );
  final files = dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.yaml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _name(File file) => file.uri.pathSegments.last;

RecipeDecodeResult _decodeFile(File file) =>
    RecipeYamlCodec.decode(file.readAsStringSync());

File _corpusFile(String name) => File('$_corpusDir/$name');

void main() {
  group('corpus', () {
    test('all files decode without errors', () {
      final files = _corpusFiles();
      expect(files.length, _expectedCorpusSize);

      final failures = <String>[];
      final warningCounts = <String, int>{};
      for (final file in files) {
        try {
          final result = _decodeFile(file);
          for (final warning in result.warnings) {
            final type = warning.split(':').first.trim();
            warningCounts[type] = (warningCounts[type] ?? 0) + 1;
          }
        } catch (error) {
          failures.add('${_name(file)}: $error');
        }
      }

      print('decoded ${files.length - failures.length}/${files.length} files');
      print('aggregate warning counts by type: '
          '${warningCounts.isEmpty ? '(none)' : warningCounts}');
      if (failures.isNotEmpty) {
        print('DECODE FAILURES (${failures.length}):');
        failures.forEach(print);
      }
      expect(failures, isEmpty);
    });

    test('round-trip parse -> emit -> parse is model-equal', () {
      final files = _corpusFiles();
      final mismatches = <String>[];
      for (final file in files) {
        final Recipe original;
        try {
          original = _decodeFile(file).recipe;
        } catch (_) {
          // Decode failures are reported (with details) by the decode test.
          continue;
        }
        try {
          final reparsed =
              RecipeYamlCodec.decode(RecipeYamlCodec.encode(original)).recipe;
          if (reparsed != original) {
            mismatches.add(
              '${_name(file)}: differing top-level fields: '
              '${_differingFields(original, reparsed)}',
            );
          }
        } catch (error) {
          mismatches.add('${_name(file)}: re-decode threw: $error');
        }
      }

      if (mismatches.isNotEmpty) {
        print('ROUND-TRIP MISMATCHES (${mismatches.length}):');
        mismatches.forEach(print);
      }
      expect(mismatches, isEmpty);
    });

    test('servings coverage', () {
      final files = _corpusFiles();
      var total = 0;
      var parsed = 0;
      var nullServings = 0;
      final unparseable = <String>[];
      for (final file in files) {
        final recipe = _decodeFile(file).recipe;
        total++;
        if (recipe.servings == null) {
          nullServings++;
        } else if (recipe.serves != null) {
          parsed++;
        } else {
          unparseable.add('${_name(file)}: ${recipe.servings}');
        }
      }

      print('servings coverage: total=$total parsed=$parsed '
          'null=$nullServings unparseable=${unparseable.length}');
      if (unparseable.isNotEmpty) {
        print('UNPARSEABLE SERVINGS (${unparseable.length}):');
        unparseable.forEach(print);
      }
      expect(
        unparseable.length,
        lessThanOrEqualTo(5),
        reason: 'the servings parser was built from the corpus vocabulary — '
            'more than 5 unparseable values means a regression',
      );
      expect(
        unparseable,
        isEmpty,
        reason: 'expected full corpus coverage (see printed list)',
      );
    });
  });

  group('targeted: 0857-rich-chocolate-bundt-cake', () {
    late Recipe recipe;

    setUpAll(() {
      recipe = _decodeFile(
        _corpusFile('0857-rich-chocolate-bundt-cake.yaml'),
      ).recipe;
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
      recipe = _decodeFile(_corpusFile('0038-foolproof-vinaigrette.yaml'))
          .recipe;
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
      recipe = _decodeFile(_corpusFile('0020-sweet-potato-soup.yaml')).recipe;
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
      final reparsed =
          RecipeYamlCodec.decode(RecipeYamlCodec.encode(recipe)).recipe;
      expect(reparsed, recipe);
      expect(reparsed.subsections.first.ingredients, isNotNull);
      expect(reparsed.subsections.first.steps, isEmpty);
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
