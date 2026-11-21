// Matcher v123 (batch PB1, prep53 — Total Sugars from Foundation records;
// matcherVersion 108 → 109). FDC's Foundation records publish Total Sugars
// as 269.3 (L56 / L57's raw details: 75 of 209 Foundation, 0 of 88 SR
// Legacy), `sugars` read 269 alone and the provider kept only the numbers
// the map reads, so the label read no sugars from a record holding 269.3
// and no 269. Here: the provider's detail parse as one function
// (`fdcDetailNutrients`), the pure merge beside `FdcFood` (`mergeNumbers`)
// and its offline tool (`tool/fdc_merge_numbers.dart`, run as a subprocess),
// and the map ['269', '269.3'] on whole corpus recipes over the recorded
// real FDC answers (FixtureProvider; the 43 foods.json Foundation entries
// the merge gave 269.3 re-recorded `--from-db` the widened snapshot 33 with
// `--replace`, each the old entry plus exactly its raw's 269.3). The raws
// are verbatim copies of L56 / L57's archive (test/fixtures/fdc_raw).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dart_frog/dart_frog.dart' as frog;
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/fdc_provider.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/v1/recipes/[id]/nutrition/index.dart' as nutrition_route;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _pancakes = '0747-100-percent-whole-wheat-pancakes.yaml';
const _apples = '0953-best-baked-apples.yaml';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// A committed raw detail (L56 / L57's archive, verbatim).
Map<String, dynamic> _raw(String id) => _json('test/fixtures/fdc_raw/$id.json');

/// The recorded `foods.json` entry of [id] (decoded afresh each call).
Map<String, dynamic> _entry(String id) =>
    (_json('test/fixtures/fdc/foods.json')[id]! as Map).cast();

/// [id]'s entry without the 269.3 the merge gave it: snapshot 33's cached
/// row, byte for byte — asserted once on a snapshot-33 copy for every id
/// this file seeds or reads so (790646 2747661 746771 2346392 1104647 323294
/// 172241 168152 173430 2705393 1750342 1750340 746784 748967: `jsonEncode`
/// of the entry less '269.3' == the row's `response`, 14 BYTE-EQUAL).
Map<String, dynamic> _unmerged(String id) =>
    _entry(id)
      ..['nutrients'] = (Map<String, dynamic>.of(
        _entry(id)['nutrients'] as Map<String, dynamic>,
      )..remove('269.3'));

FdcFood _food(Map<String, dynamic> json) => FdcFood.fromJson(json);

Set<String> get _mapped => nutrientByFdcNumber.keys.toSet();

/// Every number a raw publishes (the tool's parse).
Map<String, double> _published(String id) =>
    fdcDetailNutrients(_raw(id), (_) => true);

void main() {
  group('R1 fdcDetailNutrients — the provider parse, moved verbatim', () {
    Future<FdcFood?> served(int id, String body) => HttpOverrides.runZoned(
      () => UsdaFdcProvider(apiKey: () => 'fixture-key-not-real').food(id),
      createHttpClient: (_) => _FakeClient((method, uri, _) => (200, body)),
    );

    test('the provider over the committed raw 790646 (byte for byte) equals '
        'the replaced foods.json entry: 13 numbers, 269.3 = 5.82, NOT 293 '
        '(2.71), and its 2 portions', () async {
      final body = File('test/fixtures/fdc_raw/790646.json').readAsStringSync();
      expect(_published('790646')['293'], 2.71, reason: 'the raw carries 293');
      final food = (await served(790646, body))!;
      final entry = _food(_entry('790646'));
      expect(food.nutrientsPer100g, entry.nutrientsPer100g);
      expect(food.nutrientsPer100g.length, 13);
      expect(food.nutrientsPer100g['269.3'], 5.82);
      expect(food.nutrientsPer100g.containsKey('293'), isFalse);
      expect(food.nutrientsPer100g['291'], 1.9, reason: "onions' fiber");
      expect(
        [for (final p in food.portions) p.toJson()],
        [for (final p in entry.portions) p.toJson()],
      );
      expect(food.portions, hasLength(2));
      expect(food.dataType, 'Foundation');
    });

    test('garlic 1104647: entries with no amount are skipped — exactly the '
        '6 numbers of its foods.json entry, its 1 portion', () async {
      final raw = _raw('1104647');
      expect(
        (raw['foodNutrients'] as List).where(
          (e) => (e as Map)['amount'] == null,
        ),
        isNotEmpty,
        reason: 'the raw holds amount-less entries',
      );
      // Its four amount-less entries are FDC's group headers (951
      // Proximates, 956 Carbohydrates, 300 Minerals, 952 Vitamins and Other
      // Components): read with every number kept (the tool's parse), the
      // raw gives its 11 entries that carry an amount, never a header.
      final all = fdcDetailNutrients(raw, (_) => true);
      expect(all, hasLength(11));
      expect(all.keys, isNot(anyOf(contains('951'), contains('956'))));
      expect(all.keys, isNot(anyOf(contains('300'), contains('952'))));
      final food = (await served(
        1104647,
        File('test/fixtures/fdc_raw/1104647.json').readAsStringSync(),
      ))!;
      final entry = _food(_entry('1104647'));
      expect(food.nutrientsPer100g, entry.nutrientsPer100g);
      expect(food.nutrientsPer100g.keys.toSet(), {
        '203',
        '204',
        '205',
        '208',
        '291',
        '401',
      });
      expect(
        [for (final p in food.portions) p.toJson()],
        [for (final p in entry.portions) p.toJson()],
      );
      expect(food.portions, hasLength(1));
    });

    test('a repeated number keeps its LAST value (the shipped loop, RULED: '
        'it drops a value)', () {
      // SYNTHESIZED (the testing rule's exception: no raw on disk repeats a
      // MAPPED number — the nearest real record, 1999629 "Mushrooms, white
      // button" (22 v122 rows), repeats only the unmapped '' seven times in
      // live57_raw/raw_1999629.json): raw 790646 with a second '269.3'.
      final raw = _raw('790646');
      (raw['foodNutrients'] as List).add({
        'nutrient': {'number': '269.3', 'name': 'Sugars, Total'},
        'amount': 7.5,
      });
      expect(fdcDetailNutrients(raw, nutrientByFdcNumber.containsKey), {
        ..._entry('790646')['nutrients'] as Map,
        '269.3': 7.5,
      });
    });

    test("a foodNutrients entry that is no object is the food's unreadable "
        'answer (FOOD)', () {
      // SYNTHESIZED negative path (malformed input the corpus cannot give).
      final raw = _raw('790646');
      (raw['foodNutrients'] as List).add('not an object');
      expect(
        () => fdcDetailNutrients(raw, (_) => true),
        throwsA(
          isA<NutritionProviderException>().having(
            (e) => e.scope,
            'scope',
            FailureScope.food,
          ),
        ),
      );
    });
  });

  group('R2 (a) mergeNumbers — pure, beside FdcFood', () {
    test("onions 790646: snapshot 33's row + raw 790646 with {269.3} is the "
        'replaced foods.json entry, toJson byte-equal; merged [269.3]; '
        'nothing reported', () {
      final r = mergeNumbers(
        _food(_unmerged('790646')),
        _published('790646'),
        {'269.3'},
        mapped: _mapped,
      );
      expect(jsonEncode(r.food.toJson()), jsonEncode(_entry('790646')));
      expect(r.merged, ['269.3']);
      expect(r.food.nutrientsPer100g['269.3'], 5.82);
      expect(r.differs, isEmpty);
      expect(r.revisions, isEmpty);
      // The unmapped 293 (2.71) the raw carries is never added.
      expect(_published('790646')['293'], 2.71);
      expect(r.food.nutrientsPer100g.containsKey('293'), isFalse);
      // Idempotent: the same call on its own result merges nothing.
      final again = mergeNumbers(
        r.food,
        _published('790646'),
        {'269.3'},
        mapped: _mapped,
      );
      expect(again.merged, isEmpty);
      expect(jsonEncode(again.food.toJson()), jsonEncode(_entry('790646')));
    });

    test('garlic 1104647 publishes no 269.3: merges nothing', () {
      final r = mergeNumbers(
        _food(_unmerged('1104647')),
        _published('1104647'),
        {'269.3'},
        mapped: _mapped,
      );
      expect(r.merged, isEmpty);
      expect(jsonEncode(r.food.toJson()), jsonEncode(_entry('1104647')));
    });

    test('2747661 gains 269.3 (2.703) alone; the MAPPED 430 (19.7) its row '
        'lacks is a REVISION, never added', () {
      final r = mergeNumbers(
        _food(_unmerged('2747661')),
        _published('2747661'),
        {'269.3'},
        mapped: _mapped,
      );
      expect(r.merged, ['269.3']);
      expect(r.food.nutrientsPer100g['269.3'], 2.703);
      expect(r.food.nutrientsPer100g.containsKey('430'), isFalse);
      expect(jsonEncode(r.food.toJson()), jsonEncode(_entry('2747661')));
      expect(r.revisions, [(number: '430', cached: null, published: 19.7)]);
      // The owner gate (2026-11-20): two numbers the row lacks are appended
      // in [numbers]' order — the row then holds 430, so no revision.
      final both = mergeNumbers(
        _food(_unmerged('2747661')),
        _published('2747661'),
        {'430', '269.3'},
        mapped: _mapped,
      );
      expect(both.merged, ['430', '269.3']);
      final keys = both.food.nutrientsPer100g.keys.toList();
      expect(keys.sublist(keys.length - 2), ['430', '269.3']);
      expect(both.food.nutrientsPer100g['430'], 19.7);
      expect(both.food.nutrientsPer100g['269.3'], 2.703);
      expect(both.revisions, isEmpty);
    });

    test('oranges 746771: the raw prints 3 portions, the row none — the '
        'merged food keeps none', () {
      expect(_raw('746771')['foodPortions'], hasLength(3));
      final r = mergeNumbers(
        _food(_unmerged('746771')),
        _published('746771'),
        {'269.3'},
        mapped: _mapped,
      );
      expect(r.food.portions, isEmpty);
      expect(jsonEncode(r.food.toJson()), jsonEncode(_entry('746771')));
    });

    test("pine nuts 2346392, FDC's own revision: with {204} the cached 61.3 "
        'is kept and REPORTED against 61.27; with {269.3} the 12 revised '
        'values are listed', () {
      final cached = _food(_entry('2346392'));
      final fat = mergeNumbers(
        cached,
        _published('2346392'),
        {'204'},
        mapped: _mapped,
      );
      expect(fat.merged, isEmpty);
      expect(fat.food.nutrientsPer100g['204'], 61.3);
      expect(jsonEncode(fat.food.toJson()), jsonEncode(_entry('2346392')));
      expect(fat.differs, [(number: '204', cached: 61.3, published: 61.27)]);
      expect(fat.revisions.map((d) => d.number), isNot(contains('204')));
      final sugars = mergeNumbers(
        cached,
        _published('2346392'),
        {'269.3'},
        mapped: _mapped,
      );
      expect(sugars.merged, isEmpty);
      expect(sugars.differs, isEmpty);
      expect(
        {for (final d in sugars.revisions) d.number: d},
        {
          '958': (number: '958', cached: 643.0, published: 642.99228),
          '957': (number: '957', cached: 689.0, published: 688.614),
          '204': (number: '204', cached: 61.3, published: 61.27),
          '205': (number: '205', cached: 18.6, published: 18.5921),
          '291': (number: '291', cached: 3.94, published: 3.941),
          '203': (number: '203', cached: 15.7, published: 15.7039),
          '301': (number: '301', cached: 8.74, published: 8.736),
          '306': (number: '306', cached: 655.0, published: 654.8),
          '404': (number: '404', cached: 0.625, published: 0.6253),
          '406': (number: '406', cached: 4.47, published: 4.466),
          '415': (number: '415', cached: 0.255, published: 0.2546),
          '304': (number: '304', cached: 206.0, published: 205.9),
        },
      );
      expect(sugars.revisions, hasLength(12));
    });
  });

  group('R2 (b) tool/fdc_merge_numbers.dart — a thin loop, run as a '
      'subprocess', () {
    late Directory temp;
    late String raws;
    late String packages;
    var seeds = 0;
    // The seeded rows, in the raws' FILE-NAME order for the three that merge
    // (2747661.json, 746771.json, 790646.json sort so; their ids ascend
    // 746771, 790646, 2747661) — the tool writes in fdc_id order, never in
    // the order it meets them.
    const seeded = [
      2747661, 746771, 790646, // Foundation, a raw with 269.3: merged
      2346392, // Foundation, a raw with no 269.3: its revisions reported
      323294, // Foundation, no raw: a rule row with no raw
      172241, // SR Legacy "Vinegar, balsamic": 269 and no 291, no raw
      168152, // SR Legacy "Jujube, Chinese, fresh, dried": 291, no 269
      173430, // SR Legacy "Butter, without salt": both 269 and 291
      2705393, // Survey (FNDDS) — SYNTHESIZED without its 291 (below)
    ];

    setUpAll(() async {
      packages = (await Isolate.packageConfig)!.toFilePath();
      temp = Directory.systemTemp.createTempSync('salt-v123-tool-');
      raws = '${temp.path}/raws';
      Directory(raws).createSync();
      for (final f in Directory('test/fixtures/fdc_raw').listSync()) {
        (f as File).copySync('$raws/${f.uri.pathSegments.last}');
      }
      // A real JSON that is no FDC detail (a contract golden): skipped.
      File(
        '../../packages/salt_shared/test/fixtures/contract/'
        'nutrition_served_with.json',
      ).copySync('$raws/not_a_detail.json');
      // A real file that is no `.json` (the contract fixtures' README): the
      // tool reads `*.json` alone — neither parsed nor counted (the owner
      // gate, hand-edit verifier round 1: the filter dropped survived).
      File(
        '../../packages/salt_shared/test/fixtures/contract/README.md',
      ).copySync('$raws/README.md');
      // SYNTHESIZED (the testing rule's exception: no file on disk holds
      // exactly one of the two keys — the nearest real inputs are the 10 FDC
      // SEARCH answers in the archives, live61_raw ×7, live62_raw ×1,
      // 2026-11-16/live55_raw ×2, which hold neither): one key alone each,
      // skipped and counted, never parsed or refused.
      File(
        '$raws/only_fdcid.json',
      ).writeAsStringSync(jsonEncode({'fdcId': 790646}));
      File('$raws/only_foodnutrients.json').writeAsStringSync(
        jsonEncode({'foodNutrients': _raw('790646')['foodNutrients']}),
      );
    });

    tearDownAll(() => temp.deleteSync(recursive: true));

    /// A fresh database holding [seeded]'s snapshot-33 rows.
    String seed() {
      final path = '${temp.path}/cache${seeds++}.db';
      final db = sqlite3.open(path)
        ..execute(
          'CREATE TABLE fdc_food_cache (fdc_id INTEGER PRIMARY KEY, '
          'response TEXT NOT NULL, fetched_at TEXT NOT NULL '
          "DEFAULT (datetime('now')))",
        );
      for (final id in seeded) {
        final row = _unmerged('$id');
        if (id == 2705393) {
          // SYNTHESIZED: no cached Survey (FNDDS) row lacks 269 or 291 (all
          // 382 on snapshot 33 hold both) — the nearest real record,
          // 2705393 "Buttermilk" (50 v122 rows), less its 291.
          (row['nutrients'] as Map).remove('291');
        }
        db.execute(
          'INSERT INTO fdc_food_cache (fdc_id, response, fetched_at) '
          'VALUES (?, ?, ?)',
          [id, jsonEncode(row), '2026-09-26 19:29:0${id % 10}'],
        );
      }
      db.dispose();
      return path;
    }

    Map<int, (String, String)> rowsOf(String path) {
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        return {
          for (final r in db.select(
            'SELECT fdc_id, response, fetched_at FROM fdc_food_cache',
          ))
            r['fdc_id'] as int: (
              r['response'] as String,
              r['fetched_at'] as String,
            ),
        };
      } finally {
        db.dispose();
      }
    }

    Future<ProcessResult> tool(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['--packages=$packages', 'tool/fdc_merge_numbers.dart', ...args],
    );

    Future<void> refused(List<String> args, String db, Object stderr) async {
      final before = File(db).readAsBytesSync();
      final run = await tool(args);
      expect(run.exitCode, isNot(0), reason: '${run.stdout}');
      expect(run.stderr, stderr);
      expect(File(db).readAsBytesSync(), before);
    }

    test('refusals: a number the map does not read (293), no --numbers, no '
        '--db, no --raw-dir, an unknown argument — non-zero, no byte '
        'changed', () async {
      final db = seed();
      await refused(
        ['--db', db, '--raw-dir', raws, '--numbers', '293'],
        db,
        contains('refused: the map reads no 293'),
      );
      await refused(
        ['--db', db, '--raw-dir', raws],
        db,
        contains('refused: no --numbers'),
      );
      await refused(
        ['--raw-dir', raws, '--numbers', '269.3'],
        db,
        contains('usage:'),
      );
      await refused(['--db', db, '--numbers', '269.3'], db, contains('usage:'));
      // The owner gate (hand-edit verifier round 1): an unknown argument —
      // a mistyped `--dry-run` — is refused; never a run that exits 0.
      await refused(
        ['--db', db, '--raw-dir', raws, '--numbers', '269.3', '--dryrun'],
        db,
        contains('unknown argument: --dryrun'),
      );
    });

    test('--numbers 269.3 merges exactly the seeded ids with a 269.3 raw, in '
        'ascending fdc_id order, each row the replaced foods.json entry; '
        'fetched_at kept; no INSERT; its reports; a second run merges 0 and '
        'changes no byte', () async {
      final db = seed();
      final before = rowsOf(db);
      final run = await tool([
        '--db',
        db,
        '--raw-dir',
        raws,
        '--numbers',
        '269.3',
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final out = (run.stdout as String).split('\n');
      expect(
        out.first,
        'files read: 11 detail, 3 skipped (not a detail); distinct ids 11, '
        'repeats 0',
      );
      expect(out.where((l) => l.startsWith('merged ')), [
        'merged 746771 269.3',
        'merged 790646 269.3',
        'merged 2747661 269.3',
      ]);
      expect(out, containsAllInOrder(['rows merged: 3', '  269.3: 3']));
      expect(out, contains('differs: 0'));
      expect(out, contains('revisions: 2 rows, 13 values'));
      expect(
        out,
        contains('revision 2346392 Foundation 204 cached 61.3 published 61.27'),
      );
      expect(
        out,
        contains('revision 2747661 Foundation 430 cached - published 19.7'),
      );
      expect(out.where((l) => l.startsWith('no raw ')), [
        'no raw 168152 SR Legacy Jujube, Chinese, fresh, dried',
        'no raw 172241 SR Legacy Vinegar, balsamic',
        'no raw 323294 Foundation ${_entry('323294')['description']}',
        'no raw 2705393 Survey (FNDDS) Buttermilk',
      ]);
      expect(out, contains('rule rows with no raw: 4'));
      final after = rowsOf(db);
      expect(after.keys.toSet(), before.keys.toSet(), reason: 'no INSERT');
      for (final id in seeded) {
        expect(after[id]!.$2, before[id]!.$2, reason: 'fetched_at $id');
        expect(
          after[id]!.$1,
          {746771, 790646, 2747661}.contains(id)
              ? jsonEncode(_entry('$id'))
              : before[id]!.$1,
          reason: '$id',
        );
      }
      final merged = File(db).readAsBytesSync();
      final again = await tool([
        '--db',
        db,
        '--raw-dir',
        raws,
        '--numbers',
        '269.3',
      ]);
      expect(again.exitCode, 0);
      expect(again.stdout, contains('rows merged: 0\n'));
      expect(File(db).readAsBytesSync(), merged);
    });

    test('--dry-run reports the same merge and changes no byte', () async {
      final db = seed();
      final before = File(db).readAsBytesSync();
      final run = await tool([
        '--db', db, '--raw-dir', raws, '--numbers', '269.3', '--dry-run', //
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(run.stdout, contains('rows merged: 3 (dry run: nothing written)'));
      expect(File(db).readAsBytesSync(), before);
    });

    test('--dry-run on a WAL database with no -wal / -shm beside it (the '
        'live database after a clean stop, deploy step 4) runs: exit 0, the '
        'same report, no byte of the database changed', () async {
      // Closer round 1, D1: a read-only open of such a file failed with
      // SQLITE_CANTOPEN at the first SELECT. The seeded rows are the
      // snapshot-33 rows; only the journal mode differs from the test above.
      final db = seed();
      final plain = await tool([
        '--db', db, '--raw-dir', raws, '--numbers', '269.3', '--dry-run', //
      ]);
      sqlite3.open(db)
        ..execute('PRAGMA journal_mode=WAL')
        ..dispose();
      for (final side in ['$db-wal', '$db-shm']) {
        final f = File(side);
        if (f.existsSync()) {
          expect(f.lengthSync(), side.endsWith('-wal') ? 0 : isNonNegative);
          f.deleteSync();
        }
      }
      final before = File(db).readAsBytesSync();
      expect(before.sublist(18, 20), [2, 2], reason: 'WAL in the header');
      final run = await tool([
        '--db', db, '--raw-dir', raws, '--numbers', '269.3', '--dry-run', //
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(run.stdout, plain.stdout);
      expect(run.stdout, contains('rows merged: 3 (dry run: nothing written)'));
      expect(File(db).readAsBytesSync(), before);
    });

    test('an unreadable detail raw refuses the WHOLE run: the id and file '
        'printed, no byte changed', () async {
      // SYNTHESIZED negative path (the testing rule's exception: malformed
      // input no FDC answer on disk gives): raw 790646 with a foodNutrients
      // entry that is no object, beside the real raws.
      final dir = Directory('${temp.path}/unreadable')..createSync();
      final raw = _raw('790646');
      (raw['foodNutrients'] as List).add('not an object');
      File('${dir.path}/zz_790646.json').writeAsStringSync(jsonEncode(raw));
      final db = seed();
      await refused(
        [
          '--db',
          db,
          '--raw-dir',
          raws,
          '--raw-dir',
          dir.path,
          '--numbers',
          '269.3',
        ],
        db,
        allOf(
          contains('refused: unreadable raw 790646'),
          contains('zz_790646.json'),
        ),
      );
    });

    test('raws that disagree on a --numbers value refuse the run, the id '
        'printed, no byte changed', () async {
      // SYNTHESIZED negative path: raw 790646 with its 269.3 altered (5.82 →
      // 6.0), beside the real one.
      final dir = Directory('${temp.path}/disagree')..createSync();
      final raw = _raw('790646');
      for (final e
          in (raw['foodNutrients'] as List).cast<Map<String, dynamic>>()) {
        if ((e['nutrient'] as Map?)?['number'] == '269.3') {
          e['amount'] = 6.0;
        }
      }
      File('${dir.path}/790646.json').writeAsStringSync(jsonEncode(raw));
      final db = seed();
      await refused(
        [
          '--db',
          db,
          '--raw-dir',
          raws,
          '--raw-dir',
          dir.path,
          '--numbers',
          '269.3',
        ],
        db,
        contains('refused: raws disagree: 790646 269.3 5.82'),
      );
      // The owner gate (2026-11-20): the refusal is scoped to --numbers.
      // SYNTHESIZED (no two raws on disk disagree on ANY number — the
      // archives' 11 repeats, measured): raw 790646 with a number OUTSIDE
      // --numbers altered (291, 1.9 → 2.0), beside the real one, is a
      // repeat like any other — the run merges its three rows.
      final other = Directory('${temp.path}/revised')..createSync();
      final revised = _raw('790646');
      for (final e
          in (revised['foodNutrients'] as List).cast<Map<String, dynamic>>()) {
        if ((e['nutrient'] as Map?)?['number'] == '291') {
          e['amount'] = 2.0;
        }
      }
      expect(fdcDetailNutrients(revised, (_) => true)['291'], 2.0);
      File('${other.path}/790646.json').writeAsStringSync(jsonEncode(revised));
      final run = await tool([
        '--db', seed(), '--raw-dir', raws, '--raw-dir', other.path, //
        '--numbers', '269.3',
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(
        (run.stdout as String).split('\n').first,
        'files read: 12 detail, 3 skipped (not a detail); distinct ids 11, '
        'repeats 1',
      );
      expect(run.stdout, contains('rows merged: 3\n'));
    });
  });

  group(
    'R3 the map: sugars [269, 269.3] on whole corpus recipes',
    skip: skipIfNoCorpus,
    () {
      // Two databases, one tree: UNWIDENED holds the details snapshot 33
      // holds (every foods.json entry less its merged 269.3 — byte-equal to
      // the snapshot's rows, asserted above) and WIDENED the replaced entries.
      // The tip on an unwidened cache reads what the base tree read (the
      // whole-library replay G3: no totals key moves on snapshot 33).
      const records = [
        790085,
        746784,
        172804,
        175040,
        173468,
        2705393,
        2710180,
        748967, // pancakes
        1750342, 173430, 2709202, 2346395, 168833, 2346396, 169103, 171320,
        169661, 2709319, // apples (173468 above)
      ];
      late Directory temp;
      final dbs = <String, SaltDatabase>{};
      final recipes = <String, Recipe>{};

      setUpAll(() async {
        temp = Directory.systemTemp.createTempSync('salt-v123-');
        for (final side in ['unwidened', 'widened']) {
          final config = ServerConfig(
            dataDir: '${temp.path}/$side',
            logLevel: Level.WARNING,
            trustProxy: false,
          );
          Directory(config.dataDir).createSync();
          final db = dbs[side] = SaltDatabase.open(config.dbPath)
            ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
          for (final id in records) {
            db.fdcFoodCachePut(
              id,
              jsonEncode(side == 'widened' ? _entry('$id') : _unmerged('$id')),
            );
          }
          final fixture = FixtureProvider(pending: pendingSearches);
          final provider = side == 'widened' ? fixture : _Unwidened(fixture);
          for (final file in [_pancakes, _apples]) {
            final host = loadCorpusRecipe(file);
            db.upsertRecipe(host, sourceSlug: _source, contentHash: host.id);
            final stored = db.recipeByIdOrSlug(host.id)!.recipe;
            expect(await matchAndCompute(db, provider, stored), isNull);
            recipes[file] = db.recipeByIdOrSlug(host.id)!.recipe;
          }
        }
      });

      tearDownAll(() {
        for (final db in dbs.values) {
          db.dispose();
        }
        temp.deleteSync(recursive: true);
      });

      List<Object?> rowsOf(String side, String file) => [
        for (final r in dbs[side]!.ingredientMatchesFor(recipes[file]!.id))
          (
            r.position,
            r.fdcId,
            r.grams,
            r.status,
            r.hold,
            r.parts,
            r.confidence,
          ),
      ];
      Map<String, dynamic> totalsOf(String side, String file) =>
          jsonDecode(dbs[side]!.nutritionFor(recipes[file]!.id)!.totalsJson!)
              as Map<String, dynamic>;
      double gramsAt(String file, int position) => dbs['widened']!
          .ingredientMatchesFor(recipes[file]!.id)
          .singleWhere((r) => r.position == position)
          .grams!;

      test('every row and every totals key but sugars byte-equal on the two '
          'caches; energy unmoved', () {
        for (final file in [_pancakes, _apples]) {
          expect(
            rowsOf('widened', file),
            rowsOf('unwidened', file),
            reason: file,
          );
          final a = totalsOf('unwidened', file);
          final b = totalsOf('widened', file);
          expect(b.keys.toSet(), a.keys.toSet(), reason: file);
          for (final key in a.keys) {
            if (key != 'sugars') {
              expect(b[key], a[key], reason: '$file $key');
            }
          }
          expect(b['energy'], a['energy'], reason: file);
        }
      });

      test('A SUGAR LINE: 100-percent-whole-wheat-pancakes|1 "2 tablespoons '
          'sugar" on 746784 "Sugars, granulated" (269.3 = 99.8) and |7 "2 '
          'large eggs" on 748967 "Eggs, Grade A, Large, egg whole" (0.2): '
          'sugars moves by exactly grams x 99.8 / 100 + grams x 0.2 / 100', () {
        final sugar = gramsAt(_pancakes, 1);
        final eggs = gramsAt(_pancakes, 7);
        // The fixture compute's grams (the v122 rows print 24.81 and 100.00).
        expect(sugar, 24.805896378514547);
        expect(eggs, 100.0);
        expect(_entry('746784')['nutrients'], containsPair('269.3', 99.8));
        expect(_entry('748967')['nutrients'], containsPair('269.3', 0.2));
        final a = totalsOf('unwidened', _pancakes)['sugars'] as double;
        final b = totalsOf('widened', _pancakes)['sugars'] as double;
        // By hand: 24.805896378514547 x 0.998 + 100 x 0.002 = 24.956284585758.
        expect(b - a, closeTo(sugar * 99.8 / 100 + eggs * 0.2 / 100, 1e-9));
        expect(b - a, closeTo(24.956284585758, 1e-9));
        expect(a, closeTo(29.4264, 1e-9));
        expect(b, closeTo(54.382684585758, 1e-9));
      });

      test('THE ORDER: best-baked-apples|0 on 1750342 "Apples, granny smith, '
          'with skin, raw", which publishes BOTH 269 (10.65) and 269.3 '
          '(10.651), counts 269: 928.72962 g x 10.65 / 100 = 98.909704 g, '
          "not 98.918992; the recipe's sugars unmoved", () {
        expect(
          _entry('1750342')['nutrients'],
          allOf(containsPair('269', 10.65), containsPair('269.3', 10.651)),
        );
        expect(gramsAt(_apples, 0), 928.72962);
        final a = totalsOf('unwidened', _apples)['sugars'] as double;
        final b = totalsOf('widened', _apples)['sugars'] as double;
        expect(b, a);
        expect(b, closeTo(259.715126337141, 1e-9));
        // The other rows' share: 259.715126337 - 98.909704530.
        expect(b - 928.72962 * 10.65 / 100, closeTo(160.805421807, 1e-8));
      });

      test("onions 790646's fiber stays 1.9 (291); 293's 2.71 is never read; "
          'the three defs as ruled (OQ1, OQ3)', () async {
        final onions = (await FixtureProvider().food(790646))!;
        expect(onions.nutrientsPer100g['291'], 1.9);
        expect(onions.nutrientsPer100g.containsKey('293'), isFalse);
        NutrientDef def(String key) =>
            nutrientDefs.singleWhere((d) => d.key == key);
        expect(def('fiber').fdcNumbers, ['291']);
        expect(def('sugars').fdcNumbers, ['269', '269.3']);
        expect(def('sugars_added').fdcNumbers, ['539']);
        expect(nutrientByFdcNumber, hasLength(34));
      });

      test(
        "A2: the nutrition GET, through the route, prints the pancakes' "
        'per-serving sugars at the hand figure / its serving basis',
        () async {
          final db = dbs['widened']!;
          final basis = db.nutritionFor(recipes[_pancakes]!.id)!.servingBasis!;
          expect(basis, 15);
          final adminId = db.createUser(
            username: 'admin',
            passwordHash: 'unused',
            role: 'admin',
          );
          final pipeline =
              ((frog.RequestContext context) => nutrition_route.onRequest(
                    context,
                    recipes[_pancakes]!.id,
                  ))
                  .use(
                    frog.provider<AuthUser?>(
                      (_) => AuthUser(
                        id: adminId,
                        username: 'admin',
                        role: 'admin',
                        mustChangePassword: false,
                        scope: 'full',
                        via: 'session',
                      ),
                    ),
                  )
                  .use(frog.provider<SaltDatabase>((_) => db))
                  .use(errorHandler())
                  .use(requestIdProvider());
          final server = await frog.serve(
            pipeline,
            InternetAddress.loopbackIPv4,
            0,
          );
          final client = HttpClient();
          try {
            final request = await client.open(
              'GET',
              '127.0.0.1',
              server.port,
              '/',
            );
            final response = await request.close();
            final body =
                jsonDecode(await utf8.decoder.bind(response).join())
                    as Map<String, dynamic>;
            expect(response.statusCode, 200);
            final perServing = body['per_serving'] as Map<String, dynamic>;
            // 54.382684585758 / 15 = 3.6255 -> 3.63 (unwidened: 29.4264 / 15
            // -> 1.96).
            expect((perServing['sugars'] as Map)['amount'], 3.63);
          } finally {
            client.close();
            await server.close(force: true);
          }
        },
      );
    },
  );
}

/// The provider as the base tree's caches saw it: every food without the
/// 269.3 `tool/fdc_merge_numbers.dart` merged (snapshot 33's rows).
class _Unwidened implements NutritionProvider {
  _Unwidened(this.inner);

  final NutritionProvider inner;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async {
    final food = await inner.food(fdcId);
    return food == null ? null : _food(_unmerged('$fdcId'));
  }
}

// The fake HTTP client of fdc_request_tally_test.dart: the response bodies
// are recorded FDC payloads, served byte for byte.
class _FakeClient implements HttpClient {
  _FakeClient(this.respond);

  final (int, String) Function(String method, Uri uri, String body) respond;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _FakeRequest('POST', url, respond);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeRequest('GET', url, respond);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._method, this._uri, this._respond);

  final String _method;
  final Uri _uri;
  final (int, String) Function(String, Uri, String) _respond;
  final StringBuffer _body = StringBuffer();

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  void write(Object? object) => _body.write(object);

  @override
  Future<HttpClientResponse> close() async {
    final (status, text) = _respond(_method, _uri, _body.toString());
    return _FakeResponse(status, text);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, this._text);

  @override
  final int statusCode;
  final String _text;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(_text)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
