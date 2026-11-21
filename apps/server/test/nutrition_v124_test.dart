// Matcher v124 (batch PB2a, prep53 — a negative published amount reads as 0;
// the cached details carry their own saturated and trans fat; matcherVersion
// 109 → 110). PART N: `recomputeTotals`'s `add` adds `max(per100, 0)` for
// every def — FDC publishes carbohydrate by difference (205) below zero on
// seven Foundation meat records, three of them foods.json entries (2727569
// "Chicken, breast, meat and skin, raw" −0.42825, 2727567 thigh −0.17255,
// 2727568 wing −0.45875), and the key stays (at 0.0 where nothing else
// adds). PART M is data: PB1's tool merged each cached detail's OWN 606 /
// 605 (`--numbers 606,605`), and the four foods.json entries it widened
// (2710824 2747667 2758998 2759000) were re-recorded `--from-db` the widened
// snapshot with `--replace` — each the old entry plus exactly [606, 605].
// Real corpus recipes over the recorded real FDC answers (FixtureProvider);
// every figure is derived here by hand from the rows' own grams and the
// records' own values.

import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' as frog;
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/middleware/error_handler.dart';
import 'package:salt_server/src/middleware/request_context.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/nutrients.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import '../routes/api/v1/recipes/[id]/nutrition/index.dart' as nutrition_route;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _breasts = '0120-roasted-bone-in-chicken-breasts.yaml';
const _thighs = '0125-oven-roasted-chicken-thighs.yaml';
const _glazed = '0627-grilled-glazed-bone-in-chicken-breasts.yaml';
const _wings = '1125-roasted-and-glazed-chicken-wings.yaml';
const _marbella = '0124-chicken-marbella.yaml';
const _guacamole = '0472-chunky-guacamole.yaml';
const _nachos = '0471-cheesy-nachos-with-guacamole-and-salsa.yaml';
const _scallops = '0277-pan-seared-scallops.yaml';

/// The records the replay's rows of these recipes read that are foods.json
/// entries (G2's rows_main.tsv): seeded as the snapshot holds them, so a
/// line reads the cached detail as the replay does, never a trimmed hit.
const _nRecords = [
  173468, 2710180, 2727569, 2727567, 170931, 2727568, 1104647, 167749, //
  168820, 169098, 169231, 169698, 170499, 170924, 171186, 173470, 2259793,
  2707442, 2709782, 2709794, 2710692, 746784, 170917, 170932, 171328,
  171609, 172238, 172240, 173430, 2706232, 2709211, 2709796, 2710089,
  2710186, 2710689, 748608,
];
const _mRecords = [
  1104647, 168156, 169997, 170923, 2710824, 2747661, 790646, 168155, //
  170457, 170931, 173468, 2346387, 2708202, 2709794, 790577, 173430,
  2709168, 2710180, 2747667,
];

/// The four entries the merge widened (each gained 606 then 605).
const _widened = {'2710824', '2747667', '2758998', '2759000'};

Map<String, dynamic> _entry(String id) =>
    ((jsonDecode(File('test/fixtures/fdc/foods.json').readAsStringSync())
                as Map<String, dynamic>)[id]!
            as Map)
        .cast();

/// [id]'s entry as SNAPW (the base's cache) holds it: a widened entry less
/// its 606 / 605 — `jsonEncode` BYTE-EQUAL to SNAPW's `fdc_food_cache` row
/// for the four (asserted once, out of the suite, on a SNAPW copy).
Map<String, dynamic> _unmerged(String id) {
  final entry = _entry(id);
  if (_widened.contains(id)) {
    entry['nutrients'] = Map<String, dynamic>.of(
      entry['nutrients'] as Map<String, dynamic>,
    )..removeWhere((k, _) => k == '606' || k == '605');
  }
  return entry;
}

SaltDatabase _open(Directory temp, String name) {
  final config = ServerConfig(
    dataDir: '${temp.path}/$name',
    logLevel: Level.WARNING,
    trustProxy: false,
  );
  Directory(config.dataDir).createSync();
  return SaltDatabase.open(config.dbPath)
    ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
}

/// Stores [file] and computes it (its child sections first, the bulk order).
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider provider,
  String file,
) async {
  final host = loadCorpusRecipe(file);
  db.upsertRecipe(host, sourceSlug: _source, contentHash: host.id);
  final stored = db.recipeByIdOrSlug(host.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, provider, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, provider, stored), isNull, reason: file);
  return db.recipeByIdOrSlug(host.id)!.recipe;
}

Map<String, dynamic> _totals(SaltDatabase db, Recipe recipe) =>
    jsonDecode(db.nutritionFor(recipe.id)!.totalsJson!) as Map<String, dynamic>;

void main() {
  group(
    'PART N: a negative published 205 adds 0; the key stays',
    skip: skipIfNoCorpus,
    () {
      late Directory temp;
      late SaltDatabase db;
      final provider = FixtureProvider(pending: pendingSearches);
      final recipes = <String, Recipe>{};

      setUpAll(() async {
        temp = Directory.systemTemp.createTempSync('salt-v124n-');
        db = _open(temp, 'n');
        for (final id in _nRecords) {
          db.fdcFoodCachePut(id, jsonEncode(_entry('$id')));
        }
        for (final file in [_breasts, _thighs, _glazed, _wings, _marbella]) {
          recipes[file] = await _compute(db, provider, file);
        }
      });

      tearDownAll(() {
        db.dispose();
        temp.deleteSync(recursive: true);
      });

      /// The rows `add` reads: unheld, unskipped, on a record, grams > 0, no
      /// routed child (none of these five holds parts — asserted).
      List<IngredientMatchRow> counted(String file) => [
        for (final r in db.ingredientMatchesFor(recipes[file]!.id))
          if (r.hold == null &&
              r.status != 'skipped' &&
              r.fdcId != null &&
              r.childRecipeId == null &&
              (r.grams ?? 0) > 0)
            r,
      ];

      /// The 205 the totals read for [fdcId] (`nutrientSiblings` applied).
      Future<double?> carbsOf(int fdcId) async => (await provider.food(
        nutrientSiblings[fdcId] ?? fdcId,
      ))!.nutrientsPer100g['205'];

      /// Σ counted rows' grams × max(205, 0) / 100 — the rule, by hand.
      Future<double> rule(String file) async {
        var sum = 0.0;
        for (final r in counted(file)) {
          expect(r.parts, isNull, reason: '$file|${r.position}');
          final v = await carbsOf(r.fdcId!);
          if (v != null) sum += r.grams! * (v < 0 ? 0.0 : v) / 100;
        }
        return sum;
      }

      test(
        'the three negative records are foods.json entries (FDC values)',
        () {
          expect(_entry('2727569')['nutrients'], containsPair('205', -0.42825));
          expect(_entry('2727567')['nutrients'], containsPair('205', -0.17255));
          expect(_entry('2727568')['nutrients'], containsPair('205', -0.45875));
        },
      );

      test('roasted-bone-in-chicken-breasts|0 (2727569, 923.06 g) and '
          'oven-roasted-chicken-thighs|0 (2727567, 1,111.30 g): carbs is '
          'EXACTLY 0.0 and present (was −3.953003 and −1.917549)', () {
        for (final (file, id) in [(_breasts, 2727569), (_thighs, 2727567)]) {
          final meat = counted(file).singleWhere((r) => r.position == 0);
          expect(meat.fdcId, id);
          // The rows beside the meat publish 0 g / 100 g carbs or no grams.
          final totals = _totals(db, recipes[file]!);
          expect(totals.containsKey('carbs'), isTrue, reason: file);
          expect(totals['carbs'], 0.0, reason: file);
        }
        expect(counted(_breasts)[0].grams, closeTo(923.06, 0.005));
        expect(counted(_thighs)[0].grams, closeTo(1111.30, 0.005));
      });

      test('THE KEY STAYS: grilled-glazed-bone-in-chicken-breasts — every '
          'counted row that publishes 205 is |1 on 2727569 (|0 the brine salt '
          'is 0 g), and carbs is PRESENT at exactly 0.0', () async {
        final publishing = <int>[];
        for (final r in counted(_glazed)) {
          if (await carbsOf(r.fdcId!) != null) publishing.add(r.position);
        }
        expect(publishing, [1]);
        expect(counted(_glazed).single.fdcId, 2727569);
        final totals = _totals(db, recipes[_glazed]!);
        expect(totals.containsKey('carbs'), isTrue);
        expect(totals['carbs'], 0.0);
      });

      test(
        'roasted-and-glazed-chicken-wings: the wing (2727568, −0.45875) adds '
        '0 and |3 "1 teaspoon pepper" (170931, 2.30 g) carries the total: '
        '2.30 × 63.95 / 100 = 1.47085 (was −2.690857: a sign change)',
        () async {
          final pepper = counted(_wings).singleWhere((r) => r.position == 3);
          expect(pepper.fdcId, 170931);
          expect(pepper.grams, 2.3);
          expect(await carbsOf(170931), 63.95);
          expect(counted(_wings)[0].fdcId, 2727568);
          final carbs = _totals(db, recipes[_wings]!)['carbs'] as double;
          expect(carbs, closeTo(2.3 * 63.95 / 100, 1e-9));
          expect(carbs, closeTo(1.47085, 1e-9));
        },
      );

      test('chicken-marbella|10 (2727569) after nine positive-carbs rows: the '
          'clamp is on the AMOUNT added, never on the running total', () async {
        final meat = counted(_marbella).singleWhere((r) => r.position == 10);
        expect(meat.fdcId, 2727569);
        final carbs = _totals(db, recipes[_marbella]!)['carbs'] as double;
        // The other rows' share, by hand (G2's replay: 82.056373); a clamp on
        // the running total would give this less the meat's 870.99 g ×
        // 0.42825 / 100 = 3.73 g (78.326373).
        expect(carbs, closeTo(await rule(_marbella), 1e-9));
        expect(carbs, closeTo(82.056373, 1e-6));
        expect(meat.grams! * 0.42825 / 100, closeTo(3.73, 0.005));
      });

      test(
        'AS A PROPERTY over the five: carbs == Σ counted grams × max(205, 0) '
        '/ 100 within 1e-9, and no totals value is negative',
        () async {
          for (final file in [_breasts, _thighs, _glazed, _wings, _marbella]) {
            final totals = _totals(db, recipes[file]!);
            expect(
              totals['carbs'] as double,
              closeTo(await rule(file), 1e-9),
              reason: file,
            );
            for (final MapEntry(:key, :value) in totals.entries) {
              expect(
                value as num,
                greaterThanOrEqualTo(0),
                reason: '$file $key',
              );
            }
          }
        },
      );

      test('THE CLAMP ENDS THE DEF, NEVER THE RECORD: a negative record still '
          'adds EVERY other def — on the five, each key but energy == Σ '
          'counted grams × max(first present number of the def, 0) / 100; '
          'roasted-bone-in-chicken-breasts|0 923.06 g × 21.40625 / 100 = '
          '197.59 g of protein', () async {
        for (final file in [_breasts, _thighs, _glazed, _wings, _marbella]) {
          // The model, def by def (energy apart: its Atwater arm is its own).
          final sums = <String, double>{};
          for (final r in counted(file)) {
            final food = (await provider.food(
              nutrientSiblings[r.fdcId!] ?? r.fdcId!,
            ))!;
            for (final def in nutrientDefs.skip(1)) {
              for (final number in def.fdcNumbers) {
                final v = food.nutrientsPer100g[number];
                if (v != null) {
                  sums[def.key] =
                      (sums[def.key] ?? 0) + r.grams! * (v < 0 ? 0 : v) / 100;
                  break;
                }
              }
            }
          }
          final totals = _totals(db, recipes[file]!)..remove('energy');
          expect(totals.keys.toSet(), sums.keys.toSet(), reason: file);
          for (final MapEntry(:key, :value) in sums.entries) {
            expect(
              totals[key] as double,
              closeTo(value, 1e-9),
              reason: '$file $key',
            );
          }
        }
        expect(nutrientDefs.first.key, 'energy');
        // The meat publishes six numbers read after carbs (203, 301, 303,
        // 306, 304, 305): each is in the models above. By hand, the breasts'
        // protein is the meat's alone (the salt and the oil publish 0).
        final meat = counted(_breasts).singleWhere((r) => r.position == 0);
        final protein = _totals(db, recipes[_breasts]!)['protein'] as double;
        expect(protein, closeTo(meat.grams! * 21.40625 / 100, 1e-9));
        expect(protein, closeTo(197.592471, 1e-6));
      });

      test('A2: the nutrition GET of roasted-bone-in-chicken-breasts, through '
          'the route, prints per-serving carbs 0.0 and dv_percent 0.0 (was '
          '−0.99 / −0.4)', () async {
        final id = recipes[_breasts]!.id;
        final adminId = db.createUser(
          username: 'admin',
          passwordHash: 'unused',
          role: 'admin',
        );
        final pipeline =
            ((frog.RequestContext context) =>
                    nutrition_route.onRequest(context, id))
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
          final carbs =
              (body['per_serving'] as Map<String, dynamic>)['carbs'] as Map;
          expect(carbs['amount'], 0.0);
          expect(carbs['dv_percent'], 0.0);
        } finally {
          client.close();
          await server.close(force: true);
        }
      });
    },
  );

  group(
    'PART M: the widened entries carry their own 606 / 605',
    skip: skipIfNoCorpus,
    () {
      late Directory temp;
      final dbs = <String, SaltDatabase>{};
      final recipes = <String, Map<String, Recipe>>{};

      setUpAll(() async {
        temp = Directory.systemTemp.createTempSync('salt-v124m-');
        for (final side in ['unwidened', 'widened']) {
          final db = dbs[side] = _open(temp, side);
          for (final id in _mRecords) {
            db.fdcFoodCachePut(
              id,
              jsonEncode(side == 'widened' ? _entry('$id') : _unmerged('$id')),
            );
          }
          final fixture = FixtureProvider(pending: pendingSearches);
          final provider = side == 'widened' ? fixture : _Unwidened(fixture);
          final mine = recipes[side] = {};
          // The child first: the nachos' |6 routes to chunky-guacamole.
          for (final file in [_guacamole, _nachos, _scallops]) {
            mine[file] = await _compute(db, provider, file);
          }
        }
      });

      tearDownAll(() {
        for (final db in dbs.values) {
          db.dispose();
        }
        temp.deleteSync(recursive: true);
      });

      Map<String, dynamic> totals(String side, String file) =>
          _totals(dbs[side]!, recipes[side]![file]!);
      List<Object?> rowsOf(String side, String file) => [
        for (final r in dbs[side]!.ingredientMatchesFor(
          recipes[side]![file]!.id,
        ))
          (r.position, r.fdcId, r.grams, r.status, r.hold, r.parts),
      ];
      double gramsAt(String file, int position) => dbs['widened']!
          .ingredientMatchesFor(recipes['widened']![file]!.id)
          .singleWhere((r) => r.position == position)
          .grams!;

      test(
        'the four entries = the unwidened entry + [606, 605], in that order',
        () {
          for (final (id, sat, trans) in [
            ('2710824', 4.15, 0.01),
            ('2747667', 0.13, 0.0),
            ('2758998', 0.489, 0.0),
            ('2759000', 0.557, 0.003),
          ]) {
            final now = (_entry(id)['nutrients'] as Map).entries.toList();
            final before = (_unmerged(id)['nutrients'] as Map).entries.toList();
            expect(now.length, before.length + 2, reason: id);
            expect(
              [for (final e in now.skip(before.length)) (e.key, e.value)],
              [('606', sat), ('605', trans)],
              reason: id,
            );
          }
          // 2758998 is a nutrientSiblings KEY: a total never reads its 606.
          expect(nutrientSiblings[2758998], 169736);
        },
      );

      test('every row equal on the two caches; every key but saturated and '
          'trans equal', () {
        for (final file in [_guacamole, _nachos, _scallops]) {
          expect(
            rowsOf('widened', file),
            rowsOf('unwidened', file),
            reason: file,
          );
          final a = totals('unwidened', file);
          final b = totals('widened', file);
          for (final key in {...a.keys, ...b.keys}) {
            if (key != 'saturated' && key != 'trans') {
              expect(b[key], a[key], reason: '$file $key');
            }
          }
        }
      });

      test(
        'chunky-guacamole|0 "3 medium, ripe avocados" on 2710824 (450.00 g): '
        'saturated +450 × 4.15 / 100 = 18.675, trans +450 × 0.01 / 100 = '
        '0.045',
        () {
          final grams = gramsAt(_guacamole, 0);
          expect(grams, 450.0);
          final a = totals('unwidened', _guacamole);
          final b = totals('widened', _guacamole);
          final dSat = (b['saturated'] as double) - (a['saturated'] as double);
          final dTrans = (b['trans'] as double) - (a['trans'] as double);
          expect(dSat, closeTo(grams * 4.15 / 100, 1e-9));
          expect(dSat, closeTo(18.675, 1e-9));
          expect(dTrans, closeTo(grams * 0.01 / 100, 1e-9));
          expect(dTrans, closeTo(0.045, 1e-9));
        },
      );

      test('cheesy-nachos-with-guacamole-and-salsa restates the guacamole '
          'through its routed row: the same deltas', () {
        final routed = dbs['widened']!
            .ingredientMatchesFor(recipes['widened']![_nachos]!.id)
            .singleWhere((r) => r.position == 6);
        expect(routed.childRecipeId, recipes['widened']![_guacamole]!.id);
        double delta(String file, String key) =>
            (totals('widened', file)[key] as double) -
            (totals('unwidened', file)[key] as double);
        expect(delta(_nachos, 'saturated'), closeTo(18.675, 1e-9));
        expect(delta(_nachos, 'trans'), closeTo(0.045, 1e-9));
        expect(
          delta(_nachos, 'saturated'),
          closeTo(delta(_guacamole, 'saturated'), 1e-9),
        );
      });

      test('pan-seared-scallops|0 on 2747667 "Scallops, sea, frozen, wild '
          'caught": a trans key FIRST APPEARS at exactly 0.0; saturated rises '
          'by grams × 0.13 / 100', () {
        final grams = gramsAt(_scallops, 0);
        expect(grams, closeTo(680.39, 0.005));
        final a = totals('unwidened', _scallops);
        final b = totals('widened', _scallops);
        expect(a.containsKey('trans'), isFalse);
        expect(b['trans'], 0.0);
        expect(
          (b['saturated'] as double) - (a['saturated'] as double),
          closeTo(grams * 0.13 / 100, 1e-9),
        );
      });
    },
  );
}

/// The provider as the base's cache held the four widened records (SNAPW):
/// each without the 606 / 605 the merge appended.
class _Unwidened implements NutritionProvider {
  _Unwidened(this.inner);

  final NutritionProvider inner;

  @override
  Future<List<FdcCandidate>> search(String query) => inner.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async {
    final food = await inner.food(fdcId);
    return food == null ? null : FdcFood.fromJson(_unmerged('$fdcId'));
  }
}
