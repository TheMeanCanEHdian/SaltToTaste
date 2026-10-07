// Matcher v44, steps 1 and 3 (prep43 design_v2 §2 v44.1 / v44.3; S1, S15,
// N2, N3): a referenced SECTION is a recipe of its own, keyed
// `<host id>#<exact title>` in the same three tables, its FK carried by
// migration 019's VIRTUAL generated `host_id` (cascade kept); every
// nutrition path loads a row's, child's or job's id through
// `nutritionRecipeOf`; the per-recipe gates read the HOST (layout, the
// write race's `fresh()`, `_heldMediumNow` keyed by the row's recipe id);
// the bulk sweep orders [child section keys, non-parents, parents] over a
// LIBRARY-WIDE child set, collects what no main line routes to (never a
// decided row), and a host save drops the keys of its gone titles (S15).
//
// Real corpus recipes over recorded real FDC answers (FixtureProvider;
// three entries added --from-db from snapshot 19: search "virgin olive
// oil", search "caraway seeds", food 170918 — chraime and its Tabil),
// never the network. The pins written before step 2 (the engine's own
// section routing) landed write a parent ROUTED to a key in the routed
// shape design_v3 §2.2 item 3 gives (as v41's storage step did); every
// assertion holds for the engine's own row, and the yield-edit pin reads
// the engine's own route. Synthesized inputs, each a negative path and
// stated where used: a key with no host, a section title edited (S15), a
// stored medium hold cleared to the shape a stale recipe stores (N2), a
// pot step given to a section that stores none (F3), a section's yield
// edited (v44.3).

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/migrations.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _chraime = 'atk-tv-2023-1208-chraime';
const _tabil = '$_chraime#Tabil';
const _pieHost = 'atk-tv-2023-0972-basic-double-crust-pie-dough';
const _pie = '$_pieHost#Basic Single-Crust Pie Dough';
const _roast = 'atk-tv-2023-0214-roast-beef-tenderloin';

/// Snapshot 19 (the diag copy): the v43 replay's base, 13,615 main rows.
const _snapshot19 = '../../.claude/diag/2026-10-06/snap19.db';

void main() {
  late Directory tempDir;
  late ServerConfig config;
  late SaltDatabase db;
  late FixtureProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt-v44-storage-');
    config = ServerConfig(
      dataDir: tempDir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    );
    db = SaltDatabase.open(config.dbPath)
      ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
    provider = FixtureProvider();
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  Recipe store(String fileName) {
    final recipe = loadCorpusRecipe(fileName);
    db.upsertRecipe(
      recipe,
      sourceSlug: _source,
      contentHash: contentHashOf(recipe),
    );
    return recipe;
  }

  /// [key] as nutrition reads it now (a section key or a recipe id).
  Recipe now(String key) => nutritionRecipeOf(db, key)!.recipe;

  bool fresh(String key) => nutritionIsFresh(db, now(key));

  /// A second connection on the same file, for what the DAL does not
  /// expose (raw counts, `foreign_key_check`).
  T raw<T>(T Function(Database raw) read) {
    final connection = sqlite3.open(config.dbPath);
    try {
      return read(connection);
    } finally {
      connection.dispose();
    }
  }

  int countByHost(String host) => raw(
    (r) => [
      for (final table in [
        'ingredient_matches',
        'recipe_nutrition',
        'recipe_layout',
      ])
        r.select('SELECT count(*) AS n FROM $table WHERE host_id = ?', [
              host,
            ]).first['n']
            as int,
    ].fold(0, (a, b) => a + b),
  );

  /// [host]'s section [title] with its lines [a] and [b] swapped, saved
  /// through the recipe edit service (the recipe PUT's path): the section's
  /// own text, reordered — a real edit of real lines.
  void reorderSection(String host, String title, int a, int b) {
    final recipe = db.recipeByIdOrSlug(host)!.recipe;
    final subsections = [
      for (final sub in recipe.subsections)
        if (sub.title == title)
          () {
            final group = sub.ingredients!.first;
            final items = [...group.items];
            final first = items[a];
            items[a] = items[b];
            items[b] = first;
            return sub.copyWith(
              ingredients: [
                group.copyWith(items: items),
                ...sub.ingredients!.skip(1),
              ],
            );
          }()
        else
          sub,
    ];
    final result = updateRecipe(db, config, host, {
      'subsections': [for (final sub in subsections) sub.toMap()],
    });
    expect(result.changed, isTrue);
  }

  /// [parent]'s reference line [position] written ROUTED to [key] in the
  /// engine's routed shape (design_v3 §2.2 item 3), stamped with the key's
  /// current `computed_at`.
  IngredientMatchRow routeTo(Recipe parent, int position, String key) {
    final line = nutritionLines(parent)[position];
    expect(isSubRecipeReference(line.raw), isTrue, reason: line.raw);
    final child = db.nutritionFor(key)!;
    final row = IngredientMatchRow(
      recipeId: parent.id,
      position: position,
      raw: line.raw,
      itemKey: lineKeyOf(line),
      fdcId: null,
      description: null,
      dataType: null,
      confidence: 1,
      grams: child.totalGrams,
      gramSource: SaltDatabase.recipeGramSource,
      status: 'auto',
      childRecipeId: key,
      childShare: 1,
      childStamp: child.computedAt,
    );
    db.upsertIngredientMatch(row);
    return row;
  }

  Future<void> sweep(BulkScope scope) async {
    final job = startBulkJob(db, provider, scope: scope);
    expect(job, isNotNull);
    while (bulkJobRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(db.nutritionJob(job!)!['status'], 'done');
    expect(db.nutritionJob(job)!['failed'], 0);
  }

  test(
    'migration 019 on snapshot 19: every main row, stamp and layout '
    'byte-equal, foreign_key_check empty',
    skip: File(_snapshot19).existsSync() ? false : 'no snapshot 19 here',
    () {
      final path = '${tempDir.path}/snap19.db';
      File(_snapshot19).copySync(path);
      List<String> dump(Database d) => [
        for (final (table, order) in [
          ('ingredient_matches', 'recipe_id, position'),
          ('recipe_nutrition', 'recipe_id'),
          ('recipe_layout', 'recipe_id'),
        ])
          for (final row in d.select('SELECT * FROM $table ORDER BY $order'))
            [
              table,
              for (final column in row.keys)
                if (column != 'host_id') '$column=${row[column]}',
            ].join('|'),
      ];
      final before = sqlite3.open(path);
      expect(before.select('PRAGMA user_version').first.columnAt(0), 18);
      final rows = dump(before);
      before.dispose();
      expect(
        rows.where((row) => row.startsWith('ingredient_matches|')),
        hasLength(13615),
      );
      SaltDatabase.open(path).dispose();
      final after = sqlite3.open(path)..execute('PRAGMA foreign_keys = ON');
      addTearDown(after.dispose);
      expect(
        after.select('PRAGMA user_version').first.columnAt(0),
        migrations.length, // 19 at v44; 020 adds only indexes (v47 F9).
      );
      expect(dump(after), rows);
      expect(after.select('PRAGMA foreign_key_check'), isEmpty);
      // Every main row's host is itself.
      expect(
        after
            .select(
              'SELECT count(*) AS n FROM ingredient_matches '
              'WHERE host_id IS NOT recipe_id',
            )
            .first['n'],
        0,
      );
    },
  );

  group('a section key in storage (chraime#Tabil)', skip: skipIfNoCorpus, () {
    late Recipe chraime;

    setUp(() => chraime = store('1208-chraime.yaml'));

    test('nutritionRecipeOf reads the section; recipeByIdOrSlug refuses '
        'the key', () {
      expect(sectionKeyOf(chraime.id, 'Tabil'), _tabil);
      expect(hostOf(_tabil), chraime.id);
      expect(hostOf(chraime.id), chraime.id);
      final found = nutritionRecipeOf(db, _tabil)!;
      final tabil = found.recipe;
      expect(found.sourceSlug, _source);
      expect(tabil.id, _tabil);
      expect(tabil.title, 'Tabil');
      expect(tabil.servings, 'MAKES ABOUT ½ CUP');
      expect(tabil.steps, isEmpty); // R20: its method was never captured.
      expect(tabil.subsections, isEmpty);
      expect(
        [for (final line in nutritionLines(tabil)) line.raw],
        [
          '3½ tablespoons coriander seeds',
          '2 tablespoons plus 2 teaspoons caraway seeds',
          '1 tablespoon plus 2 teaspoons cumin seeds',
        ],
      );
      // Memoised per host instance: its lines stay identical.
      final host = db.recipeByIdOrSlug(chraime.id)!.recipe;
      expect(
        identical(
          nutritionLines(sectionOf(host, _tabil)!),
          nutritionLines(sectionOf(host, _tabil)!),
        ),
        isTrue,
      );
      // Favorites, images and notes load by recipeByIdOrSlug: never a key.
      expect(db.recipeByIdOrSlug(_tabil), isNull);
      expect(nutritionRecipeOf(db, '${chraime.id}#tabil'), isNull);
      // A synthesized key whose host does not exist (negative path).
      expect(nutritionRecipeOf(db, 'atk-tv-2023-9999-no-such#Tabil'), isNull);
      expect(nutritionRecipeOf(db, chraime.id)!.recipe.id, chraime.id);
    });

    test('a key inserts only with a live host; the host delete cascades '
        'all three tables; ON CONFLICT(recipe_id) upserts on a key', () async {
      await matchAndCompute(db, provider, now(_tabil));
      final rows = db.ingredientMatchesFor(_tabil);
      expect(rows, hasLength(3));
      expect(db.nutritionFor(_tabil)!.status, 'complete');
      final layout = db.layoutOf(_tabil);
      expect(layout.seq, greaterThan(0), reason: 'laid out (F2)');
      expect(layout.lines, [for (final row in rows) row.raw]);
      // A synthesized key with no host (negative path): the FK refuses it.
      expect(
        () => db.upsertIngredientMatch(
          IngredientMatchRow(
            recipeId: 'atk-tv-2023-9999-no-such#Tabil',
            position: 0,
            raw: rows.first.raw,
            fdcId: null,
            description: null,
            dataType: null,
            confidence: 0,
            grams: null,
            gramSource: null,
            status: 'unmatched',
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
      await matchAndCompute(db, provider, now(_tabil));
      expect(
        raw(
          (r) => r.select(
            'SELECT count(*) AS n FROM recipe_nutrition WHERE recipe_id = ?',
            [_tabil],
          ).first['n'],
        ),
        1,
      );
      expect(countByHost(chraime.id), greaterThan(0));
      deleteRecipe(db, config, chraime.id);
      expect(countByHost(chraime.id), 0);
      expect(db.ingredientMatchesFor(_tabil), isEmpty);
      expect(db.nutritionFor(_tabil), isNull);
      expect(db.layoutOf(_tabil).seq, 0);
      expect(raw((r) => r.select('PRAGMA foreign_key_check')), isEmpty);
    });

    test('LAYOUT on the host: a decided Tabil row follows its line across a '
        'host save reordering the section', () async {
      await matchAndCompute(db, provider, now(_tabil));
      final coriander = db
          .ingredientMatchesFor(_tabil)
          .singleWhere((row) => row.position == 0);
      expect(coriander.raw, '3½ tablespoons coriander seeds');
      db.upsertIngredientMatch(coriander.copyWith(status: 'skipped'));
      final seq = db.layoutOf(_tabil).seq;
      reorderSection(chraime.id, 'Tabil', 0, 2);
      expect(fresh(_tabil), isFalse, reason: 'the section hash moved');
      await matchAndCompute(db, provider, now(_tabil));
      final moved = db
          .ingredientMatchesFor(_tabil)
          .singleWhere((row) => row.raw == coriander.raw);
      expect(moved.position, 2);
      expect(moved.status, 'skipped');
      expect(db.layoutOf(_tabil).seq, greaterThan(seq));
      expect(db.layoutOf(_tabil).lines, [
        for (final line in nutritionLines(now(_tabil))) line.raw,
      ]);
      expect(fresh(_tabil), isTrue);
    });

    test("WRITE RACE on the host: a host save during the section compute's "
        'await writes no row and stamps nothing fresh', () async {
      provider.gate = Completer<void>();
      final before = now(_tabil);
      final compute = matchAndCompute(db, provider, before);
      while (provider.searchCalls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final written = db.ingredientMatchesFor(_tabil).length;
      reorderSection(chraime.id, 'Tabil', 0, 2);
      provider.gate!.complete();
      await compute;
      expect(db.ingredientMatchesFor(_tabil), hasLength(written));
      expect(fresh(_tabil), isFalse);
      for (final row in db.ingredientMatchesFor(_tabil)) {
        expect(
          row.raw,
          nutritionLines(now(_tabil))[row.position].raw,
          reason: 'no row on an old position',
        );
      }
    });
  });

  group(
    "N2: the held-medium cache keys the row's recipe id",
    skip: skipIfNoCorpus,
    () {
      // boiled-potatoes-with-black-olive-tapenade: main line 1 "1 tablespoon
      // salt" is the pot's salt, a held medium (snapshot 19 holds it
      // `discarded_medium`); its section "Black Olive Tapenade" (an A9 child)
      // has a line at position 1 too. Each row is written undecided with no
      // stored hold — the shape a stale recipe stores (a matcher bump not
      // yet swept; Run 053), synthesized as such: only then does the reach
      // read the line from the recipe now ([_heldMediumNow]).
      late Recipe potatoes;
      late IngredientMatchRow main;
      late IngredientMatchRow section;
      const key =
          'atk-tv-2023-0703-boiled-potatoes-with-black-olive-tapenade'
          '#Black Olive Tapenade';

      IngredientMatchRow undecided(String recipeId) {
        final line = nutritionLines(now(recipeId))[1];
        final row = IngredientMatchRow(
          recipeId: recipeId,
          position: 1,
          raw: line.raw,
          itemKey: lineKeyOf(line),
          fdcId: null,
          description: null,
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: 'unmatched',
        );
        db.upsertIngredientMatch(row);
        return row;
      }

      List<IngredientMatchRow> reach(IngredientMatchRow row) => decisionReach(
        db,
        row.itemKey!,
        excluding: (recipeId: 'none', position: 0),
      );

      setUp(() {
        potatoes = store('0703-boiled-potatoes-with-black-olive-tapenade.yaml');
        main = undecided(potatoes.id);
        section = undecided(key);
        expect(main.raw, '1 tablespoon salt');
        expect(section.raw, '1½ cups pitted kalamata olives');
        expect(heldMediumLine(potatoes, nutritionLines(potatoes)[1]), isTrue);
      });

      bool reached(IngredientMatchRow row) => reach(
        row,
      ).any((r) => r.recipeId == row.recipeId && r.position == row.position);

      test('the section line read first: the main pot salt stays held', () {
        expect(reached(section), isTrue);
        expect(reached(main), isFalse);
      });

      test('the main line read first: the section line stays reached', () {
        expect(reached(main), isFalse);
        expect(reached(section), isTrue);
      });
    },
  );

  group(
    "F3: a held-medium SECTION line stays out of the key's reach",
    skip: skipIfNoCorpus,
    () {
      // roast-beef-tenderloin's section "Shallot and Parsley Butter" (a PO
      // candidate) lists "¼ teaspoon table salt" at position 4; no section
      // of snapshot 19 holds a medium (verify44 D3: 0 of the 140 sections'
      // lines read heldMediumLine), so the section is given a step of its
      // own that boils and drains that salt — a SYNTHESIZED step, the
      // negative path, worded on the two pot steps of 0703 (boiled
      // potatoes: "Bring 6 cups water, potatoes, and salt to boil …", then
      // "… Drain potatoes …").
      // The row is the one the key stored BEFORE that save (undecided, no
      // hold — a stale section); only [_heldMediumNow] reading the line from
      // the section now, by its HOST's hash, keeps it out of the reach.
      const title = 'Shallot and Parsley Butter';
      const key = '$_roast#$title';
      const steps = [
        RecipeStep(
          number: 1,
          text:
              'Bring 6 cups water, shallot, and salt to boil in large '
              'saucepan.',
        ),
        RecipeStep(number: 2, text: 'Drain shallot.'),
      ];

      test('a key decision leaves it out of `others` once a step holds it', () {
        store('0214-roast-beef-tenderloin.yaml');
        final before = now(key);
        final line = nutritionLines(before)[4];
        expect(line.raw, '¼ teaspoon table salt');
        expect(before.steps, isEmpty); // R20: its method was never captured.
        expect(heldMediumLine(before, line), isFalse);
        final row = IngredientMatchRow(
          recipeId: key,
          position: 4,
          raw: line.raw,
          itemKey: lineKeyOf(line),
          fdcId: null,
          description: null,
          dataType: null,
          confidence: 0,
          grams: null,
          gramSource: null,
          status: 'unmatched',
        );
        db.upsertIngredientMatch(row);
        bool reached() => decisionReach(
          db,
          row.itemKey!,
          excluding: (recipeId: 'none', position: 0),
        ).any((r) => r.recipeId == key && r.position == 4);
        expect(reached(), isTrue, reason: 'not a medium yet');

        final host = db.recipeByIdOrSlug(_roast)!.recipe;
        final result = updateRecipe(db, config, _roast, {
          'subsections': [
            for (final sub in host.subsections)
              (sub.title == title
                      ? sub.copyWith(
                          steps: steps,
                        )
                      : sub)
                  .toMap(),
          ],
        });
        expect(result.changed, isTrue);
        final saved = now(key);
        expect(saved.steps, steps);
        expect(heldMediumLine(saved, nutritionLines(saved)[4]), isTrue);
        expect(db.ingredientMatchesFor(key).single.hold, isNull);
        expect(reached(), isFalse);
      });
    },
  );

  group('order and cascade', skip: skipIfNoCorpus, () {
    test('a fresh import orders [child section keys, non-parents, parents] '
        'in missing and all', () {
      store('1208-chraime.yaml');
      store('0972-basic-double-crust-pie-dough.yaml');
      store('0742-quiche-lorraine.yaml');
      final scoped = bulkScope(db, BulkScope.missing);
      expect(scoped.children, {_tabil, _pie});
      const order = [
        _pie,
        _tabil,
        _pieHost,
        'atk-tv-2023-0742-quiche-lorraine',
        _chraime,
      ];
      expect(scoped.ids, order);
      expect(bulkScopeIds(db, BulkScope.all), order);
    });

    test('the child set: a food-counted section line and a prose-only '
        'target make no child', () {
      // The four `section` resolutions a shipped food rule counts (P1 §2.1;
      // their rows stay food rows) and lemon-meringue-pie|0, whose target
      // lists no ingredients (S13's `no_ingredients`).
      // The prose-only target is another recipe's section: its host stored.
      store('0972-basic-double-crust-pie-dough.yaml');
      for (final file in [
        '0731-curry-deviled-eggs-with-easy-peel-hard-cooked-eggs.yaml',
        '1192-gado-gado.yaml',
        '0478-ground-beef-tacos.yaml',
        '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
        '0989-lemon-meringue-pie.yaml',
      ]) {
        final recipe = store(file);
        expect(
          sectionChildKeysOf(db, now(recipe.id), ResolverMemo(db)),
          isEmpty,
          reason: file,
        );
      }
      expect(bulkScope(db, BulkScope.all).children, isEmpty);
    });

    test('seedLayout seeds a key while its host lives', () {
      store('1208-chraime.yaml');
      final lines = [for (final line in nutritionLines(now(_tabil))) line.raw];
      expect(db.seedLayout(_tabil, lines), isTrue);
      expect(db.layoutOf(_tabil).lines, lines);
      expect(db.seedLayout('atk-tv-2023-9999-no-such#Tabil', lines), isFalse);
    });

    test('a child section with no stamp joins the stale scope first', () async {
      final chraime = store('1208-chraime.yaml');
      await matchAndCompute(db, provider, now(chraime.id));
      expect(db.nutritionFor(_tabil), isNull);
      expect(bulkScopeIds(db, BulkScope.stale).first, _tabil);
      expect(bulkScopeIds(db, BulkScope.missing), [_tabil]);
    });

    test('a Tabil line edit: the stale scope is [chraime#Tabil, chraime]; '
        'one sweep leaves both fresh', () async {
      final chraime = store('1208-chraime.yaml');
      await matchAndCompute(db, provider, now(_tabil));
      await matchAndCompute(db, provider, now(chraime.id));
      routeTo(now(chraime.id), 7, _tabil);
      expect(fresh(_tabil), isTrue);
      expect(fresh(chraime.id), isTrue);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
      reorderSection(chraime.id, 'Tabil', 0, 1);
      // v47 (F5, Run 062 critic): its own hash reads the titles only, but
      // the section it routes to is no longer fresh — the page reads stale.
      expect(nutritionStampCurrent(db, now(chraime.id)), isTrue);
      expect(fresh(chraime.id), isFalse, reason: 'its routed Tabil changed');
      expect(bulkScopeIds(db, BulkScope.stale), [_tabil, chraime.id]);
      await sweep(BulkScope.stale);
      expect(fresh(_tabil), isTrue);
      expect(fresh(chraime.id), isTrue);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    });

    test("a Tabil YIELD edit re-reads the parent's share: the stale scope "
        'is [chraime#Tabil, chraime]; one sweep halves chraime|7', () async {
      // verify44 D4, the design's v44.3 pin, end to end on the ENGINE's own
      // route (step 2): "1 tablespoon tabil (recipe follows)" of "MAKES
      // ABOUT ½ CUP" reads 0.125 (the v44 replay's chraime|7, 5.66 g); the
      // yield edited to "MAKES ABOUT 1 CUP" — a SYNTHESIZED edit, the
      // negative path — moves only the section's hash (its `servings` term),
      // and the sweep re-reads the share from the section's new yield.
      final chraime = store('1208-chraime.yaml');
      await sweep(BulkScope.missing);
      IngredientMatchRow tabilRow() => db
          .ingredientMatchesFor(chraime.id)
          .singleWhere((row) => row.position == 7);
      var row = tabilRow();
      expect(row.raw, '1 tablespoon tabil (recipe follows)');
      expect(row.childRecipeId, _tabil);
      expect(row.childShare, closeTo(0.125, 1e-6));
      expect(row.grams, closeTo(5.66, 0.005));
      final total = db.nutritionFor(_tabil)!.totalGrams!;
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);

      final host = db.recipeByIdOrSlug(chraime.id)!.recipe;
      final result = updateRecipe(db, config, chraime.id, {
        'subsections': [
          for (final sub in host.subsections)
            (sub.title == 'Tabil'
                    ? sub.copyWith(servings: 'MAKES ABOUT 1 CUP')
                    : sub)
                .toMap(),
        ],
      });
      expect(result.changed, isTrue);
      // v47 (F5): its own stamp current, its routed section's not — stale.
      expect(nutritionStampCurrent(db, now(chraime.id)), isTrue);
      expect(fresh(chraime.id), isFalse, reason: 'its routed Tabil changed');
      expect(fresh(_tabil), isFalse, reason: "the section's servings");
      expect(bulkScopeIds(db, BulkScope.stale), [_tabil, chraime.id]);
      await sweep(BulkScope.stale);
      row = tabilRow();
      expect(row.childRecipeId, _tabil);
      expect(row.childShare, closeTo(1 / 16, 1e-6));
      expect(row.grams, closeTo(2.83, 0.005));
      expect(row.grams, closeTo(total * row.childShare!, 1e-9));
      expect(row.childStamp, db.nutritionFor(_tabil)!.computedAt);
      expect(bulkScopeIds(db, BulkScope.stale), isEmpty);
    });

    test('a Basic Single-Crust Pie Dough edit appends quiche-lorraine, '
        'pumpkin-pie and pecan-pie', () async {
      store('0972-basic-double-crust-pie-dough.yaml');
      final parents = [
        store('0742-quiche-lorraine.yaml'),
        store('0987-pumpkin-pie.yaml'),
        store('0988-pecan-pie.yaml'),
      ];
      await matchAndCompute(db, provider, now(_pie));
      for (final parent in parents) {
        routeTo(now(parent.id), 0, _pie);
      }
      reorderSection(_pieHost, 'Basic Single-Crust Pie Dough', 0, 1);
      expect(bulkScopeIds(db, BulkScope.stale), [
        _pie,
        for (final parent in parents) parent.id,
      ]);
    });

    test('a stale sweep of ONE recipe leaves the other section stamps '
        '(the child set is library-wide, F5)', () async {
      final chraime = store('1208-chraime.yaml');
      store('0972-basic-double-crust-pie-dough.yaml');
      store('0742-quiche-lorraine.yaml');
      await matchAndCompute(db, provider, now(_tabil));
      await matchAndCompute(db, provider, now(_pie));
      await matchAndCompute(db, provider, now(chraime.id));
      final pie = db.nutritionFor(_pie)!.computedAt;
      final main = now(chraime.id);
      final items = [...main.ingredients.first.items];
      items.insert(0, items.removeAt(1));
      updateRecipe(db, config, chraime.id, {
        'ingredients': [
          main.ingredients.first.copyWith(items: items).toMap(),
          for (final group in main.ingredients.skip(1)) group.toMap(),
        ],
      });
      expect(bulkScopeIds(db, BulkScope.stale), [chraime.id]);
      await sweep(BulkScope.stale);
      expect(db.nutritionFor(_pie)?.computedAt, pie);
      expect(db.nutritionFor(_tabil), isNotNull);
    });

    test('the GC collects a key no main line routes to any more — its stamp '
        'and engine rows — and never a decided row (F5, R21)', () async {
      final chraime = store('1208-chraime.yaml');
      await matchAndCompute(db, provider, now(_tabil));
      final caraway = db
          .ingredientMatchesFor(_tabil)
          .singleWhere((row) => row.position == 1);
      db.upsertIngredientMatch(caraway.copyWith(status: 'skipped'));
      // Still a child: nothing collected.
      expect(
        db.collectSectionGarbage(bulkScope(db, BulkScope.all).children),
        [
          isEmpty,
        ].first,
      );
      expect(db.nutritionFor(_tabil), isNotNull);
      // chraime's line 7 "1 tablespoon tabil (recipe follows)" removed: no
      // main line routes to the section now.
      final main = now(chraime.id);
      updateRecipe(db, config, chraime.id, {
        'ingredients': [
          for (final group in main.ingredients)
            group
                .copyWith(
                  items: [
                    for (final item in group.items)
                      if (!isSubRecipeReference(item.raw)) item,
                  ],
                )
                .toMap(),
        ],
      });
      final children = bulkScope(db, BulkScope.stale).children;
      expect(children, isEmpty);
      expect(db.collectSectionGarbage(children), [_tabil]);
      expect(db.nutritionFor(_tabil), isNull);
      final left = db.ingredientMatchesFor(_tabil);
      expect(left, hasLength(1));
      expect(left.single.raw, caraway.raw);
      expect(left.single.status, 'skipped');
      expect(db.layoutOf(_tabil).seq, greaterThan(0), reason: 'its row stays');
      expect(
        db.collectSectionGarbage(children),
        isEmpty,
        reason: 'only a decided row is left: nothing to collect',
      );
    });

    test('S15: a host section retitle drops the old key (rows, stamp, '
        'layout); the parent pick on it reads its child gone', () async {
      // roast-beef-tenderloin|5 "1 recipe flavored butter (recipes follow)"
      // picked "Shallot and Parsley Butter" by a person (a decided row,
      // derived for its stamp). The retitle is synthesized (negative path).
      final roast = store('0214-roast-beef-tenderloin.yaml');
      const butter = '$_roast#Shallot and Parsley Butter';
      await matchAndCompute(db, provider, now(butter));
      await matchAndCompute(db, provider, now(roast.id));
      final picked = routeTo(now(roast.id), 5, butter);
      final stamp = db.nutritionFor(roast.id)!;
      db.upsertIngredientMatch(
        picked.copyWith(
          status: 'confirmed',
          derivedSeq: derivedKeyOf(
            db.layoutSeqOf(roast.id),
            stamp.ingredientsHash,
          ),
        ),
      );
      expect(db.hasUnderivedRows(roast.id), isFalse);
      final mainRows = db.ingredientMatchesFor(roast.id).length;
      final host = now(roast.id);
      updateRecipe(db, config, roast.id, {
        'subsections': [
          for (final sub in host.subsections)
            (sub.title == 'Shallot and Parsley Butter'
                    ? sub.copyWith(title: 'Shallot-Parsley Butter')
                    : sub)
                .toMap(),
        ],
      });
      expect(db.ingredientMatchesFor(butter), isEmpty);
      expect(db.nutritionFor(butter), isNull);
      expect(db.layoutOf(butter).seq, 0);
      expect(nutritionRecipeOf(db, butter), isNull);
      expect(db.ingredientMatchesFor(roast.id), hasLength(mainRows));
      expect(
        db
            .ingredientMatchesFor(roast.id)
            .singleWhere((row) => row.position == 5)
            .childRecipeId,
        butter,
        reason: 'the pick names the old key; the GET names its old title',
      );
      expect(db.hasUnderivedRows(roast.id), isTrue, reason: 'child gone');
    });

    test(
      "the per-recipe job computes the recipe's child sections first",
      () async {
        final chraime = store('1208-chraime.yaml');
        expect(db.nutritionFor(_tabil), isNull);
        startRecipeComputeJob(db, provider, now(chraime.id));
        while (recipeComputeJobId(chraime.id) != null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(fresh(_tabil), isTrue);
        expect(fresh(chraime.id), isTrue);
      },
    );
  });

  test('grep-pin [F2]: no nutrition path loads a row, child or job id by '
      'recipeByIdOrSlug, contentHashOf or recipeExists without its host', () {
    final files = [
      ...Directory('lib/src/nutrition').listSync().whereType<File>().where(
        (file) => file.path.endsWith('.dart'),
      ),
      for (final path in [
        'lib/src/handlers/nutrition_handlers.dart',
        'lib/src/services/nutrition_composite.dart',
        'lib/src/services/nutrition_review.dart',
        'lib/src/services/decision_rekey.dart',
        'lib/src/services/item_key_backfill.dart',
        'lib/src/services/layout_backfill.dart',
      ])
        File(path),
    ];
    final byId = <String>[];
    for (final file in files) {
      final text = file.readAsStringSync();
      for (final match in RegExp(
        r'recipeByIdOrSlug\(([^)]*)\)|contentHashOf\((?!hostOf\()|'
        r'recipeExists\(',
      ).allMatches(text)) {
        byId.add('${file.path}: ${match[0]}');
      }
    }
    // nutritionRecipeOf's own two reads and the resolver memo's host read.
    expect(byId, [
      'lib/src/nutrition/engine.dart: recipeByIdOrSlug(id)',
      'lib/src/nutrition/engine.dart: recipeByIdOrSlug(key)',
      'lib/src/nutrition/engine.dart: recipeByIdOrSlug(host)',
    ]);
    // The layout gates bind the HOST (salt_database.dart, F2).
    final dal = File('lib/src/db/salt_database.dart').readAsStringSync();
    expect(
      RegExp(r'FROM recipes WHERE id = \?').allMatches(dal).length,
      // upsertRecipe x2, recipeExists, deleteRecipe x2, recipeByIdOrSlug,
      // recipeIdentityByIdOrSlug, contentHashOf, the two layout gates.
      10,
    );
    expect(dal, contains('.execute([recipeId, texts, hostOf(recipeId)])'));
    expect(dal, contains('.select([hostOf(recipeId)]).isEmpty'));
  });
}
