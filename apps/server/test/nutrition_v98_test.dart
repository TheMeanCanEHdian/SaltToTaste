// Matcher v98 (the dual-fleet Run 071/072 fixes over the prep51 chain v83–v97;
// matcherVersion 92 UNCHANGED — no corpus row moves: the replay of snapshot
// 30 is byte-identical to the v97 set; zero requests; server only). The
// spec: .claude/diag/2026-10-31/review071/union_P.md (P1–P8 + RECORDED).
// P1 / P6: two hash terms (every line's `prep`; the sections' yields of a
// recipe holding a reference line) — every stamp stales once, no row moves. P2: `_repeatWith`'s
// count bounded (`\d{1,3}`), the fallback null-safe. P3: the matches GET
// plans M52 ONCE for any number of confirmed browning lines (the memo path
// shortcuts a browning line keyed alike), and `_m52Key` reads the browned
// food over `_brownedRecords` (the RECORDED gap). P8: `skinDiscarded`
// answered once per index and item (`skinScans`). P4: a counted repeat's
// rounds = N ÷ the first pass's count of its noun in the step (an "in M
// batches" tail = M). P5: the unpinned guards of v85 / v92 / v96, one STATED
// pin each. Every corpus line and step is real; STATED synthesized (named at
// each): a real line made amount-less, a real sentence with one word or
// count changed, a stored row written in a state a person path reaches, the
// cap shapes' repeated real lines. Figures from the recorded fixtures
// (FixtureProvider) — never the network.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_cost_test.dart' show fill;
import 'nutrition_v26_cost_test.dart' show capLines, capStep, capSteps, capped;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _tomatoSoup = '0014-creamless-creamy-tomato-soup.yaml';
const _gazpacho = '0032-creamy-gazpacho-andaluz.yaml';
const _friedRice = '0521-fried-rice-with-shrimp-pork-and-shiitakes.yaml';
const _friedRiceSection = 'Fried Rice with Peas and Bean Sprouts';
const _pizza = '0398-ultimate-grilled-pizza.yaml';
const _burgers = '0314-black-bean-burgers.yaml';
const _smashed = '0311-smashed-burgers.yaml';
const _chops = '0201-pan-seared-thick-cut-pork-chops.yaml';
const _shortRibs = '0087-braised-beef-short-ribs.yaml';
const _hearty = '0002-hearty-chicken-noodle-soup.yaml';
const _classic = '0002-classic-chicken-noodle-soup.yaml';
const _lamb =
    '1192-braised-lamb-shanks-with-red-wine-and-herbes-de-provence.yaml';

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v98-');
  final db = SaltDatabase.open(
    ServerConfig(
      dataDir: dir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    ).dbPath,
  )..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return db;
}

/// [r] stored and computed (its section children first).
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, fdc, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

IngredientMatchRow _rowIn(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

/// [r] with its line at [position] rebuilt by [edit] (every other line and
/// group as stored).
Recipe _withLine(
  Recipe r,
  int position,
  IngredientLine Function(IngredientLine) edit,
) {
  var k = 0;
  return r.copyWith(
    ingredients: [
      for (final g in r.ingredients)
        IngredientGroup(
          group: g.group,
          items: [for (final l in g.items) k++ == position ? edit(l) : l],
        ),
    ],
  );
}

void main() {
  test(
    'matcherVersion 95 — v98 bumped nothing (it kept 92: no corpus row moves; the two '
    'hash terms stale every stamp once)',
    () {
      // RE-PIN (M96 batch, v99): matcherVersion 93 (was 92).
      // RE-PIN (M97 batch, v100): matcherVersion 94 (was 93).
      // RE-PIN (fix101 batch, v101): matcherVersion 95 (was 94).
      expect(matcherVersion, 95);
    },
  );

  // P1 (MED; Sonnet S3 / S7 / S9, Opus O5): v84 C1b reads the structured
  // `prep` ([lineGrams]' `_crustsRemoved.hasMatch(line.prep ?? '')`), which
  // `ingredientsHashOf` never hashed — a prep-only edit (the editor's Prep
  // field: `_setStructured` sends the ORIGINAL raw with the new prep; the
  // API; a hand-edited YAML) left the stamp fresh while the recompute moved
  // the row. STATED synthesized: a real line with only its prep changed.
  // P6 (LOW; Sonnet S8): the subsections' `servings`, which the own-section
  // route reads (`_yieldTailOf`'s `atYield(sub.servings)`) — beside 0521's
  // standing reference line |9 (v91) a yield edit re-routing |10 flipped no
  // other term. Hashed under `references`, beside the titles (the reader is
  // reached only through `isReferenceIn` and the resolver's list; with no
  // reference line the routing edit flips `references` itself). STATED
  // synthesized: a real section's yield edited.
  group('P1 / P6 — the two hash terms', skip: skipIfNoCorpus, () {
    late final fdc = FixtureProvider(pending: {...pendingSearches});
    test('P1: a prep-only edit stales the stamp and the recompute moves the '
        'row — creamy-gazpacho-andaluz|7 18.77 → 45.36 g (334.73 → 352.41 '
        'kcal / serving; Opus O5), 0014|6 56.31 → 136.08 g (Sonnet S7); the '
        'controls: an identical upsert stays fresh, a raw-only and an '
        'item-only edit stale as before (mutant: the term removed — the hash '
        'equal, fresh true)', () async {
      for (final (file, position, prep, before, after, kcal) in [
        (
          _gazpacho,
          7,
          'torn into 1-inch pieces',
          '18.77',
          '45.36',
          ('334.73', '352.41'),
        ),
        (_tomatoSoup, 6, 'torn into 1-inch pieces', '56.31', '136.08', null),
      ]) {
        final db = _db();
        final reason = '$file|$position';
        final stored = await _compute(db, fdc, loadCorpusRecipe(file));
        final line = nutritionLines(stored)[position];
        expect(line.prep, contains('removed'), reason: reason);
        expect(
          _rowIn(db, stored.id, position).grams?.toStringAsFixed(2),
          before,
          reason: reason,
        );
        if (kcal != null) {
          expect(
            db.nutritionFor(stored.id)!.caloriesPerServing?.toStringAsFixed(2),
            kcal.$1,
            reason: reason,
          );
        }
        String hash(Recipe r) => ingredientsHashOf(r, ResolverMemo(db));
        // The controls: the same document hashes alike; raw and item were
        // terms before.
        expect(hash(stored), hash(loadCorpusRecipe(file)), reason: reason);
        for (final edit in <IngredientLine Function(IngredientLine)>[
          (l) => l.copyWith(raw: '${l.raw} '),
          (l) => l.copyWith(item: '${l.item} '),
        ]) {
          expect(
            hash(_withLine(stored, position, edit)),
            isNot(hash(stored)),
            reason: reason,
          );
        }
        final edited = _withLine(
          stored,
          position,
          (l) => l.copyWith(prep: prep),
        );
        expect(nutritionLines(edited)[position].raw, line.raw, reason: reason);
        expect(hash(edited), isNot(hash(stored)), reason: reason);
        db.upsertRecipe(edited, sourceSlug: _source, contentHash: 'v98-prep');
        final now = db.recipeByIdOrSlug(stored.id)!.recipe;
        expect(nutritionLines(now)[position].prep, prep, reason: reason);
        expect(nutritionIsFresh(db, now), isFalse, reason: reason);
        expect(await matchAndCompute(db, fdc, now), isNull);
        expect(
          _rowIn(db, stored.id, position).grams?.toStringAsFixed(2),
          after,
          reason: reason,
        );
        expect(nutritionIsFresh(db, now), isTrue, reason: reason);
        if (kcal != null) {
          expect(
            db.nutritionFor(stored.id)!.caloriesPerServing?.toStringAsFixed(2),
            kcal.$2,
            reason: reason,
          );
        }
      }
    });
    test(
      'P6: a section-yield edit stales the stamp WITH the standing '
      'reference line |9 (base: hash equal with |9, differing only without '
      'it — the pre-v91 behaviour) — 0521 "$_friedRiceSection" SERVES 4 TO '
      '6 → MAKES 1 cup; the recompute then re-routes |10 "1 cup bean '
      'sprouts" from FNDDS 2709768 90 g `portion` to its own section at '
      'share 1.0 (mutant: the term removed — the hash equal with |9)',
      () async {
        final db = _db();
        final base = loadCorpusRecipe(_friedRice);
        Recipe yieldEdit(Recipe r) => r.copyWith(
          subsections: [
            for (final s in r.subsections)
              s.title == _friedRiceSection
                  ? s.copyWith(servings: 'MAKES 1 cup')
                  : s,
          ],
        );
        expect(
          base.subsections
              .singleWhere((s) => s.title == _friedRiceSection)
              .servings,
          'SERVES 4 TO 6',
        );
        String hash(Recipe r) => ingredientsHashOf(r, ResolverMemo(db));
        final without9 = base.copyWith(
          ingredients: [
            for (final g in base.ingredients)
              g.copyWith(
                items: [
                  for (final l in g.items)
                    if (!l.raw.startsWith('5 cups cold cooked')) l,
                ],
              ),
          ],
        );
        expect(hash(yieldEdit(base)), isNot(hash(base)));
        expect(hash(yieldEdit(without9)), isNot(hash(without9)));
        final stored = await _compute(db, fdc, base);
        String row(int p) {
          final m = _rowIn(db, stored.id, p);
          return '${m.fdcId}|${m.childRecipeId}|${m.childShare}|${m.grams}|${m.gramSource}';
        }

        expect(row(10), '2709768|null|null|90.0|portion');
        db.upsertRecipe(
          yieldEdit(stored),
          sourceSlug: _source,
          contentHash: 'v98-yield',
        );
        final now = nutritionRecipeOf(db, stored.id)!.recipe;
        expect(nutritionIsFresh(db, now), isFalse);
        expect(await matchAndCompute(db, fdc, now), isNull);
        expect(
          row(10),
          'null|atk-tv-2023-0521-fried-rice-with-shrimp-pork-and-shiitakes#'
          '$_friedRiceSection|1.0|null|recipe',
        );
      },
    );
  });

  // P2 (MED; Sonnet S2 / S5, Opus critic 1): `_repeatWith` captured `\d+`
  // unbounded and `_repeatsOf` ended `int.tryParse(m[1]!) ??
  // _numberWords[m[1]!]!` — a 20-digit count threw out of the memoised
  // `_stepPrintsOf` (the whole compute failed, no rows / totals written;
  // `derivedFor` on a decided pizza|12 threw), 2^63 − 1 wrapped `1 + N`
  // (40.23 g silently), 1,000,000 read 13,411,681.25 g. v98: one to three
  // digits; the fallback null-safe. STATED synthesized: the pizza's REAL
  // step 9 sentence with its count changed.
  group('P2 — the repeat count bounded', skip: skipIfNoCorpus, () {
    const s9 =
        'Transfer pizza to cutting board; repeat with remaining 2 crusts.';
    test('the reader: 2 / "two" 2 and 999 999 (the cap; no corpus count '
        'exceeds 8, `_counted`), and 1000, 1000000, 2^63 − 1 and a 20-digit '
        'run no count — null, never a throw (mutant: `{1,3}` → `+` reads '
        '1000000)', () {
      expect(
        nutritionLines(loadCorpusRecipe(_pizza))[12].raw,
        'Extra-virgin olive oil',
      );
      expect(
        loadCorpusRecipe(_pizza).steps[8].text,
        contains(s9),
      );
      for (final (n, expected) in <(String, int?)>[
        ('2', 2),
        ('two', 2),
        ('999', 999),
        ('1000', null),
        ('1000000', null),
        ('9223372036854775807', null),
        ('99999999999999999999', null),
      ]) {
        expect(
          repeatsOfForTest(s9.replaceFirst('2 crusts', '$n crusts')),
          expected,
          reason: n,
        );
      }
    });
    test('the whole compute: a 20-digit count on pizza step 9 completes — '
        'row 12 53.65 g `portion` (step 9 read × 1 with no counted repeat, '
        'as v92\'s "clause (2) dropped" mutant read), 919.15 kcal / serving; '
        'the real "2 crusts" 80.47 g, 978.43 (the v92 pin); `derivedFor` on '
        'pizza|12 confirmed throws nothing', () async {
      final fdc = FixtureProvider(pending: {...pendingSearches});
      for (final (n, grams, kcal) in const [
        ('2', '80.47', '978.43'),
        ('99999999999999999999', '53.65', '919.15'),
        ('9223372036854775807', '53.65', '919.15'),
      ]) {
        final db = _db();
        final base = loadCorpusRecipe(_pizza);
        final r = base.copyWith(
          id: '${base.id}-v98-$n',
          slug: '${base.slug}-v98-$n',
          steps: [
            for (final s in base.steps)
              s.copyWith(
                text: s.text.replaceAll(
                  'remaining 2 crusts',
                  'remaining $n crusts',
                ),
              ),
          ],
        );
        final stored = await _compute(db, fdc, r);
        final row = _rowIn(db, stored.id, 12);
        expect(
          (row.grams?.toStringAsFixed(2), row.gramSource),
          (grams, 'portion'),
          reason: n,
        );
        expect(
          db.nutritionFor(stored.id)!.caloriesPerServing?.toStringAsFixed(2),
          kcal,
          reason: n,
        );
        final derived = await derivedFor(
          db,
          fdc,
          stored,
          12,
          nutritionLines(stored)[12],
          row.copyWith(status: 'confirmed'),
        );
        expect(derived.row.grams?.toStringAsFixed(2), grams, reason: n);
      }
    });
  });

  // P3 (MED; Sonnet S4, Opus O2) + the RECORDED `_m52Key` gap (Opus critics
  // 2 / 3): v96 put `_browningFatAt` in derivedFor's Confirm arm, so every
  // CONFIRMED browning row reached `_m52OnConfirm`, whose memo path
  // shortcut only `sameMatchRow` or a coat keyed alike — a line the
  // per-line rule leaves WHOLE is stored on its engine source (`portion`),
  // never the confirm's `discarded`, so the GET ran a full `_m52Plan` per
  // row (400 plans, 320,001 food reads, 13.9 s at the caps; f912190 0
  // plans in ~1 s). v98: such a row, keyed alike in O(1) (`_m52KeysAlike`,
  // which now keys a browning line as `_m52Key` does), takes the request's
  // plan; and the key reads the browned food over `_brownedRecords`.
  group(
    'P3 — one plan a GET for confirmed browning lines',
    skip: skipIfNoCorpus,
    () {
      late final fdc = FixtureProvider(
        pending: {...pendingSearches, 'thyme or dried'},
      );
      test('the real corpus: classic-chicken-noodle-soup|0 "1 tablespoon '
          'vegetable oil" (a browning line left whole) confirmed through the '
          'PUT — the GET plans ONCE (base bdd0c5e: 2) and serves the stored '
          'row, 14.00 g `portion`', () async {
        final db = _db();
        final recipe = await _compute(db, fdc, loadCorpusRecipe(_classic));
        expect(browningFatLinesOf(recipe), {0});
        await applyMatchOverride(db, fdc, recipe, 0, {
          'raw': nutritionLines(recipe)[0].raw,
          'confirmed': true,
        });
        final stored = _rowIn(db, recipe.id, 0);
        expect(
          (stored.status, stored.grams?.toStringAsFixed(2), stored.gramSource),
          ('confirmed', '14.00', 'portion'),
        );
        m52PlanRuns = 0;
        final item =
            ((await matchesBody(db, fdc, recipe))['items']! as List)
                    .cast<Map<String, Object?>>()
                    .singleWhere((i) => i['position'] == 0)['match']!
                as Map<String, Object?>;
        expect(m52PlanRuns, 1);
        expect(
          (
            item['status'],
            (item['grams'] as num?)?.toStringAsFixed(2),
            item['gram_source'],
          ),
          ('confirmed', '14.00', 'portion'),
        );
      });
      test(
        'the key reads the browned food over `_brownedRecords` (the RECORDED '
        'gap): braised-lamb-shanks|0 on SR 172513 "Lamb, …" browns |2\'s oil — '
        'its grams doubled move the key (base: alike, the coated food read '
        '`_meatRecords` only; mutants: the write dropped, the four heads '
        'dropped from it)',
        () async {
          final db = _db();
          final recipe = await _compute(db, fdc, loadCorpusRecipe(_lamb));
          expect(browningFatLinesOf(recipe), {2});
          final rows = db.ingredientMatchesFor(recipe.id);
          final shanks = rows.singleWhere((m) => m.position == 0);
          expect(
            (shanks.fdcId, shanks.description),
            (
              172513,
              'Lamb, New Zealand, imported, fore-shank, separable lean and fat, raw',
            ),
          );
          expect(_rowIn(db, recipe.id, 2).grams?.toStringAsFixed(2), '25.33');
          final doubled = [
            for (final r in rows)
              r.position == 0 ? r.copyWith(grams: r.grams! * 2) : r,
          ];
          expect(m52KeyOf(recipe, doubled), isNot(m52KeyOf(recipe, rows)));
        },
      );
    },
  );

  // The new arm's gates, each on a STATED synthesized stored state (the row a
  // person path leaves when the steps change after the decision — written
  // here directly, as v26's cap shapes write their 398 confirms): the GET
  // (one request memo) must serve what a derivation with no memo plans, and
  // a gate that refuses plans the row's own list (`m52PlanRuns` 2).
  group("P3 — the browning arm's gates", skip: skipIfNoCorpus, () {
    late final fdc = FixtureProvider(
      pending: {...pendingSearches, 'thyme or dried'},
    );
    Future<(String?, String?, int)> getForm(
      SaltDatabase db,
      Recipe recipe,
      int position,
    ) async {
      m52PlanRuns = 0;
      final item =
          ((await matchesBody(db, fdc, recipe))['items']! as List)
                  .cast<Map<String, Object?>>()
                  .singleWhere((i) => i['position'] == position)['match']!
              as Map<String, Object?>;
      return (
        (item['grams'] as num?)?.toStringAsFixed(2),
        item['gram_source'] as String?,
        m52PlanRuns,
      );
    }

    Future<(String?, String?)> derivedForm(
      SaltDatabase db,
      Recipe recipe,
      int position,
    ) async {
      final d = (await derivedFor(
        db,
        fdc,
        recipe,
        position,
        nutritionLines(recipe)[position],
        _rowIn(db, recipe.id, position),
      )).row;
      return (d.grams?.toStringAsFixed(2), d.gramSource);
    }

    test(
      'its own hold exactly: short-ribs|2 (planned 24.12 g) stored '
      'confirmed but held `coating` — the key reads none-or-`coating` '
      "alike, the browning arm skips a held row — the GET plans the row's "
      'own list and serves 24.12 g `discarded`, as the derivation does '
      "(mutant: `row.hold == null` dropped → the stored plan's no entry)",
      () async {
        final db = _db();
        final recipe = await _compute(db, fdc, loadCorpusRecipe(_shortRibs));
        expect(browningFatLinesOf(recipe), contains(2));
        final row = _rowIn(db, recipe.id, 2);
        expect(
          (row.grams?.toStringAsFixed(2), row.gramSource),
          ('24.12', 'discarded'),
        );
        db.upsertIngredientMatch(
          row.copyWith(status: 'confirmed', hold: 'coating'),
        );
        expect(await derivedForm(db, recipe, 2), ('24.12', 'discarded'));
        expect(await getForm(db, recipe, 2), ('24.12', 'discarded', 2));
      },
    );
    test('never a frying oil: 0317 easier-french-fries with a real-style '
        '"Skim the fat from the liquid." appended (its |1 "6 cups peanut '
        'oil", a frying oil, then a browning line too), |1 stored confirmed '
        '`portion` (as a confirm before a steps edit leaves it) — the GET '
        "plans its own list and serves the fryer's 136.62 g `discarded`, "
        'as the derivation does (mutant: the frying-oil gate dropped → the '
        'stored plan, no fryer entry)', () async {
      final db = _db();
      final corpus = loadCorpusRecipe('0317-easier-french-fries.yaml');
      final recipe = await _compute(
        db,
        fdc,
        corpus.copyWith(
          id: '${corpus.id}-v98-skim',
          slug: '${corpus.slug}-v98-skim',
          steps: [
            ...corpus.steps,
            corpus.steps.last.copyWith(
              number: corpus.steps.length + 1,
              text: 'Skim the fat from the liquid.',
            ),
          ],
        ),
      );
      expect(browningFatLinesOf(recipe), contains(1));
      final row = _rowIn(db, recipe.id, 1);
      expect(
        (row.grams?.toStringAsFixed(2), row.gramSource),
        ('136.62', 'discarded'),
      );
      db.upsertIngredientMatch(
        row.copyWith(status: 'confirmed', gramSource: 'portion'),
      );
      expect(await derivedForm(db, recipe, 1), ('136.62', 'discarded'));
      expect(await getForm(db, recipe, 1), ('136.62', 'discarded', 2));
    });
    test('a browning line only: an amount edit carries each confirmed pan row '
        '(STATED: "4 tablespoons" → "5 tablespoons", "2" → "3", the row '
        'stored on the old text, `discarded`, laid by its item key) — '
        'chicken-saltimbocca|5 (C4 and browning: the C4 entry wins, read '
        'alike) takes the arm, the GET planning once; 0420 chicken-francese|13 '
        '(C4, no browning line) does not — the GET plans its own list (2; '
        "mutant: `_browningFatAt` dropped → 1); both serve the derivation's "
        'grams', () async {
      for (final (file, position, from, to, browning, grams, plans) in [
        (
          '0421-chicken-saltimbocca.yaml',
          5,
          '4 tablespoons',
          '5 tablespoons',
          true,
          '23.14',
          1,
        ),
        (
          '0420-chicken-francese.yaml',
          13,
          '2 tablespoons',
          '3 tablespoons',
          false,
          '14.95',
          2,
        ),
      ]) {
        final db = _db();
        final recipe = await _compute(db, fdc, loadCorpusRecipe(file));
        final reason = '$file|$position';
        expect(panFatLinesOf(recipe), contains(position), reason: reason);
        expect(
          browningFatLinesOf(recipe).contains(position),
          browning,
          reason: reason,
        );
        await applyMatchOverride(db, fdc, recipe, position, {
          'raw': nutritionLines(recipe)[position].raw,
          'confirmed': true,
        });
        expect(
          _rowIn(db, recipe.id, position).gramSource,
          'discarded',
          reason: reason,
        );
        final edited = _withLine(
          recipe,
          position,
          (l) {
            // The editor's own re-parse of an edited line.
            final raw = l.raw.replaceFirst(from, to);
            final parsed = parseIngredientLine(raw);
            return IngredientLine(
              raw: raw,
              item: parsed.item,
              prep: parsed.prep,
              amounts: parsed.amounts,
            );
          },
        );
        expect(
          nutritionLines(edited)[position].raw,
          isNot(nutritionLines(recipe)[position].raw),
          reason: reason,
        );
        db.upsertRecipe(edited, sourceSlug: _source, contentHash: 'v98-amount');
        final now = db.recipeByIdOrSlug(recipe.id)!.recipe;
        expect(
          nutritionLines(now)[position].amounts,
          isNotEmpty,
          reason: reason,
        );
        final derived = await derivedForm(db, now, position);
        final got = await getForm(db, now, position);
        expect(derived, (grams, 'discarded'), reason: reason);
        expect((got.$1, got.$2), derived, reason: reason);
        expect(got.$3, plans, reason: reason);
      }
    });
    test('a browned food at the line keys apart: braised-lamb-shanks|2 '
        'stored confirmed on the shanks\' own record 172513 ("Lamb, …") at '
        '5,000 g — counted, it is the browned food of the stored list, '
        "never of the confirm's — so `_m52KeysAlike` refuses (its guard "
        "over `_brownedRecords`) and the GET plans the row's own list (2; "
        'mutant: the guard back to `_meatRecords` → 1); the line keeps no '
        'entry either way (its own record weighs it whole)', () async {
      final db = _db();
      final recipe = await _compute(db, fdc, loadCorpusRecipe(_lamb));
      final shanks = _rowIn(db, recipe.id, 0);
      final row = _rowIn(db, recipe.id, 2);
      db.upsertIngredientMatch(
        row.copyWith(
          status: 'confirmed',
          fdcId: shanks.fdcId,
          description: shanks.description,
          grams: 5000,
          gramSource: 'portion',
        ),
      );
      final derived = await derivedForm(db, recipe, 2);
      final got = await getForm(db, recipe, 2);
      expect(derived, ('27.21', 'density'));
      expect((got.$1, got.$2), derived);
      expect(got.$3, 2);
    });
  });

  // P3's cap shape (Opus O2's, STATED: the cap-shape exception) —
  // braised-beef-short-ribs' REAL meat line |0 and 399 copies of
  // hearty-chicken-noodle-soup|0's REAL "1 tablespoon vegetable oil" under
  // 120 × 10,000-character steps heating the oil, the last skimming the fat:
  // every oil line a browning line the per-line rule leaves WHOLE (kept =
  // 0.015195 × 1,587.57 / 14 ≈ 1.72 ≥ 1: 14.00 g `portion`, no plan entry);
  // row 1 confirmed through the real PUT, the other 398 written confirmed as
  // v26's fryingOils / cutDough shapes write them. Base bdd0c5e: the GET ran
  // `_m52Plan` 400 times, 320,001 food reads, 13.9 s here (the fleets
  // 14–19 s). The CONTROL: "2 tablespoons vegetable oil" (0087|2's real
  // line), every line planned 24.12 g `discarded` — one plan on both trees.
  // Counts the tree's, EXACTLY.
  group(
    'RULE C, the confirmed browning lines at the caps (P3)',
    skip: skipIfNoCorpus,
    () {
      for (final (shape, oil, grams, source, getReads) in const [
        ('WHOLE', '1 tablespoon vegetable oil', '14.00', 'portion', 1599),
        ('PLANNED', '2 tablespoons vegetable oil', '24.12', 'discarded', 1200),
      ]) {
        test('$shape: 399 confirmed "$oil" rows — the GET plans ONCE '
            '(m52PlanRuns 1, knownFoodReads $getReads), the compute twice and '
            'the recompute once; the GET serves the stored rows; each under the '
            'backstop', () async {
          final base = loadCorpusRecipe(_shortRibs);
          const meat =
              '3½ pounds boneless beef short ribs, trimmed of excess fat';
          expect(nutritionLines(base)[0].raw, meat);
          expect(
            nutritionLines(
              loadCorpusRecipe(shape == 'WHOLE' ? _hearty : _shortRibs),
            )[shape == 'WHOLE' ? 0 : 2].raw,
            oil,
          );
          final r = capped(
            base,
            [meat, for (var i = 1; i < capLines; i++) oil],
            [
              for (var i = 0; i < capSteps; i++)
                fill(
                  i == capSteps - 1
                      ? 'Skim the fat from the liquid. '
                      : 'Heat the oil in a Dutch oven. ',
                  capStep,
                ),
            ],
          );
          final db = wp.tempDb();
          final provider = FixtureProvider(pending: pendingSearches);
          wp.saveRecipe(db, r);
          Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
          expect(await matchAndCompute(db, provider, stored()), isNull);
          final rows = db.ingredientMatchesFor(r.id);
          expect(
            {
              for (final m in rows.skip(1))
                (m.grams?.toStringAsFixed(2), m.gramSource),
            },
            {(grams, source)},
          );
          await applyMatchOverride(db, provider, stored(), 1, {
            'raw': rows[1].raw,
            'confirmed': true,
          });
          final put = db.ingredientMatchesFor(r.id);
          for (final row in put.skip(2)) {
            db.upsertIngredientMatch(
              row.copyWith(status: 'confirmed', derivedSeq: put[1].derivedSeq),
            );
          }
          for (final (step, plans, reads, keys) in [
            ('GET', 1, getReads, 1),
            ('compute', 2, 2394, 399),
            ('recompute', 1, 1198, null),
          ]) {
            stepIndexCounts.clear();
            m52PlanRuns = 0;
            knownFoodReads = 0;
            final sw = Stopwatch()..start();
            final out = switch (step) {
              'GET' => await matchesBody(db, provider, stored()),
              'compute' => await matchAndCompute(db, provider, stored()),
              _ => recomputeTotals(db, stored()),
            };
            final ms = sw.elapsedMilliseconds;
            final counts = Map.of(stepIndexCounts)..remove('names');
            expectBounded(
              r,
              counts,
              '$shape $step',
              copies: counts['indexes'] ?? 1,
            );
            expect(
              (m52PlanRuns, knownFoodReads, counts['m52Keys']),
              (plans, reads, keys),
              reason: '$shape $step',
            );
            expect(ms, lessThan(backstopMs), reason: '$shape $step');
            if (out is Map<String, Object?>) {
              final items = (out['items']! as List)
                  .cast<Map<String, Object?>>();
              expect(
                {
                  for (final item in items.skip(1))
                    (
                      (item['match']! as Map)['status'],
                      ((item['match']! as Map)['grams'] as num?)
                          ?.toStringAsFixed(2),
                      (item['match']! as Map)['gram_source'],
                    ),
                },
                {('confirmed', grams, source)},
                reason: shape,
              );
            }
          }
          expect(
            {
              for (final m in db.ingredientMatchesFor(r.id).skip(1))
                (m.status, m.grams?.toStringAsFixed(2), m.gramSource),
            },
            {('confirmed', grams, source)},
          );
        }, timeout: const Timeout(Duration(minutes: 5)));
      }
    },
  );

  // P8 (LOW; Opus O3): v96's `_browningFatPlan` weighs each browning line
  // (`lineGrams`) per plan pass, and `lineGrams` asks `skinDiscarded`, which
  // scanned every skin sentence on every call, UNCOUNTED — at f912190 the
  // recompute made no such weighing. v98: the answer once per index and item
  // (in `#skinSentences`' own memo), each scan counted (`skinScans`). STATED:
  // v96's TRUE shape (0087's REAL meat line |0 and 399 copies of its REAL "2
  // tablespoons vegetable oil", 120 × 10,000-character steps, the last
  // skimming the fat) with one skin-trip sentence a chunk ("Remove the skin
  // from the chicken thighs and discard."). Base bdd0c5e here: compute
  // 14,177 ms, GET 5,326, recompute 4,703 (Opus: 4.7–6.0 s, 14 × f912190's
  // 320–414 ms); the tree 1,154 / 1,009 / 431. Counts the tree's, EXACTLY.
  group(
    'RULE C, the skin scans under the browning plan (P8)',
    skip: skipIfNoCorpus,
    () {
      test('SKIN: the skin sentences scanned once per item (2 a compute and a '
          'GET, 1 a recompute), the oils 24.12 g `discarded`, each under the '
          'backstop', () async {
        final base = loadCorpusRecipe(_shortRibs);
        const meat =
            '3½ pounds boneless beef short ribs, trimmed of excess fat';
        const oil = '2 tablespoons vegetable oil';
        expect(nutritionLines(base)[0].raw, meat);
        expect(nutritionLines(base)[2].raw, oil);
        final r = capped(
          base,
          [meat, for (var i = 1; i < capLines; i++) oil],
          [
            for (var i = 0; i < capSteps; i++)
              fill(
                i == capSteps - 1
                    ? 'Skim the fat from the liquid. '
                    : 'Heat the oil in a Dutch oven. Remove the skin from the '
                          'chicken thighs and discard. ',
                capStep,
              ),
          ],
        );
        final db = wp.tempDb();
        final provider = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, r);
        Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
        for (final (step, run) in <(String, Future<Object?> Function())>[
          ('compute', () => matchAndCompute(db, provider, stored())),
          ('GET', () => matchesBody(db, provider, stored())),
          ('recompute', () async => recomputeTotals(db, stored())),
        ]) {
          stepIndexCounts.clear();
          final sw = Stopwatch()..start();
          await run();
          final ms = sw.elapsedMilliseconds;
          final counts = Map.of(stepIndexCounts)..remove('names');
          expectBounded(r, counts, 'SKIN $step');
          expect(counts, _skinCounts[step], reason: 'SKIN $step');
          expect(ms, lessThan(backstopMs), reason: 'SKIN $step');
        }
        expect(
          {
            for (final m in db.ingredientMatchesFor(r.id).skip(1))
              (m.grams?.toStringAsFixed(2), m.gramSource),
          },
          {('24.12', 'discarded')},
        );
      }, timeout: const Timeout(Duration(minutes: 3)));
    },
  );

  // P4 (LOW; Sonnet S1, Opus O1): v92's counted repeat multiplied by N
  // PIECES, which is N rounds only when each piece is its own round (the
  // pizza) — a batch of several pieces repeated once over-counted 1.5–2×.
  // v98: rounds = ceil(N ÷ the nearest count of the same piece noun in an
  // earlier sentence of the step — the pass it repeats); an "in M batches"
  // tail = M; none → N. No corpus row moves (every corpus line the steps
  // print carries its amount; pizza|12 keeps 80.47 g — its rounds 2 and 2).
  // STATED synthesized (the fleets' probes): a real line made amount-less
  // (raw, item and amounts replaced; every sentence real).
  group("P4 — a counted repeat's rounds", skip: skipIfNoCorpus, () {
    GramResolution? amountless(String file, int position, String raw) {
      final r = _withLine(
        loadCorpusRecipe(file),
        position,
        (l) => IngredientLine(raw: raw, item: raw),
      );
      final line = nutritionLines(r)[position];
      expect(line.amounts, isEmpty);
      return stepAmountGrams(r, line, null, normalizeItem(raw));
    }

    test('the batch phrasing reads its rounds — 0314|12 "8 teaspoons '
        'vegetable oil" made amount-less: "4 teaspoons × 2" = 8 tsp, 36.28 g '
        '(base 16 tsp, 72.55 g — the recipe prints 8); 0311|9 kosher salt ⅛ '
        'teaspoon × 2 = ¼ tsp, 0.75 g (base × 3, 1.12 g — prints ¼); 0201|2 '
        '"1 tablespoon × 2", 27.21 g (base × 3, 40.81 g — prints 1–2) '
        '(mutant: the divide dropped → base)', () {
      expect(
        nutritionLines(loadCorpusRecipe(_burgers))[12].raw,
        '8 teaspoons vegetable oil',
      );
      expect(
        nutritionLines(loadCorpusRecipe(_smashed))[9].raw,
        '¼ teaspoon kosher salt, divided',
      );
      expect(
        nutritionLines(loadCorpusRecipe(_chops))[2].raw,
        '1–2 tablespoons vegetable oil',
      );
      for (final (file, position, raw, grams, basis) in const [
        (
          _burgers,
          12,
          'Vegetable oil',
          '36.28',
          'from step 5: 4 teaspoons × 2 (the 2 teaspoons + 2 teaspoons base '
              'left; no amount on the line)',
        ),
        (
          _smashed,
          9,
          'Kosher salt',
          '0.75',
          'from step 3: ⅛ teaspoon × 2 (no amount on the line)',
        ),
        (
          _chops,
          2,
          'Vegetable oil',
          '27.21',
          'from step 3: 1 tablespoon × 2 (no amount on the line)',
        ),
      ]) {
        final g = amountless(file, position, raw);
        expect(
          (g?.grams.toStringAsFixed(2), g?.basis),
          (grams, basis),
          reason: '$file|$position',
        );
      }
    });
    test("the corpus census: every counted repeat's rounds (v92's 22 "
        'sentences, `_counted`: N unchanged) — one piece a round keeps N (the '
        "pizza's 2 and 2, 0198's 7 chops), a batch of N one round, 0820's "
        '"in 2 batches" 2', () {
      final hits = <String>[];
      for (final file
          in Directory(corpusRecipesDir)
              .listSync()
              .map((f) => f.uri.pathSegments.last)
              .where((f) => f.endsWith('.yaml'))
              .toList()
            ..sort()) {
        final r = loadCorpusRecipe(file);
        for (final (label, steps) in [
          (file, r.steps),
          for (final s in r.subsections)
            ('$file|${s.title}', s.steps ?? const <RecipeStep>[]),
        ]) {
          for (final (k, step) in steps.indexed) {
            final rounds = repeatRoundsForTest(step.text);
            for (final (j, n) in rounds.indexed) {
              if (n != null) {
                final sentence = step.text.toLowerCase().split(
                  RegExp(r'(?<=\.)\s+'),
                )[j];
                hits.add('$label|${k + 1}: ${repeatsOfForTest(sentence)} → $n');
              }
            }
          }
        }
      }
      expect(hits, _rounds);
    });
    test('STATED: the NEAREST earlier count, rounded up — 0041 step 2 with '
        '"Transfer 6 pieces" read as "Transfer 4 pieces": ceil(6 ÷ 4) = 2 '
        '(mutants: the first count, "12 equal pieces", → 1; floor → 1)', () {
      final step = loadCorpusRecipe(
        '0041-salad-with-herbed-baked-goat-cheese-and-vinaigrette.yaml',
      ).steps[1].text;
      expect(step, contains('into 12 equal pieces'));
      expect(step, contains('Transfer 6 pieces'));
      expect(repeatRoundsForTest(step).whereType<int>(), [1]);
      expect(
        repeatRoundsForTest(
          step.replaceFirst('Transfer 6 pieces', 'Transfer 4 pieces'),
        ).whereType<int>(),
        [2],
      );
    });
  });

  // P5 (LOW; Sonnet S6, Opus O4): the guards of v85 / v92 / v96 that no pin
  // proved — each mutant left the full corpus suite green, and two of v96's
  // four C4-copied plan guards are NOT equivalent off the corpus (the v96
  // commit called all four EQUIVALENT). ONE STATED synthesized pin each: a
  // real recipe with one real sentence's word or count changed, one answer of
  // the fixtures replaced, or one stored row written in a person path's
  // state — each named, each proven by its own mutant.
  group('P5 — the unpinned guards', skip: skipIfNoCorpus, () {
    late final fdc = FixtureProvider(
      pending: {...pendingSearches, 'thyme or dried'},
    );
    Recipe rewrite(String file, String from, String to) {
      final r = loadCorpusRecipe(file);
      var hits = 0;
      final steps = [
        for (final s in r.steps)
          s.text.contains(from)
              ? (() {
                  hits++;
                  return s.copyWith(text: s.text.replaceFirst(from, to));
                })()
              : s,
      ];
      expect(hits, 1, reason: from);
      return r.copyWith(
        id: '${r.id}-v98-p5',
        slug: '${r.slug}-v98-p5',
        steps: steps,
      );
    }

    test('(a) the number words "one" and "four" count — the pizza\'s step 9 '
        '"remaining 2 crusts" read "one crust" 1 and "four crusts" 4 '
        '(mutants: either word dropped from `_repeatWith` → null)', () {
      const s9 =
          'Transfer pizza to cutting board; repeat with remaining 2 crusts.';
      expect(repeatsOfForTest(s9.replaceFirst('2 crusts', 'one crust')), 1);
      expect(repeatsOfForTest(s9.replaceFirst('2 crusts', 'four crusts')), 4);
    });
    test("(b) a pour-off of GREASE triggers as of fat — maple|11's only "
        'trigger "Pour off the fat from the skillet …" read "Pour off the '
        'grease …": |11 still a browning line (mutant: the `grease` prefilter '
        'dropped → none)', () {
      final r = rewrite(
        '0235-maple-glazed-pork-tenderloin.yaml',
        'Pour off the fat from the skillet',
        'Pour off the grease from the skillet',
      );
      expect(browningFatLinesOf(r), contains(11));
    });
    test(
      '(c) "pour off all EXCEPT …" keeps a part, as "all but" does — '
      'maple|11\'s only trigger "Pour off the fat from the skillet …" read '
      '"Pour off all except 1 tablespoon fat from the skillet …" (and, the '
      'control, "all but"): no trigger, |11 no browning line (mutant: the '
      '`except` prefilter dropped → the except form triggers, |11 admitted)',
      () {
        for (final word in ['except', 'but']) {
          final r = rewrite(
            '0235-maple-glazed-pork-tenderloin.yaml',
            'Pour off the fat from the skillet',
            'Pour off all $word 1 tablespoon fat from the skillet',
          );
          expect(browningFatLinesOf(r), isNot(contains(11)), reason: word);
        }
      },
    );
    test('(e) a "repeat with" sentence heats the fat only as a counted repeat '
        '— 0087 S1 "Repeat with the remaining 1 tablespoon oil and the '
        'remaining meat." read with no count ("the remaining oil"): a mention '
        'outside a heat sentence, |2 none (mutant: `&&` → `||`, the substring '
        'alone → |2 admitted)', () {
      expect(browningFatLinesOf(loadCorpusRecipe(_shortRibs)), contains(2));
      final r = rewrite(
        _shortRibs,
        'Repeat with the remaining 1 tablespoon oil and the remaining meat.',
        'Repeat with the remaining oil and the remaining meat.',
      );
      expect(browningFatLinesOf(r), isNot(contains(2)));
    });
    test('(d) / (g) the per-serving arm (classic-gazpacho|10, "drizzling each '
        'portion with about 1 teaspoon olive oil"): a recipe serving ONE counts '
        '× 1 (mutant: `serves < 1` → `<= 1` refuses); a "with about" farther '
        'than the 24-character window before the print reads nothing (15 '
        'spaces after "about" none, 14 × 8: mutant `- 24` → `- 25` reads the '
        '15 × 8)', () async {
      final db = _db();
      final food = (await FixtureProvider().food(748608))!;
      Future<(String, String?)?> read(Recipe r) async {
        final line = nutritionLines(r)[10];
        expect(line.raw, 'Extra-virgin olive oil, for serving');
        final g = lineGrams(db, line, food, recipe: r);
        return g == null ? null : (g.grams.toStringAsFixed(2), g.basis);
      }

      final gazpacho = loadCorpusRecipe('0031-classic-gazpacho.yaml');
      expect(gazpacho.serves?.min, 8);
      expect(
        await read(gazpacho.copyWith(serves: const Serves(min: 1, max: 1))),
        (
          '4.47',
          'from step 2: about 1 teaspoon × 1 portions (no amount on the line)',
        ),
      );
      // The window's edge: "with" 24 characters before the print (14 spaces
      // after "about") is read, 25 (15 spaces) is not.
      for (final (spaces, expected) in [
        (
          14,
          (
            '35.76',
            'from step 2: about${' ' * 14}1 teaspoon × 8 portions (no amount '
                'on the line)',
          ),
        ),
        (15, null),
      ]) {
        expect(
          await read(
            rewrite(
              '0031-classic-gazpacho.yaml',
              'with about 1 teaspoon olive oil',
              'with about${' ' * spaces}1 teaspoon olive oil',
            ),
          ),
          expected,
          reason: '$spaces spaces',
        );
      }
    });
    test(
      "(f) the browned food on a veal, duck or game record — 0087|0's "
      'stored row read on "Veal, …" / "Duck, …" / "Game meat, …" '
      '(STATED: its description alone; the record id kept): a recompute '
      'keeps |2 at 24.12 g `discarded` (mutants: each head dropped from '
      '`_brownedRecords` → no browned food, |2 back to 28.00 g `portion`)',
      () async {
        for (final head in ['Veal, ', 'Duck, ', 'Game meat, ']) {
          final db = _db();
          final recipe = await _compute(db, fdc, loadCorpusRecipe(_shortRibs));
          final ribs = _rowIn(db, recipe.id, 0);
          expect(ribs.description, startsWith('Beef, '), reason: head);
          db.upsertIngredientMatch(
            ribs.copyWith(
              description: '$head${ribs.description!.substring(6)}',
            ),
          );
          recomputeTotals(db, recipe);
          final row = _rowIn(db, recipe.id, 2);
          expect(
            (row.grams?.toStringAsFixed(2), row.gramSource),
            ('24.12', 'discarded'),
            reason: head,
          );
        }
      },
    );
  });

  // P5, v96's four C4-copied guards of `_browningFatPlan` (Opus O4; the v96
  // commit's "EQUIVALENT" was so on the corpus replay alone): each on 0087's
  // REAL rows with one STATED change.
  group("P5 — the browning plan's four guards", skip: skipIfNoCorpus, () {
    Future<(SaltDatabase, Recipe)> computed(
      NutritionProvider p,
      Recipe r,
    ) async {
      final db = _db();
      return (db, await _compute(db, p, r));
    }

    test(
      "`_m52Engine`: the oil's search answered with NO hits (an FDC miss "
      'or outage: `unmatched`, no record) — the compute completes, |2 '
      'unmatched (mutant: the guard dropped → `food(r.fdcId!, …)` throws '
      '"Null check operator used on a null value", no rows written)',
      () async {
        final (db, recipe) = await computed(
          _OilAs(null),
          loadCorpusRecipe(_shortRibs),
        );
        expect(browningFatLinesOf(recipe), contains(2));
        final row = _rowIn(db, recipe.id, 2);
        expect((row.status, row.fdcId), ('unmatched', null));
      },
    );
    test('below the gate: the oil answered by the fixtures\' "bacon fat" hits '
        '(confidence below 0.5) — |2 keeps its engine row, 27.21 g `density` '
        '(mutant: the guard dropped → the plan writes 24.24 g `discarded` '
        'with the browning basis)', () async {
      final (db, recipe) = await computed(
        _OilAs('bacon fat'),
        loadCorpusRecipe(_shortRibs),
      );
      final row = _rowIn(db, recipe.id, 2);
      expect(belowConfidenceGate(row.confidence), isTrue);
      expect(
        (row.grams?.toStringAsFixed(2), row.gramSource),
        ('27.21', 'density'),
      );
    });
    test('a held row: |2 (planned 24.12 g) stored held `partial_pour_away` '
        '(STATED) — a recompute keeps it held, out of the totals: 612.07 kcal '
        '/ serving (mutant: the hold guard dropped → the plan writes it back, '
        'unheld, 648.25)', () async {
      final fdc = FixtureProvider(
        pending: {...pendingSearches, 'thyme or dried'},
      );
      final (db, recipe) = await computed(fdc, loadCorpusRecipe(_shortRibs));
      final row = _rowIn(db, recipe.id, 2);
      expect(
        db.nutritionFor(recipe.id)!.caloriesPerServing?.toStringAsFixed(2),
        '648.25',
      );
      db.upsertIngredientMatch(row.copyWith(hold: 'partial_pour_away'));
      recomputeTotals(db, recipe);
      expect(_rowIn(db, recipe.id, 2).hold, 'partial_pour_away');
      expect(
        db.nutritionFor(recipe.id)!.caloriesPerServing?.toStringAsFixed(2),
        '612.07',
      );
    });
    test(
      'a non-partialUse medium: 0215 horseradish-crusted-beef-tenderloin '
      'with a real-style "Skim the fat from the liquid." appended (|3 "1 cup '
      'plus 2 teaspoons vegetable oil", a frying oil, then a browning line '
      'beside the browned tenderloin |0) and its fried potato |10 skipped '
      'through the PUT (the fryer then sizes nothing) — |3 keeps the frying '
      "oil's kept part, 23.07 g `discarded`, 285.32 kcal / serving (mutant: "
      'the medium guard dropped → the browning film 13.78 g, 271.38)',
      () async {
        final fdc = FixtureProvider(pending: {...pendingSearches});
        final corpus = loadCorpusRecipe(
          '0215-horseradish-crusted-beef-tenderloin.yaml',
        );
        final (db, recipe) = await computed(
          fdc,
          corpus.copyWith(
            id: '${corpus.id}-v98-skim',
            slug: '${corpus.slug}-v98-skim',
            steps: [
              ...corpus.steps,
              corpus.steps.last.copyWith(
                number: corpus.steps.length + 1,
                text: 'Skim the fat from the liquid.',
              ),
            ],
          ),
        );
        expect(browningFatLinesOf(recipe), {3});
        expect(_rowIn(db, recipe.id, 3).grams?.toStringAsFixed(2), '38.09');
        await applyMatchOverride(db, fdc, recipe, 10, {
          'raw': nutritionLines(recipe)[10].raw,
          'skipped': true,
        });
        final row = _rowIn(db, recipe.id, 3);
        expect(
          (row.grams?.toStringAsFixed(2), row.gramSource),
          ('23.07', 'discarded'),
        );
        expect(
          db.nutritionFor(recipe.id)!.caloriesPerServing?.toStringAsFixed(2),
          '285.32',
        );
      },
    );
  });
}

/// P8's SKIN shape's counts on the tree (the process-wide `names` aside).
const Map<String, Map<String, int>> _skinCounts = {
  'compute': {
    'indexes': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'lower': 1,
    'sentences': 29013,
    'skinScans': 2,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 230478,
    'memo:naming': 2,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:oilOwners': 1,
    'memo:reservedUse': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'memo:dips': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    'memo:parenthetical': 1,
    'browningFatLineReads': 399,
    'memo:defatsLiquid': 1,
  },
  'GET': {
    'leanOnlyReads': 1,
    // RE-PIN (fix101 batch, v101, U1): was 1 — + the GET offer's as-picked
    // read (`pickedMoveSource` → `_carriedIdOf`), once per line text and
    // record.
    'carriedReads': 2,
    'indexes': 1,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'lower': 1,
    'sentences': 29013,
    'memo:pourAway': 1,
    'cheese': 1,
    'memo:brines': 1,
    'memo:wordHeads': 1,
    'memo:brineWords': 1,
    'memo:parting': 1,
    'words': 230478,
    'memo:naming': 2,
    'memo:strainAt': 1,
    'memo:savesRemainder': 1,
    'memo:setAsideLine': 1,
    'memo:measuresOut': 1,
    'memo:reservedWhole': 1,
    'memo:discards': 1,
    'memo:leftInBowl': 1,
    'memo:dips': 1,
    'memo:cutShare': 1,
    'memo:keptSolids': 1,
    'memo:panFatLines': 1,
    'memo:browningFat': 1,
    'memo:parenthetical': 1,
    'browningFatLineReads': 399,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'skinScans': 2,
    'memo:liftedFromMarinade': 1,
    'memo:defatsLiquid': 1,
    'memo:oilOwners': 1,
    'memo:reservedUse': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'm52Keys': 1,
    'memo:coatShape': 1,
    'memo:fries': 1,
    'memo:shallowFries': 1,
    'memo:mayHoldCoat': 1,
  },
  'recompute': {
    'indexes': 1,
    'memo:dips': 1,
    'lower': 1,
    'sentences': 29013,
    'memo:starter': 1,
    'heads': 1,
    'memo:braise': 1,
    'memo:strain': 1,
    'memo:pourAway': 1,
    'memo:oilOwners': 1,
    'memo:reservedUse': 1,
    'memo:leftInBowl': 1,
    'memo:keptSolids': 1,
    'memo:browningFat': 1,
    'memo:parenthetical': 1,
    'browningFatLineReads': 399,
    'words': 230478,
    'memo:naming': 1,
    'memo:skinSentences': 1,
    'allSentences': 1,
    'skinScans': 1,
    'memo:baconPan': 1,
    'memo:baconKept': 1,
    'memo:pourOffFat': 1,
    'memo:defatsLiquid': 1,
  },
};

/// P4's census: every corpus counted repeat (v92's `_counted`, "<file>|<step>:
/// N") and its rounds — 22 sentences in 20 recipes, none in a section.
const List<String> _rounds = [
  '0041-salad-with-herbed-baked-goat-cheese-and-vinaigrette.yaml|2: 6 → 1',
  '0189-pan-seared-thick-cut-steaks.yaml|2: 2 → 1',
  '0198-crispy-pan-fried-pork-chops.yaml|2: 7 → 7',
  '0201-pan-seared-thick-cut-pork-chops.yaml|3: 2 → 1',
  '0201-pan-seared-thick-cut-pork-chops.yaml|4: 2 → 1',
  '0206-crunchy-baked-pork-chops.yaml|4: 3 → 3',
  '0254-crunchy-oven-fried-fish.yaml|3: 3 → 3',
  '0299-grown-up-grilled-cheese-sandwiches-with-cheddar-and-shallot.yaml|3: 2 → 1',
  '0311-smashed-burgers.yaml|3: 2 → 1',
  '0314-black-bean-burgers.yaml|5: 3 → 1',
  '0396-grilled-tomato-and-cheese-pizza.yaml|8: 2 → 1',
  '0398-ultimate-grilled-pizza.yaml|8: 2 → 2',
  '0398-ultimate-grilled-pizza.yaml|9: 2 → 2',
  '0455-chicken-provencal.yaml|1: 4 → 1',
  '0499-huevos-rancheros.yaml|3: 3 → 3',
  '0727-perfect-fried-eggs.yaml|1: 2 → 1',
  '0729-shakshuka-eggs-in-spicy-tomato-and-roasted-red-pepper-sauce.yaml|3: 7 → 7',
  '0810-new-york-bagels.yaml|7: 4 → 1',
  '0820-chocolate-chip-cookie-ice-cream-sandwiches.yaml|5: 8 → 2',
  '1099-spanish-migas-with-fried-eggs.yaml|1: 3 → 1',
  '1101-pupusas-with-quick-salsa-and-curtido.yaml|6: 4 → 1',
  '1147-fresh-bulk-sausage.yaml|5: 3 → 3',
];

/// P5's provider (Opus O4's probe): the fixtures, but a query naming oil is
/// answered with no hits ([as] null) or as the fixtures answer [as] — the
/// one STATED answer.
class _OilAs implements NutritionProvider {
  _OilAs(this.as);
  final String? as;
  final FixtureProvider inner = FixtureProvider(
    pending: {...pendingSearches, 'thyme or dried'},
  );
  @override
  Future<List<FdcCandidate>> search(String q) async => !q.contains('oil')
      ? inner.search(q)
      : as == null
      ? const []
      : inner.search(as!);
  @override
  Future<FdcFood?> food(int id) => inner.food(id);
}
