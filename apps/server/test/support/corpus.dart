import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:salt_shared/salt_shared.dart';

/// Root of the real Recipe Extraction corpus, overridable with the
/// `SALT_CORPUS_DIR` environment variable so the suite is not pinned to one
/// machine's home directory. Points at the source root (the directory that
/// contains `recipes/`, `images/`, and `source.yaml`).
/// Corpus source root — set `SALT_CORPUS_DIR` to point at your extraction
/// corpus (the directory containing `recipes/`, `images/`, `source.yaml`).
/// The default is `$HOME/recipe-corpus/<cookbook>`; corpus-backed tests
/// skip when it is absent (see [skipIfNoCorpus]).
String get corpusRoot =>
    Platform.environment['SALT_CORPUS_DIR'] ??
    // ignore: missing_whitespace_between_adjacent_strings
    '${Platform.environment['HOME'] ?? '.'}/recipe-corpus/'
        'The Complete America_s Test Kitchen TV Show Cookbook 2001–2023';

/// The `recipes/` directory inside [corpusRoot].
String get corpusRecipesDir => '$corpusRoot/recipes';

/// The `images/` directory inside [corpusRoot].
String get corpusImagesDir => '$corpusRoot/images';

/// Whether the corpus is present on this machine. Suites should pass this to
/// `group(..., skip: corpusAvailable ? false : 'corpus not found')`.
bool get corpusAvailable => Directory(corpusRecipesDir).existsSync();

/// Skip reason for a corpus-backed test/group: `null` (run) when the corpus
/// is present, else a message so `dart test` SKIPS rather than fails (e.g. in
/// CI). Use as `group(..., skip: skipIfNoCorpus, () {...})`.
String? get skipIfNoCorpus =>
    corpusAvailable ? null : 'ATK corpus not present; set SALT_CORPUS_DIR';

/// Decodes the corpus recipe file [fileName] (e.g.
/// `0857-rich-chocolate-bundt-cake.yaml`).
Recipe loadCorpusRecipe(String fileName) => RecipeYamlCodec.decode(
  File('$corpusRecipesDir/$fileName').readAsStringSync(),
).recipe;

/// The canonical content hash the importer computes for [recipe] (SHA-256 of
/// the canonical v2 YAML encoding).
String contentHashOf(Recipe recipe) =>
    sha256.convert(utf8.encode(RecipeYamlCodec.encode(recipe))).toString();
