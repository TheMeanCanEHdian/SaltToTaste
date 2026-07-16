import 'dart:io';

import 'package:salt_shared/salt_shared.dart';

/// Access to the real ATK extraction corpus from the Flutter app's tests.
///
/// Mirrors `apps/server/test/support/corpus.dart` — the app package cannot
/// import another package's test directory, so the loader is duplicated
/// rather than shared. Set `SALT_CORPUS_DIR` to the source root (the
/// directory containing `recipes/`, `images/`, `source.yaml`).
String get corpusRoot =>
    Platform.environment['SALT_CORPUS_DIR'] ??
    // ignore: missing_whitespace_between_adjacent_strings
    '${Platform.environment['HOME'] ?? '.'}/recipe-corpus/'
        'The Complete America_s Test Kitchen TV Show Cookbook 2001–2023';

/// The `recipes/` directory inside [corpusRoot].
String get corpusRecipesDir => '$corpusRoot/recipes';

/// Whether the corpus is present on this machine (CI runs without it).
bool get corpusAvailable => Directory(corpusRecipesDir).existsSync();

/// Skip reason for a corpus-backed test/group: `null` (run) when the corpus
/// is present, else a message so the suite SKIPS rather than fails.
String? get skipIfNoCorpus =>
    corpusAvailable ? null : 'ATK corpus not present; set SALT_CORPUS_DIR';

/// Decodes the corpus recipe file [fileName] (e.g.
/// `0857-rich-chocolate-bundt-cake.yaml`).
Recipe loadCorpusRecipe(String fileName) => RecipeYamlCodec.decode(
  File('$corpusRecipesDir/$fileName').readAsStringSync(),
).recipe;

/// Every corpus recipe, decoded once per test process.
List<Recipe> loadAllCorpusRecipes() {
  final files =
      Directory(corpusRecipesDir)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      RecipeYamlCodec.decode(file.readAsStringSync()).recipe,
  ];
}
