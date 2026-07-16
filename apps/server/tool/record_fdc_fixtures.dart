/// Records REAL FoodData Central responses as test fixtures.
///
/// Usage: `SALT_FDC_KEY=<key> dart run tool/record_fdc_fixtures.dart`
///
/// For every distinct ingredient of the fixture recipes (the Bundt cake and
/// whole-wheat pancakes — the corpus recipes the nutrition tests exercise),
/// the search response and the best-ranked food's detail are written to
/// `test/fixtures/fdc/` in the provider's trimmed JSON shapes. The key
/// comes from the environment and never appears in the output.
library;

import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/nutrition/fdc_provider.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';

const _recipes = [
  '0857-rich-chocolate-bundt-cake.yaml',
  '0747-100-percent-whole-wheat-pancakes.yaml',
];

Future<void> main() async {
  final key = Platform.environment['SALT_FDC_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Set SALT_FDC_KEY to a real api.data.gov key.');
    exitCode = 64;
    return;
  }
  final corpusRoot = Platform.environment['SALT_CORPUS_DIR'] ??
      // ignore: missing_whitespace_between_adjacent_strings
      '${Platform.environment['HOME'] ?? '.'}/recipe-corpus/'
          'The Complete America_s Test Kitchen TV Show Cookbook 2001–2023';
  final provider = UsdaFdcProvider(apiKey: () => key);
  final outDir = Directory('test/fixtures/fdc')..createSync(recursive: true);

  final searches = <String, Object?>{};
  final foods = <String, Object?>{};
  for (final fileName in _recipes) {
    final recipe = RecipeYamlCodec.decode(
      File('$corpusRoot/recipes/$fileName').readAsStringSync(),
    ).recipe;
    for (final group in recipe.ingredients) {
      for (final line in group.items) {
        final query = normalizeItem(line.item ?? line.raw);
        if (query.isEmpty || isWaterLike(query) ||
            searches.containsKey(query)) {
          continue;
        }
        stdout.writeln('search: $query');
        final candidates = await provider.search(query);
        searches[query] = [for (final c in candidates) c.toJson()];
        // Mirror the engine: the top candidate's detail can 404 (FDC keeps
        // superseded records in search) — record the first fetchable one.
        for (final ranked in rankCandidates(query, candidates).take(8)) {
          final id = ranked.candidate.fdcId;
          if (foods.containsKey('$id')) {
            break;
          }
          stdout.writeln('  food: $id ${ranked.candidate.description}');
          final food = await provider.food(id);
          if (food != null) {
            foods['$id'] = food.toJson();
            break;
          }
          stdout.writeln('    (detail 404 — falling back)');
        }
      }
    }
  }

  const encoder = JsonEncoder.withIndent('  ');
  File('${outDir.path}/searches.json')
      .writeAsStringSync(encoder.convert(searches));
  File('${outDir.path}/foods.json').writeAsStringSync(encoder.convert(foods));
  stdout.writeln(
    'Recorded ${searches.length} searches and ${foods.length} foods.',
  );
}
