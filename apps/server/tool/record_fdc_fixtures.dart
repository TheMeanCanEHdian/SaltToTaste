/// Records REAL FoodData Central responses as test fixtures.
///
/// Usage: `SALT_FDC_KEY=<key> dart run tool/record_fdc_fixtures.dart`
///
/// Or, with no key and no network, copy answers FDC already gave from a
/// sweep snapshot's cache into the fixtures (merged; an entry already
/// recorded is kept):
/// `dart run tool/record_fdc_fixtures.dart --from-db <snapshot.db>
/// 'search=<query>' … 'food=<fdc id>' …` — the snapshot is opened read-only.
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
import 'package:sqlite3/sqlite3.dart';

const _recipes = [
  '0857-rich-chocolate-bundt-cake.yaml',
  '0747-100-percent-whole-wheat-pancakes.yaml',
];

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == '--from-db') {
    _fromSnapshot(args.skip(1).toList());
    return;
  }
  final key = Platform.environment['SALT_FDC_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Set SALT_FDC_KEY to a real api.data.gov key.');
    exitCode = 64;
    return;
  }
  final corpusRoot =
      Platform.environment['SALT_CORPUS_DIR'] ??
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
        if (query.isEmpty ||
            isWaterLike(query) ||
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
  File(
    '${outDir.path}/searches.json',
  ).writeAsStringSync(encoder.convert(searches));
  File('${outDir.path}/foods.json').writeAsStringSync(encoder.convert(foods));
  stdout.writeln(
    'Recorded ${searches.length} searches and ${foods.length} foods.',
  );
}

const String _searchSql =
    'SELECT response FROM fdc_search_cache WHERE query = ?';
const String _foodSql = 'SELECT response FROM fdc_food_cache WHERE fdc_id = ?';

/// `--from-db <snapshot> search=<query>… food=<id>…`: the snapshot's cached
/// FDC answers merged into the fixtures, in their existing one-space style.
void _fromSnapshot(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: --from-db <snapshot.db> search=<q>… food=<id>…');
    exitCode = 64;
    return;
  }
  final db = sqlite3.open(args.first, mode: OpenMode.readOnly);
  final files = {
    'searches': File('test/fixtures/fdc/searches.json'),
    'foods': File('test/fixtures/fdc/foods.json'),
  };
  final fixtures = {
    for (final MapEntry(:key, :value) in files.entries)
      key: jsonDecode(value.readAsStringSync()) as Map<String, dynamic>,
  };
  for (final arg in args.skip(1)) {
    final at = arg.indexOf('=');
    final kind = at < 0 ? '' : arg.substring(0, at);
    final value = at < 0 ? '' : arg.substring(at + 1);
    final (fixture, sql, param) = switch (kind) {
      'search' => (fixtures['searches']!, _searchSql, value as Object),
      'food' => (fixtures['foods']!, _foodSql, int.parse(value) as Object),
      _ => throw ArgumentError('Expected search=<q> or food=<id>: $arg'),
    };
    final rows = db.select(sql, [param]);
    if (rows.isEmpty) {
      stderr.writeln('not in the snapshot cache: $arg');
      exitCode = 1;
      continue;
    }
    fixture.putIfAbsent(
      value,
      () => jsonDecode(rows.first['response'] as String),
    );
  }
  db.dispose();
  const encoder = JsonEncoder.withIndent(' ');
  for (final MapEntry(:key, :value) in files.entries) {
    value.writeAsStringSync(encoder.convert(fixtures[key]));
  }
}
