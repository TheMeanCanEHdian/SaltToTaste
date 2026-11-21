/// Widens the cached FDC details with numbers their raw details publish
/// (v123, batch PB1): the cache keeps only the numbers the map read when it
/// was written, and nothing re-fetches a detail.
///
/// Usage (from apps/server; no key, no network — files only):
/// `dart run tool/fdc_merge_numbers.dart --db <db> --raw-dir <dir>
/// [--raw-dir <dir> …] --numbers <n>[,<n>…] [--dry-run]`
///
/// A thin loop over `mergeNumbers` (provider.dart): every `*.json` of each
/// dir whose top-level object holds `fdcId` and `foodNutrients` is a raw
/// detail (any other file is skipped and counted), read by
/// `fdcDetailNutrients` with every number kept; each `fdc_food_cache` row
/// with a raw, in ascending `fdc_id` order, gains the `--numbers` it lacks.
/// ONE transaction of `UPDATE fdc_food_cache SET response = ?` for the rows
/// that gained a number — `fetched_at` kept, never an INSERT, never the
/// search tables; the file opened plainly (no migration, no PRAGMA write).
/// `--dry-run` writes nothing (opened read-write so a WAL database with no
/// `-shm` opens; no write statement runs). Idempotent: a second run merges 0.
///
/// REFUSES (non-zero exit, nothing written): a `--numbers` entry the map
/// does not read; a missing `--db`, `--raw-dir` or `--numbers`; a detail
/// raw `fdcDetailNutrients` cannot read; an id whose raws disagree on a
/// `--numbers` value. PRINTS: the files read and skipped, each merged id in
/// write order and the rows merged per number, the `differs` report, the
/// REVISIONS report (mapped numbers outside `--numbers` FDC publishes at
/// another value or the row lacks — never applied), and THE RULE ROWS WITH
/// NO RAW (the prep53 design's L57 rule: every Foundation row, and every SR
/// Legacy or Survey (FNDDS) row lacking '269' or '291', with no raw).
library;

import 'dart:convert';
import 'dart:io';

import 'package:salt_server/src/nutrition/fdc_provider.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) => exitCode = run(args);

int run(List<String> args) {
  String? dbPath;
  final rawDirs = <String>[];
  List<String>? numbers;
  var dryRun = false;
  final it = args.iterator;
  String next() => it.moveNext() ? it.current : '';
  while (it.moveNext()) {
    final arg = it.current;
    switch (arg) {
      case '--db':
        dbPath = next();
      case '--raw-dir':
        rawDirs.add(next());
      case '--numbers':
        numbers = next().split(',').where((n) => n.isNotEmpty).toList();
      case '--dry-run':
        dryRun = true;
      default:
        stderr.writeln('unknown argument: $arg');
        return 64;
    }
  }
  if (dbPath == null || dbPath.isEmpty || rawDirs.isEmpty) {
    stderr.writeln(
      'usage: --db <db> --raw-dir <dir> [--raw-dir <dir> …] '
      '--numbers <n>[,<n>…] [--dry-run]',
    );
    return 64;
  }
  if (numbers == null || numbers.isEmpty) {
    stderr.writeln('refused: no --numbers');
    return 64;
  }
  final unread = [
    for (final n in numbers)
      if (!nutrientByFdcNumber.containsKey(n)) n,
  ];
  if (unread.isNotEmpty) {
    stderr.writeln('refused: the map reads no ${unread.join(', ')}');
    return 64;
  }
  final wanted = numbers.toSet();

  // The raws: id → (amounts, file), every file of a dir in path order.
  final raws = <int, Map<String, double>>{};
  final rawFile = <int, String>{};
  var detailFiles = 0;
  var skipped = 0;
  final disagree = <String>[];
  for (final dir in rawDirs) {
    final files =
        Directory(dir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, dynamic> ||
          !json.containsKey('fdcId') ||
          !json.containsKey('foodNutrients')) {
        skipped++;
        continue;
      }
      detailFiles++;
      final id = (json['fdcId']! as num).toInt();
      final Map<String, double> amounts;
      try {
        amounts = fdcDetailNutrients(json, (_) => true);
      } on NutritionProviderException catch (e) {
        stderr.writeln(
          'refused: unreadable raw $id ${file.path}: ${e.message}',
        );
        return 65;
      }
      final seen = raws[id];
      if (seen == null) {
        raws[id] = amounts;
        rawFile[id] = file.path;
        continue;
      }
      for (final n in wanted) {
        if (seen[n] != amounts[n]) {
          disagree.add(
            '$id $n ${seen[n]} (${rawFile[id]}) vs ${amounts[n]} '
            '(${file.path})',
          );
        }
      }
    }
  }
  if (disagree.isNotEmpty) {
    for (final line in disagree) {
      stderr.writeln('refused: raws disagree: $line');
    }
    return 65;
  }
  stdout.writeln(
    'files read: $detailFiles detail, $skipped skipped (not a detail); '
    'distinct ids ${raws.length}, repeats ${detailFiles - raws.length}',
  );

  // Read-write under --dry-run too: a read-only open of a WAL database with
  // no -shm beside it (the live one after a clean stop) fails with
  // SQLITE_CANTOPEN (closer round 1, D1). The dry run writes nothing because
  // no write statement runs (`!dryRun` below).
  final db = sqlite3.open(dbPath, mode: OpenMode.readWrite);
  try {
    final mapped = nutrientByFdcNumber.keys.toSet();
    final updates = <(int, String)>[];
    final perNumber = {for (final n in numbers) n: 0};
    final differs = <String>[];
    final revisions = <String>[];
    var revisedRows = 0;
    final noRaw = <String>[];
    String line(int id, String type, NumberDiff d) =>
        '$id $type ${d.number} cached ${d.cached ?? '-'} '
        'published ${d.published}';
    for (final row in db.select(
      'SELECT fdc_id, response FROM fdc_food_cache ORDER BY fdc_id',
    )) {
      final id = row['fdc_id'] as int;
      final food = FdcFood.fromJson(
        jsonDecode(row['response'] as String) as Map<String, dynamic>,
      );
      final published = raws[id];
      if (published == null) {
        final has = food.nutrientsPer100g.containsKey;
        if (food.dataType == 'Foundation' ||
            ((food.dataType == 'SR Legacy' ||
                    food.dataType == 'Survey (FNDDS)') &&
                (!has('269') || !has('291')))) {
          noRaw.add('$id ${food.dataType} ${food.description}');
        }
        continue;
      }
      final merge = mergeNumbers(food, published, wanted, mapped: mapped);
      differs.addAll([
        for (final d in merge.differs) line(id, food.dataType, d),
      ]);
      if (merge.revisions.isNotEmpty) {
        revisedRows++;
        revisions.addAll([
          for (final d in merge.revisions) line(id, food.dataType, d),
        ]);
      }
      if (merge.merged.isNotEmpty) {
        updates.add((id, jsonEncode(merge.food.toJson())));
        for (final n in merge.merged) {
          perNumber[n] = perNumber[n]! + 1;
        }
        stdout.writeln('merged $id ${merge.merged.join(',')}');
      }
    }
    if (!dryRun && updates.isNotEmpty) {
      final update = db.prepare(
        'UPDATE fdc_food_cache SET response = ? WHERE fdc_id = ?',
      );
      db.execute('BEGIN');
      for (final (id, response) in updates) {
        update.execute([response, id]);
      }
      db.execute('COMMIT');
      update.dispose();
    }
    stdout.writeln(
      'rows merged: ${updates.length}'
      '${dryRun ? ' (dry run: nothing written)' : ''}',
    );
    for (final n in numbers) {
      stdout.writeln('  $n: ${perNumber[n]}');
    }
    stdout.writeln('differs: ${differs.length}');
    for (final l in differs) {
      stdout.writeln('differs $l');
    }
    stdout.writeln('revisions: $revisedRows rows, ${revisions.length} values');
    for (final l in revisions) {
      stdout.writeln('revision $l');
    }
    stdout.writeln('rule rows with no raw: ${noRaw.length}');
    for (final l in noRaw) {
      stdout.writeln('no raw $l');
    }
  } finally {
    db.dispose();
  }
  return 0;
}
