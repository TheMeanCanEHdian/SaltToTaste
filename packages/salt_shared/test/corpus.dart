/// Shared access to the real ATK extraction corpus for tests.
///
/// Single source of truth for the corpus location, file listing, raw-value
/// scanning, and a decode-everything-once cache shared by all suites in a
/// test process.
library;

import 'dart:io';

import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

/// Overridable via the `SALT_CORPUS_DIR` environment variable so the suite
/// is not pinned to one machine's checkout location.
final String corpusDir = Platform.environment['SALT_CORPUS_DIR'] ??
    '/Users/drivard/Documents/Claude Projects/Recipe Extraction/'
        'The Complete America_s Test Kitchen TV Show Cookbook 2001–2023/recipes';

const int expectedCorpusSize = 1198;

/// The corpus files, sorted by path for deterministic output.
List<File> corpusFiles() {
  final dir = Directory(corpusDir);
  expect(
    dir.existsSync(),
    isTrue,
    reason: 'corpus directory not found: $corpusDir',
  );
  final files = dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.yaml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

File corpusFile(String name) => File('$corpusDir/$name');

String corpusFileName(File file) => file.uri.pathSegments.last;

/// The result of decoding the full corpus: successful decodes by file name,
/// and error messages for any failures.
class CorpusDecode {
  CorpusDecode(this.results, this.failures);

  final Map<String, RecipeDecodeResult> results;
  final Map<String, String> failures;
}

CorpusDecode? _cachedDecode;

/// Decodes every corpus file exactly once per test process; all suites share
/// the cached result so the 1,198-file pass is not repeated per test.
CorpusDecode decodeCorpus() {
  final cached = _cachedDecode;
  if (cached != null) return cached;
  final results = <String, RecipeDecodeResult>{};
  final failures = <String, String>{};
  for (final file in corpusFiles()) {
    final name = corpusFileName(file);
    try {
      results[name] = RecipeYamlCodec.decode(file.readAsStringSync());
    } catch (error) {
      failures[name] = '$error';
    }
  }
  return _cachedDecode = CorpusDecode(results, failures);
}

/// Collects the distinct captured values of [lineRe]'s first group across
/// every corpus file, unquoting single-quoted YAML scalars and skipping
/// empty/`null` values. Set [firstMatchOnly] to scan only the first match
/// per file (e.g. the single `servings:` line).
Set<String> distinctCorpusValues(RegExp lineRe, {bool firstMatchOnly = false}) {
  final values = <String>{};
  for (final file in corpusFiles()) {
    final content = file.readAsStringSync();
    final matches = firstMatchOnly
        ? [lineRe.firstMatch(content)].whereType<RegExpMatch>()
        : lineRe.allMatches(content);
    for (final match in matches) {
      var value = match.group(1)!.trim();
      if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isEmpty || value == 'null') continue;
      values.add(value);
    }
  }
  return values;
}
