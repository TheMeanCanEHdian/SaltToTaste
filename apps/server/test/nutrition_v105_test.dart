// Matcher v105 (batch fix105 at the base 5e6b4d7; matcherVersion 97
// unchanged) — the fixes of dual-fleet review Run 079/080 over v104,
// union U1–U14 (.claude/diag/2026-11-06/review079/union_S.md; the rulings
// in fix105/brief.md). Every pin is a real corpus recipe through the real
// compute / PUT on the recorded fixtures; each STATED synthesized input
// names its exception and its corpus source.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v25_cost_test.dart' show fill;
import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, capped;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'nutrition_v28_rule_a_test.dart' as v28;
import 'nutrition_v29_rule_a_test.dart' as v29;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _bulalo = '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml';
const _herb = '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';

final _fx = FixtureProvider(pending: pendingSearches);

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v105-');
  final config = ServerConfig(
    dataDir: dir.path,
    logLevel: Level.WARNING,
    trustProxy: false,
  );
  final db = SaltDatabase.open(config.dbPath)
    ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return db;
}

Recipe _store(SaltDatabase db, Recipe r) {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

/// [r] stored and computed (its section children first); the stored copy.
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  final stored = _store(db, r);
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

/// [r] with its main line [position]'s raw text replaced and its amounts
/// set to [amounts].
Recipe _withLine(Recipe r, int position, String raw, List<Amount> amounts) {
  var at = 0;
  return r.copyWith(
    ingredients: [
      for (final g in r.ingredients)
        g.copyWith(
          items: [
            for (final l in g.items)
              (at++ == position) ? l.copyWith(raw: raw, amounts: amounts) : l,
          ],
        ),
    ],
  );
}

Future<Map<String, Object?>> _child(
  SaltDatabase db,
  NutritionProvider fdc,
  String id,
  int at,
) async {
  final body = await matchesBody(db, fdc, nutritionRecipeOf(db, id)!.recipe);
  jsonEncode(body);
  final item = (body['items']! as List)
      .cast<Map<String, Object?>>()
      .singleWhere((i) => i['position'] == at);
  return (item['match']! as Map<String, Object?>)['child']!
      as Map<String, Object?>;
}

class _NoNet implements NutritionProvider {
  int calls = 0;
  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls++;
    throw const NutritionProviderException('no net', scope: FailureScope.food);
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    calls++;
    throw const NutritionProviderException('no net', scope: FailureScope.food);
  }
}

void main() {
  group('v105 (fix105: Run 079/080 U1–U14)', skip: skipIfNoCorpus, () {
    u1();
    u2();
    u3();
    u13();
    u5();
    u6();
    u10();
    u8();
  });
}

/// U1 (MED; S1/S4/S5, O1/O3/O4): v104 U6's re-stamp on its sibling arm —
/// the compute's DECIDED re-read arm wrote only `derived_seq`, so a
/// person-confirmed two-part row kept `held_on` on the part already cached
/// and the other part's arrival re-opened nothing (0040: 8/9 at 78.12,
/// fresh). v105: that arm re-stamps `held_on` as the engine cacheOnly arm
/// does. 0040 line 5 (v41's rendered bacon, row food 168277, parts 168322 +
/// 172345) confirmed through the real PUT after 0118. STATED synthesized
/// (negative path, as nutrition_v104_test.dart U6's own pin): both parts
/// dropped from the caches and a FOOD fault on both.
void u1() {
  test(
    'U1: a confirmed row held on two parts follows the part still uncached; '
    'its arrival re-opens the row; 9/9 at 274.36, 0 requests',
    () async {
      final (db, path) = a.pathDb();
      final r = loadCorpusRecipe(
        '0040-wilted-spinach-salad-with-warm-bacon-dressing.yaml',
      );
      final ham = loadCorpusRecipe(
        '0118-stuffed-chicken-cutlets-with-ham-and-cheddar.yaml',
      );
      await d.editAndCompute(db, _fx, ham);
      await d.editAndCompute(db, _fx, r);
      await applyMatchOverride(db, _fx, r, 5, {
        'raw': nutritionLines(r)[5].raw,
        'confirmed': true,
      });
      expect(d.rowOf(db, r, 5).status, 'confirmed');
      expect(db.nutritionFor(r.id)!.caloriesPerServing, closeTo(274.36, 0.005));
      v28.dropFood(path, 168322);
      v28.dropFood(path, 172345);
      final fault = v28.FoodFault(
        _fx,
        {168322, 172345},
        scope: FailureScope.food,
      );
      for (var p = 1; p <= 3; p++) {
        await matchAndCompute(db, fault, r);
      }
      final held = d.rowOf(db, r, 5);
      expect(
        (held.status, held.fdcId, held.hold, held.heldOn),
        ('confirmed', 168277, 'food_unavailable', 168322),
      );
      // 0118's compute caches 168322: the row re-opens (v103 U5).
      await matchAndCompute(db, v29.Asks(_fx), ham);
      expect(knownFood(db, 168322), isNotNull);
      expect(d.rowOf(db, r, 5).derivedSeq, isNull);
      final none = _NoNet();
      await matchAndCompute(db, none, r);
      expect(none.calls, 0);
      final still = d.rowOf(db, r, 5);
      // The re-stamp (base: held_on stayed 168322, the cached part).
      expect((still.hold, still.heldOn), ('food_unavailable', 172345));
      expect(still.derivedSeq, isNotNull);
      // The held_on-only arm (closer 1, D1; v104 U6's own step on the
      // sibling arm): derived_seq current, held_on naming a CACHED part —
      // the re-stamp still fires. STATED synthesized (negative path: no
      // corpus run leaves held_on on a cached part under a current
      // derived_seq, the state the disjunct repairs): held_on UPDATEd raw
      // onto 168322, the part 0118's compute cached above.
      sqlite3.open(path)
        ..execute(
          'UPDATE ingredient_matches SET held_on = ? '
          'WHERE recipe_id = ? AND position = ?',
          [168322, r.id, 5],
        )
        ..dispose();
      expect(
        (d.rowOf(db, r, 5).heldOn, d.rowOf(db, r, 5).derivedSeq),
        (168322, still.derivedSeq),
      );
      final restamp = _NoNet();
      await matchAndCompute(db, restamp, r);
      expect(restamp.calls, 0);
      expect(
        (d.rowOf(db, r, 5).status, d.rowOf(db, r, 5).heldOn),
        ('confirmed', 172345),
      );
      expect(d.rowOf(db, r, 5).derivedSeq, still.derivedSeq);
      // 172345 arrives: the row re-opens (base: derived_seq kept, fresh).
      await cachedFood(db, _fx, 172345);
      expect(d.rowOf(db, r, 5).derivedSeq, isNull);
      expect(nutritionIsFresh(db, r), isFalse);
      await matchAndCompute(db, none, r);
      expect(none.calls, 0);
      final healed = d.rowOf(db, r, 5);
      expect((healed.hold, healed.heldOn), (null, null));
      final totals = db.nutritionFor(r.id)!;
      expect((totals.matchedCount, totals.totalCount), (9, 9));
      expect(totals.caloriesPerServing, closeTo(274.36, 0.005));
    },
  );
}

/// U2 (LOW; S2/S3, O2): v104 U4's guard on its sibling arm — routeShareOf's
/// A9 bare-count arm (a SECTION child, one unitless '1') read a line that
/// WRITES an out-of-range share as the whole batch (0184|3: child_share
/// 1.0, 1,456.7 g). v105: neither whole-batch arm reads a line that writes
/// its own share ([writesShare]). STATED synthesized (negative path: the
/// corpus writes only '(½ recipe' / '(1/2 recipe' — 6 lines, grep): 0184
/// Herb Sauce line 3 "¼ cup Sauce Base (½ recipe; recipe follows)" edited to
/// the texts below with amounts [count '1'].
void u2() {
  const one = [Amount(measure: Measure.count, quantity: '1', primary: true)];
  for (final edit in [
    '1 Sauce Base (0 recipe)',
    '1 Sauce Base (500000 recipes)',
  ]) {
    test('U2: "$edit" with amount 1 reads not_routed no_share', () async {
      final db = _db();
      final real = loadCorpusRecipe(_herb);
      expect(
        nutritionLines(real)[3].raw,
        '¼ cup Sauce Base (½ recipe; recipe follows)',
      );
      final stored = await _compute(db, _fx, _withLine(real, 3, edit, one));
      final row = _row(db, stored.id, 3);
      // Base: auto, child_share 1.0, grams 1,456.7 (the fleets' probe).
      expect(
        (row.status, row.hold, row.childShare, row.grams, row.gramSource),
        ('confirmed', null, null, 0.0, 'unmeasured'),
      );
      final child = await _child(db, _fx, stored.id, 3);
      expect((child['state'], child['reason']), ('not_routed', 'no_share'));
    });
  }

  test('U2: the "(½ recipe)" control with amount 1 reads 0.5', () async {
    final db = _db();
    final stored = await _compute(
      db,
      _fx,
      _withLine(loadCorpusRecipe(_herb), 3, '1 Sauce Base (½ recipe)', one),
    );
    final row = _row(db, stored.id, 3);
    expect(row.childShare, 0.5);
    expect(row.grams, closeTo(728.35, 0.005));
    expect((await _child(db, _fx, stored.id, 3))['kcal'], 212.83);
  });
}

/// U3 (MED; S6, O5): v104 U10's class on a sibling caller —
/// applyRecipeToOthers called [derivedFor] per reached TARGET with no
/// `references:`, so the child was decoded and rescanned once per target
/// (3 parents × 400 lines: 1,220 decodes, 13.95 s, over the backstop).
/// v105: the request's one memo. STATED synthesized cap shape (the Opus O5
/// probe): 0972 Basic Double-Crust Pie Dough re-lined with its own real
/// lines to 400 and 120 × 10,000-char steps of its own step 1, stored under
/// a new id; 3 recipes each holding 0977 Classic Apple Pie's real line 0
/// "1 recipe double-crust pie dough" × 400, routed to the real 0972.
void u3() {
  test(
    'U3: a recipe pick applied to 1,199 routed lines reads the child once '
    "per request on the apply's read; the totals write rescans once per "
    'target (21 / 8) — hostDecodes and madeFromScans exact, under the '
    'backstop',
    () async {
      final db = wp.tempDb();
      final dough = loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml');
      final own = nutritionLines(dough);
      final child = capped(
        dough,
        [for (var i = 0; i < capLines; i++) own[i % own.length].raw],
        [
          for (var i = 0; i < capSteps; i++)
            fill('${dough.steps[0].text} ', capStep),
        ],
      );
      wp.saveRecipe(db, dough);
      await matchAndCompute(db, _fx, db.recipeByIdOrSlug(dough.id)!.recipe);
      final other = child.copyWith(
        id: '${child.id}-b',
        slug: '${child.slug}-b',
        title: 'Probe Pie Dough B',
      );
      wp.saveRecipe(db, other);
      await matchAndCompute(db, _fx, db.recipeByIdOrSlug(other.id)!.recipe);
      final pie = loadCorpusRecipe('0977-classic-apple-pie.yaml');
      final line = nutritionLines(pie)[0];
      expect(line.raw, '1 recipe double-crust pie dough');
      final many = [IngredientGroup(items: List.filled(capLines, line))];
      wp.saveRecipe(db, pie.copyWith(ingredients: many));
      for (var c = 1; c < 3; c++) {
        final t = pie.copyWith(
          id: '${pie.id}-c$c',
          slug: '${pie.slug}-c$c',
          ingredients: many,
        );
        wp.saveRecipe(db, t);
        await matchAndCompute(db, _fx, db.recipeByIdOrSlug(t.id)!.recipe);
      }
      Recipe stored() => db.recipeByIdOrSlug(pie.id)!.recipe;
      await matchAndCompute(db, _fx, stored());
      final rows = db.ingredientMatchesFor(pie.id);
      expect(rows.where((m) => m.childRecipeId == dough.id), hasLength(400));
      hostDecodes = 0;
      madeFromScans = 0;
      final clock = Stopwatch()..start();
      final res = await applyMatchOverride(db, _fx, stored(), 0, {
        'raw': rows[0].raw,
        'child': other.slug,
        'apply_to_all': true,
      });
      final ms = clock.elapsedMilliseconds;
      // Measured (hostDecodes, madeFromScans): the tip (21, 8); base 5e6b4d7
      // (the fleets' probe) 1,220 / 1,206 at 13.95 s. Mutant (the argument
      // dropped): (1220, 1206).
      expect((hostDecodes, madeFromScans), (21, 8));
      expect(ms, lessThan(backstopMs), reason: '${ms}ms');
      expect((res!.lines, res.recipes), (1199, 3));
      for (final id in [pie.id, '${pie.id}-c1', '${pie.id}-c2']) {
        final all = db.ingredientMatchesFor(id);
        expect(all, hasLength(400));
        expect(
          all.every(
            (m) => m.status == 'overridden' && m.childRecipeId == other.id,
          ),
          isTrue,
        );
        expect(nutritionIsFresh(db, nutritionRecipeOf(db, id)!.recipe), isTrue);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// U13 (LOW; O-C3): v104 U10's class on the GET's sibling —
/// `_sectionCandidateJson` read `lines.any(isReferenceIn)` per (row,
/// candidate), outside the `_madeFrom` memo (0158 × 400 rows on a
/// 400-line section: 160,000 reads). v105: [madeFromRecipe] on the GET's
/// memo, once per section a request (RULE C). STATED synthesized cap
/// shapes (the critic's): 0158 Classic Roast Stuffed Turkey's main group
/// 400 × its real line 7, its stuffing section re-lined with 400 of 0972
/// Basic Double-Crust Pie Dough's real lines (quiet: no reference line);
/// the TRUE path the same with its LAST line 0977's real "1 recipe
/// double-crust pie dough" (the section reads `nested`).
void u13() {
  for (final nested in [false, true]) {
    test('U13: 400 rows on a 400-line section (nested $nested) — the GET '
        'scans the section once, isReferenceIn reads exact, under the '
        'backstop', () async {
      final base = loadCorpusRecipe('0158-classic-roast-stuffed-turkey.yaml');
      final ref = nutritionLines(base)[7];
      expect(
        ref.raw,
        '1 recipe Bread Stuffing with Bacon, Apples, Sage, and Caramelized '
        'Onions (recipe follows)',
      );
      final own = nutritionLines(
        loadCorpusRecipe('0972-basic-double-crust-pie-dough.yaml'),
      );
      final pieLine = nutritionLines(
        loadCorpusRecipe('0977-classic-apple-pie.yaml'),
      )[0];
      final stuffing = base.subsections.first;
      final r = base.copyWith(
        ingredients: [IngredientGroup(items: List.filled(400, ref))],
        subsections: [
          stuffing.copyWith(
            ingredients: [
              IngredientGroup(
                items: [
                  for (var i = 0; i < 400; i++)
                    nested && i == 399 ? pieLine : own[i % own.length],
                ],
              ),
            ],
          ),
          ...base.subsections.skip(1),
        ],
      );
      validateRecipeDocument(r);
      final db = _db();
      final stored = await _compute(db, _fx, r);
      final key = sectionKeyOf(r.id, stuffing.title!);
      final rows = db.ingredientMatchesFor(r.id);
      expect(rows.where((m) => m.childRecipeId == key), hasLength(400));
      hostDecodes = 0;
      madeFromScans = 0;
      referenceReads = 0;
      final clock = Stopwatch()..start();
      final body = await matchesBody(db, _fx, stored);
      final ms = clock.elapsedMilliseconds;
      // Measured (hostDecodes, madeFromScans, referenceReads): the tip
      // (1, 1, 800) on both paths — the 400 host lines once and the
      // section's 400 once. Mutant (the bare any() back): quiet (1, 1,
      // 160,800), nested (1, 0, 160,400) — the section rescanned per row.
      expect((hostDecodes, madeFromScans, referenceReads), (1, 1, 800));
      final item = (body['items']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((i) => i['position'] == 0);
      final child =
          (item['match']! as Map<String, Object?>)['child']!
              as Map<String, Object?>;
      expect(child['state'], nested ? 'held' : 'routed');
      expect(
        [
          for (final c
              in (child['candidates']! as List).cast<Map<String, Object?>>())
            c['state'],
        ],
        [if (nested) 'nested' else 'ready'],
      );
      expect(ms, lessThan(backstopMs), reason: '${ms}ms');
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

/// [corpus] with its one step sentence [sentence] replaced by [to].
Recipe _stepEdited(Recipe corpus, String sentence, String to) {
  var hits = 0;
  final steps = [
    for (final s in corpus.steps)
      s.text.contains(sentence)
          ? (() {
              hits++;
              return s.copyWith(text: s.text.replaceFirst(sentence, to));
            })()
          : s,
  ];
  expect(hits, 1, reason: sentence);
  return corpus.copyWith(steps: steps);
}

/// U5 (LOW; S-C2, O-C1/O-C3): v104 U5's guard on its pour-off arm —
/// `_negatesSkim` knew skim phrasing only, so a NEGATED pour-off passed
/// `_skimsFatIn` and `_skimsFat`'s K2 arm read it as a skim; `_panFactsOf`
/// read `_poursOffFat` bare (`discarded`). v105: the pour / spoon /
/// drain-off negations and "never skim" join `_negatesSkim`; `_panFactsOf`
/// reads the same guard. Corpus reach 0 (steps: no negated pour / spoon /
/// drain-off; the one negated skim is 0492's). STATED synthesized
/// replacements of 1171 bulalo's real K1 sentence "Using wide, shallow
/// spoon, skim excess fat from surface of broth." (the Opus C3 table, one
/// per phrase).
void u5() {
  const real =
      'Using wide, shallow spoon, skim excess fat from surface of broth.';
  test("U5: bulalo's real skim is a skim (the control)", () {
    final bulalo = loadCorpusRecipe(_bulalo);
    expect(fatSkimmedOf(bulalo), isTrue);
    expect(browningFatLinesOf(bulalo), {0});
  });
  for (final negation in [
    'do not pour off the fat from the broth',
    "don't pour off the fat",
    'don’t pour off the fat',
    'do not spoon off the fat',
    "don't spoon off the fat",
    'don’t spoon off the fat',
    'do not drain off the fat',
    "don't drain off the fat",
    'don’t drain off the fat',
    'without pouring off the fat',
    'without spooning off the fat',
    'without draining off the fat',
    'never skim the fat',
  ]) {
    test('U5: "($negation)" is no skim and names no browning fat line', () {
      final edited = _stepEdited(
        loadCorpusRecipe(_bulalo),
        real,
        'Using wide, shallow spoon, remove the bones ($negation).',
      );
      expect(fatSkimmedOf(edited), isFalse);
      expect(browningFatLinesOf(edited), isEmpty);
    });
  }

  // `_panFactsOf`'s `discarded`: STATED synthesized on the REAL 0351 (the
  // v100 closer2 'pouredoff' form): its step 4 with 0142's real "Pour off
  // and discard fat in skillet." then 0351's own S1.2 garlic after the
  // lift-out — the fat discarded, |20 shallow; the pour-off negated ("Do not
  // pour off the fat in skillet.") discards nothing — the garlic reuses the
  // fat, |20 is the browning film, no shallow line.
  test('U5: a negated pour-off is not a discard (0351 |20)', () {
    final gravy = loadCorpusRecipe(
      '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml',
    );
    final s3 = gravy.steps[3].text;
    const lift =
        'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
    const garlic =
        'Stir in the garlic and cook until fragrant, about 30 seconds. ';
    expect(s3, contains(lift));
    expect(gravy.steps[1].text, contains(garlic.trim()));
    Recipe at(String pour) => gravy.copyWith(
      steps: [
        for (final (i, step) in gravy.steps.indexed)
          i == 3
              ? step.copyWith(
                  text: s3.replaceFirst(lift, '$lift$pour$garlic'),
                )
              : step,
      ],
    );
    expect(shallowFryLinesOf(at('Pour off and discard fat in skillet. ')), {
      20,
    });
    expect(shallowFryLinesOf(at('')), isEmpty);
    expect(
      shallowFryLinesOf(at('Do not pour off the fat in skillet. ')),
      isEmpty,
    );
  });
}

/// U6 (LOW; S-C1): v104 U2's cut set read four words, so a Granny Smith cup
/// "chopped" or "cut into 1-inch chunks" kept the SHREDDED 176.9 g/cup (2
/// cups 353.80 g; cubed 265.35 g). v105: "chopped" and "chunk(s)" join it.
/// "sliced" stays shredded (FDC 171688's slices portion is on no record on
/// disk — stated). Corpus reach 0: of the 16 Granny Smith rows on
/// v104_rows.tsv two read the density arm (the stuffing's cubed line and
/// strawberry jam's shredded cup). STATED synthesized re-texting of 0158's
/// real stuffing line 3 "2 Granny Smith apples, peeled, cored, and cut into
/// ½-inch cubes (about 2 cups)".
void u6() {
  const real =
      '2 Granny Smith apples, peeled, cored, and cut into ½-inch cubes (about 2 cups)';
  for (final (form, grams) in const [
    ('cut into ½-inch cubes', 265.35),
    ('chopped', 265.35),
    ('cut into 1-inch chunks', 265.35),
    ('cut into 1-inch chunk', 265.35),
    ('sliced', 353.80),
    ('shredded', 353.80),
  ]) {
    test('U6: "$form" (about 2 cups) weighs $grams g', () async {
      // The v103 U3 form: the real line, re-texted, its own recipe.
      final base = loadCorpusRecipe('0158-classic-roast-stuffed-turkey.yaml');
      final line = base.subsections.first.ingredients!
          .expand((g) => g.items)
          .singleWhere((l) => l.raw == real);
      final edited = line.copyWith(
        raw: real.replaceFirst('cut into ½-inch cubes', form),
      );
      final db = _db();
      final r = Recipe(
        id: 'u6',
        title: 'u6',
        slug: 'u6',
        source: const RecipeSource(name: 'ATK', type: 'epub'),
        ingredients: [
          IngredientGroup(items: [edited]),
        ],
      );
      db.upsertRecipe(r, sourceSlug: _source, contentHash: 'u6');
      expect(await matchAndCompute(db, _fx, r), isNull);
      final row = db.ingredientMatchesFor('u6').single;
      expect((row.fdcId, row.gramSource), (1750342, 'density'));
      expect(row.grams, closeTo(grams, 0.005));
      expect(
        gramBasisFor(db, edited, row),
        contains(
          grams == 265.35
              ? 'cut into ½-inch cubes = 4 cups'
              : 'shredded = 3 cups',
        ),
      );
    });
  }
}

/// U10 (LOW; O7): v104 U17 pinned `_inBatches`' word numbers in its SECOND
/// group only; the FIRST (the remaining-piece count) was unpinned. STATED
/// synthesized step (corpus reach 0; nearest corpus 0820's "remaining 8
/// sandwiches in 2 batches"): the word count reads the batch tail, 2
/// rounds (a mutant cutting the first group to digits falls back to 4).
void u10() {
  test("U10: _inBatches' remaining-piece word count reads the batch tail", () {
    expect(
      repeatRoundsForTest(
        'Repeat with remaining four sandwiches in 2 batches.',
      ).whereType<int>().toList(),
      [2],
    );
  });
}

/// U8 (LOW; S8): the apply-to-all's LINE-hold arm ([decidedKeyRowFor]) —
/// its failure is counted `unavailable` and the target left unweighed.
/// Under [onePass] the weigh above it asks every food that arm re-reads
/// (the same decision, cached or answered once), so no provider fault
/// alone reaches it: the arm's own reads differ only when the key's
/// decision moves during the weigh's await. STATED synthesized (negative
/// path: a second person's PUT racing the apply; no corpus run writes
/// one): paella-on-the-grill|14 "… littleneck clams, scrubbed" → 171977
/// applied onto cioppino|11 (bought in the shell, a line hold — v104 U7's
/// pair), 171977's detail cached; at the first turn after the PUT writes
/// the decision, the key's decision is re-put onto 167765 (Watermelon,
/// raw — on the fixtures, asked by no recipe here), whose detail FDC then
/// fails (FOOD). The apply's weigh reads its own `decided` food; only
/// [decidedKeyRowFor] re-reads the key's decision (mutants: its catch's
/// `unavailable += 0` → 0, `unweighed = false` → fresh).
void u8() {
  test('U8: the line-hold arm failing counts the target `unavailable` and '
      'leaves it unwritten, its recipe stale', () async {
    final db = _db();
    final source = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0106-paella-on-the-grill.yaml'),
    );
    final target = await _compute(
      db,
      _fx,
      loadCorpusRecipe('0108-cioppino.yaml'),
    );
    final key = _row(db, source.id, 14).itemKey!;
    final before = _row(db, target.id, 11);
    expect((before.fdcId, before.hold), (174214, null));
    // The decided record's detail cached, as snapshot 32 holds it (v104
    // U7's NoNet world): the weigh asks nothing.
    await cachedFood(db, _fx, 171977);
    final race = _Race();
    var turns = 0;
    var flipped = false;
    final applying = applyMatchOverride(db, race, source, 14, {
      'raw': nutritionLines(source)[14].raw,
      'fdc_id': 171977,
      'apply_to_all': true,
    });
    var done = false;
    unawaited(applying.whenComplete(() => done = true));
    while (!done && !flipped && turns < 100000) {
      turns++;
      await Future<void>.value();
      if (db.decisionFor(key)?.fdcId == 171977) {
        db.putDecision(
          itemKey: key,
          item: db.decisionFor(key)!.item,
          fdcId: 167765,
          description: 'Watermelon, raw',
          dataType: 'sr_legacy',
          decidedBy: null,
        );
        flipped = true;
      }
    }
    final result = await applying;
    expect(flipped, isTrue);
    // One request: the arm's own read of the re-put decision (base and
    // tip; the weigh reads 171977 from the cache).
    expect(race.asked, [167765]);
    expect(
      (result!.unavailable, result.lines, result.recipes, result.moved),
      (1, 0, 0, 0),
    );
    final after = _row(db, target.id, 11);
    expect(
      (after.fdcId, after.grams, after.hold, after.status),
      (before.fdcId, before.grams, before.hold, before.status),
    );
    expect(nutritionIsFresh(db, _stored(db, target.id)), isFalse);
    expect(_row(db, source.id, 14).fdcId, 171977);
  });
}

Recipe _stored(SaltDatabase db, String id) => nutritionRecipeOf(db, id)!.recipe;

/// [_fx], failing 167765 (FOOD) — [u8]'s race.
class _Race implements NutritionProvider {
  final asked = <int>[];
  @override
  Future<List<FdcCandidate>> search(String query) => _fx.search(query);

  @override
  Future<FdcFood?> food(int fdcId) async {
    asked.add(fdcId);
    if (fdcId == 167765) {
      throw const NutritionProviderException(
        'no 167765',
        scope: FailureScope.food,
      );
    }
    return _fx.food(fdcId);
  }
}
