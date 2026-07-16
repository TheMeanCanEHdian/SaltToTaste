import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:salt_shared/salt_shared.dart';

/// Root of the real Recipe Extraction corpus, overridable with the
/// `SALT_CORPUS_DIR` environment variable so the suite is not pinned to one
/// machine's home directory. Points at the source root (the directory that
/// contains `recipes/`, `images/`, and `source.yaml`).
const _defaultCorpusRoot =
    // ignore: missing_whitespace_between_adjacent_strings
    '/Users/drivard/Documents/Claude Projects/Recipe Extraction/'
    'The Complete America_s Test Kitchen TV Show Cookbook 2001–2023';

String get corpusRoot =>
    Platform.environment['SALT_CORPUS_DIR'] ?? _defaultCorpusRoot;

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
String contentHashOf(Recipe recipe) => sha256
    .convert(utf8.encode(RecipeYamlCodec.encode(recipe)))
    .toString();
