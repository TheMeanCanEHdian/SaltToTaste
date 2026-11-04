// Matcher v101 (batch fix101: the dual-fleet Run 073/074 fixes over v70–v82
// at the tip 30c1f83; matcherVersion 94 → 95 — ONE corpus row moves, in its
// basis text only: nasi-goreng|9 names every printing step, U13). The spec:
// .claude/diag/2026-11-03/review073/union_Q.md (U1–U16). U1: a person's pick
// of a move SOURCE kept as picked (migration 021 `as_picked`), the compute's
// decided-line derivation shared with the un-skip. U2: a subsection's text
// fields under the recipe's caps. U3 / U12: two hash terms (whether each own
// section lists lines; a section's host group headings). U4 / U5 / U9: three
// per-line reads answered once (the skin-kept part, a routed section's host,
// the note's named titles). U6: a 0 yield reads no share. U7: a negated skim
// never defats. U8: each number of two zero-nutrient keys. U15: the
// own-section yield within 1e-4. U10 / U11: the unpinned arms, one value pin
// each. Every corpus line and step is real; STATED synthesized (named at
// each, with the exception and its corpus source): a real field edited to a
// negative-path value, a real sentence with one word changed, a real line
// moved into another real recipe, the cap shapes' repeated real lines.
// Figures from the recorded fixtures (FixtureProvider) — never the network.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/migrations.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/bulk_job.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/decision_rekey.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'nutrition_v25_cost_test.dart' show fill;
import 'nutrition_v26_cost_test.dart'
    show capLines, capStep, capSteps, capped, ln, pork;
import 'nutrition_writepath_test.dart' as wp;
import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _peruvian = '0139-peruvian-roast-chicken-with-garlic-and-lime.yaml';
const _friedRice = '0521-fried-rice-with-shrimp-pork-and-shiitakes.yaml';
const _nasi = '0523-nasi-goreng-indonesian-style-fried-rice.yaml';
const _shortRibs591 = '0591-grill-roasted-beef-short-ribs.yaml';
const _carnitas = '0492-carnitas-mexican-pulled-pork.yaml';
const _shortRibs = '0087-braised-beef-short-ribs.yaml';
const _potRoast = '0082-simple-pot-roast.yaml';
const _barolo = '0426-beef-braised-in-barolo.yaml';
const _corned = '0091-home-corned-beef-with-vegetables.yaml';
const _kibbeh = '1176-red-lentil-kibbeh.yaml';
const _salmon = '0264-roasted-whole-side-of-salmon.yaml';

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v101-');
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

/// [r] stored and computed (its section children first); the stored copy.
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

/// A provider that answers nothing and counts every ask (NoNet).
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
  group('v101 (review Run 073/074 fixes)', skip: skipIfNoCorpus, () {
    caps();
    shares();
    hashes();
    readers();
    person();
    arms();
    verify4();
  });
  group('v101 cost (RULE C at the caps)', skip: skipIfNoCorpus, costShapes);
}

/// U2 (MED; critics of both fleets, Opus O5): v70 F10 capped a subsection's
/// lines and steps only — its title, kind, servings, prep note and body
/// were bounded by the 2 MB body alone, and the readers loop over them per
/// line (`namesOwnSection` 46 s a hash at 60 × 30,000-character titles;
/// `parseServings`' `_tokenTrim` quadratic, 16 s at 40,000 characters, from
/// the SECTION nutrition GET). v101: the recipe's own caps for the same
/// fields — title 250, kind 120 (the recipe's category), servings 200, prep
/// notes and body 50,000 — in `validateRecipeDocument`, so the importer and
/// the library scan refuse too (B13). The census: every corpus subsection
/// passes (the largest: title 76, 0568; kind 9, 0899; servings 70, 0053;
/// prep notes 1,067, 0053; body 906, 0082). STATED synthesized: 0139's real
/// "Spicy Mayonnaise" subsection with one field padded past its cap.
void caps() {
  test('U2: a subsection field one past its cap is refused, at the cap '
      'accepted (title 250, kind 120, servings 200, prep_notes and body '
      '50,000); every corpus subsection passes (mutant: each cap dropped → '
      'its 251 / 121 / 201 / 50,001 accepted)', () {
    final base = loadCorpusRecipe(_peruvian);
    expect(base.subsections.single.title, 'Spicy Mayonnaise');
    Recipe edited(Subsection Function(Subsection) edit) =>
        base.copyWith(subsections: [edit(base.subsections.single)]);
    for (final (field, cap, edit)
        in <(String, int, Subsection Function(Subsection, String))>[
          ('subsections.title', 250, (s, v) => s.copyWith(title: v)),
          ('subsections.kind', 120, (s, v) => s.copyWith(kind: v)),
          ('subsections.servings', 200, (s, v) => s.copyWith(servings: v)),
          (
            'subsections.prep_notes',
            50000,
            (s, v) => s.copyWith(prepNotes: v),
          ),
          ('subsections.body', 50000, (s, v) => s.copyWith(body: v)),
        ]) {
      String text(int n) => fill('Spicy Mayonnaise ', n).padRight(n, 'x');
      expect(text(cap).length, cap);
      validateRecipeDocument(edited((s) => edit(s, text(cap))));
      expect(
        () => validateRecipeDocument(edited((s) => edit(s, text(cap + 1)))),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            "'$field' must be at most $cap characters.",
          ),
        ),
        reason: field,
      );
    }
    var subsections = 0;
    for (final file in Directory(corpusRecipesDir).listSync()) {
      if (!file.path.endsWith('.yaml')) {
        continue;
      }
      final r = loadCorpusRecipe(file.uri.pathSegments.last);
      subsections += r.subsections.length;
      validateRecipeDocument(r);
    }
    expect(subsections, greaterThan(600));
  });
}

/// U6 (MED; Opus critic 1): `shareReaderOf`'s yield division gave +Infinity
/// for a 0 yield ("MAKES ABOUT 0 CUPS"), which every route caller tests
/// against null only: the parent compute threw (jsonEncode Infinity) after
/// writing the row with Infinity grams, the matches GET 500'd, the bulk
/// sweep counted it failed. v101: a share only when finite and > 0 (the
/// salt_shared pin: servings_parser_test). STATED synthesized (negative
/// path): 0139's "Spicy Mayonnaise" servings edited from MAKES ABOUT 1 CUP
/// to MAKES ABOUT 0 CUPS; the line "1 cup Spicy Mayonnaise (recipe
/// follows)" unchanged.
/// U15 (LOW; Opus critic 2): the own-section yield rule tested
/// `share == 1.0` exactly; the unit tables drift (quart 946.353 ≠ 4 × cup
/// 236.588; tbsp 14.7868 ≠ 3 × tsp 4.92892), so an equal amount in a
/// sibling unit read 0.9999989 / 0.9999973 and was counted twice beside its
/// section. v101: within 1e-4 (the drift ≤ 2.7e-6; the smallest printed step
/// ⅛). Census: no corpus unmarked line sits within 1e-4 of 1 but not at it
/// (the replay byte-identical; the two routed lines, tart|6 and fried-rice|9,
/// read exactly 1).
void shares() {
  test('U6: a 0 yield reads no share — 0139 computes (no throw), no row '
      'holds a non-finite grams or share, the GET serves the line '
      '`not_routed` `no_share`, a bulk sweep counts 0 failed (mutant: the '
      'isFinite guard dropped → the compute throws)', () async {
    final db = _db();
    final fdc = FixtureProvider(pending: pendingSearches);
    final real = loadCorpusRecipe(_peruvian);
    final sub = real.subsections.single;
    expect(sub.servings, 'MAKES ABOUT 1 CUP');
    final line = nutritionLines(real).last;
    expect(line.raw, '1 cup Spicy Mayonnaise (recipe follows)');
    expect(parseShare(line.raw, line.amounts, sub.servings), 1.0);
    expect(parseShare(line.raw, line.amounts, 'MAKES ABOUT 0 CUPS'), isNull);
    final edited = real.copyWith(
      subsections: [sub.copyWith(servings: 'MAKES ABOUT 0 CUPS')],
    );
    final stored = await _compute(db, fdc, edited);
    for (final m in db.ingredientMatchesFor(stored.id)) {
      expect(m.grams?.isFinite ?? true, isTrue, reason: '${m.position}');
      expect(m.childShare?.isFinite ?? true, isTrue, reason: '${m.position}');
    }
    final position = nutritionLines(stored).length - 1;
    expect(_rowIn(db, stored.id, position).childRecipeId, isNull);
    final body = await matchesBody(db, fdc, stored);
    jsonEncode(body);
    final item = (body['items']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere(
          (i) => i['position'] == position,
        );
    final child =
        (item['match']! as Map<String, Object?>)['child']!
            as Map<String, Object?>;
    expect((child['state'], child['reason']), ('not_routed', 'no_share'));
    db.upsertRecipe(stored, sourceSlug: _source, contentHash: 'v101-u6');
    final job = startBulkJob(db, fdc, scope: BulkScope.all)!;
    while (bulkJobRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final row = db.nutritionJob(job)!;
    expect((row['status'], row['failed']), ('done', 0));
    expect(db.nutritionFor(stored.id)!.caloriesPerServing?.isFinite, isTrue);
  });

  test('U15: an own-section yield in a sibling unit names its section — "4 '
      'cups" vs MAKES 1 QUART (0.9999989), "3 teaspoons" vs MAKES 1 '
      'TABLESPOON (0.9999973), "1 quart" vs MAKES 4 CUPS (1.0000011); "5 '
      'cups" vs MAKES ABOUT 5 CUPS (exactly 1) as before; "1 cup" vs MAKES 1 '
      'QUART refused (mutant: the tolerance → `== 1.0` refuses the first '
      'three)', () {
    // STATED synthesized: 0521's REAL section "Basic White Rice" (MAKES
    // ABOUT 5 CUPS) and its real line "5 cups cold cooked white rice, large
    // clumps broken up with fingers" (|9) — the yield and the line's amount
    // rewritten to each sibling-unit pair.
    final real = loadCorpusRecipe(_friedRice);
    final sub = real.subsections.singleWhere(
      (s) => s.title == 'Basic White Rice',
    );
    expect(sub.servings, 'MAKES ABOUT 5 CUPS');
    final line = nutritionLines(real)[9];
    expect(line.raw, startsWith('5 cups cold cooked white rice'));
    bool names(String amount, String servings) {
      final raw = line.raw.replaceFirst('5 cups', amount);
      final p = parseIngredientLine(raw);
      final edited = IngredientLine(raw: raw, item: p.item, amounts: p.amounts);
      return yieldNamesOwnSection(
        edited,
        referenceItemOf(edited),
        sub.copyWith(servings: servings),
      );
    }

    expect(names('5 cups', 'MAKES ABOUT 5 CUPS'), isTrue);
    expect(names('4 cups', 'MAKES 1 QUART'), isTrue);
    expect(names('3 teaspoons', 'MAKES 1 TABLESPOON'), isTrue);
    expect(names('1 quart', 'MAKES 4 CUPS'), isTrue);
    expect(names('1 cup', 'MAKES 1 QUART'), isFalse);
    expect(names('4 cups', 'MAKES 5 CUPS'), isFalse);
  });
}

/// U3 (MED; Sonnet S9, Opus O6): `namesOwnSection` routes an unmarked line
/// only to an own section that LISTS lines, and the hash never hashed that
/// bit — beside a standing reference line (`references` already true) a
/// section gaining its lines flipped a food line to routed with the hash
/// byte-identical (fresh through every stale sweep: 0521 + 0523's marked
/// line, 580.26 → 697.16 kcal/serving on a recompute); emptying it read
/// stale but the stale SCOPE selected nothing until a second sweep. v101:
/// `section_lines` under `references`, only where a section lists none.
/// STATED synthesized (both fleets' probe): 0521 plus 0523's REAL marked
/// line "1 recipe Faux Leftover Rice (recipe follows)" — no corpus recipe
/// holds both an unmarked own-section line and a marked reference — and
/// 0521's "Basic White Rice" emptied, then given its corpus lines back.
/// U12 (LOW; Sonnet S10): a SECTION's "1 teaspoon reserved spice rub" reads
/// the HOST's group headings (`_mainRecipePartNote`); the section's hash
/// omitted them — the host's "SPICE RUB" renamed left 0591's "Mustard
/// Glaze" fresh while its recompute turned the 0 g rule row into an
/// unmatched search. v101: `host_groups` on a section holding a 'reserved '
/// line. STATED synthesized: 0591's heading renamed "RUB MIX".
void hashes() {
  Recipe withFaux(Recipe r) {
    final faux = nutritionLines(loadCorpusRecipe(_nasi))[10];
    expect(faux.raw, '1 recipe Faux Leftover Rice (recipe follows)');
    return r.copyWith(
      ingredients: [
        ...r.ingredients.take(r.ingredients.length - 1),
        r.ingredients.last.copyWith(items: [...r.ingredients.last.items, faux]),
      ],
    );
  }

  Recipe emptied(Recipe r) => r.copyWith(
    subsections: [
      for (final s in r.subsections)
        s.title == 'Basic White Rice' ? s.copyWith(ingredients: const []) : s,
    ],
  );

  List<String> staleIds(SaltDatabase db) => bulkScope(db, BulkScope.stale).ids;

  test('U3: a section GAINING its lines beside a standing reference stales '
      'the parent — the hash differs, fresh false, the FIRST stale sweep '
      'selects the parent and its recompute routes |9 to the section (402.20 '
      'g, 697.16 kcal/serving) (mutant: the term dropped → hash equal, '
      'fresh, the parent never selected)', () async {
    final db = _db();
    final fdc = FixtureProvider(pending: pendingSearches);
    final full = withFaux(loadCorpusRecipe(_friedRice));
    final before = await _compute(db, fdc, emptied(full));
    final id = before.id;
    expect(_rowIn(db, id, 9).childRecipeId, isNull);
    expect(
      db.nutritionFor(id)!.caloriesPerServing?.toStringAsFixed(2),
      '580.26',
    );
    expect(nutritionIsFresh(db, before), isTrue);
    String hash(Recipe r) => ingredientsHashOf(r, ResolverMemo(db));
    db.upsertRecipe(full, sourceSlug: _source, contentHash: 'v101-u3');
    final after = db.recipeByIdOrSlug(id)!.recipe;
    expect(isReferenceIn(after, nutritionLines(after)[9]), isTrue);
    expect(hash(after), isNot(hash(before)));
    expect(nutritionIsFresh(db, after), isFalse);
    expect(staleIds(db), contains(id));
    for (final key in sectionChildKeysOf(db, after, ResolverMemo(db))) {
      await matchAndCompute(db, fdc, nutritionRecipeOf(db, key)!.recipe);
    }
    expect(await matchAndCompute(db, fdc, after), isNull);
    final row = _rowIn(db, id, 9);
    expect(
      (row.childRecipeId, row.grams?.toStringAsFixed(2)),
      ('$id#Basic White Rice', '402.20'),
    );
    expect(
      db.nutritionFor(id)!.caloriesPerServing?.toStringAsFixed(2),
      '697.16',
    );
  });

  test('U3: a section EMPTIED beside a standing reference — the first stale '
      'sweep selects the parent (base: [] until a second sweep collected '
      'the section) (mutant: the term dropped → not selected)', () async {
    final db = _db();
    final fdc = FixtureProvider(pending: pendingSearches);
    final full = withFaux(loadCorpusRecipe(_friedRice));
    final before = await _compute(db, fdc, full);
    expect(_rowIn(db, before.id, 9).childRecipeId, isNotNull);
    db.upsertRecipe(emptied(full), sourceSlug: _source, contentHash: 'v101-e');
    final after = db.recipeByIdOrSlug(before.id)!.recipe;
    expect(
      ingredientsHashOf(after, ResolverMemo(db)),
      isNot(ingredientsHashOf(before, ResolverMemo(db))),
    );
    expect(staleIds(db), contains(before.id));
  });

  test('U3: a recipe whose every section lists lines hashes as before — '
      "1176's (its 'Harissa' line a reference) hash is base 30c1f83's with "
      'the matcher term 94 → 95 alone (measured: the base tree with only the '
      'bump gives this value)', () {
    final db = _db();
    final r = loadCorpusRecipe(_kibbeh);
    db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
    expect(
      r.subsections.every(
        (s) => (s.ingredients ?? const []).any((g) => g.items.isNotEmpty),
      ),
      isTrue,
    );
    expect(nutritionLines(r).any((l) => isReferenceIn(r, l)), isTrue);
    // RE-PIN (fix101 batch, v101): an equality on the v100 hash with the
    // matcher term bumped — the base tree (30c1f83) with matcherVersion 95
    // alone hashes 1176 to exactly this.
    expect(ingredientsHashOf(r, ResolverMemo(db)), _kibbehHash);
  });

  test("U12: renaming 0591's host heading 'SPICE RUB' stales its three glaze "
      "sections (each prints '1 teaspoon reserved spice rub' — the brief's "
      "'siblings hash as before' holds for none of 0591's); a host heading "
      "renamed under a section with no 'reserved ' line hashes it as before "
      "(0070 'RAJAS CON CREMA' → 'Spicy Pickled Radishes') (mutant: the term "
      'dropped → the glaze hashes equal, fresh)', () async {
    final db = _db();
    final fdc = FixtureProvider(
      pending: {...pendingSearches, 'reserved spice rub', 'spice rub'},
    );
    final host = await _compute(db, fdc, loadCorpusRecipe(_shortRibs591));
    expect(host.ingredients.map((g) => g.group), contains('SPICE RUB'));
    final keys = [
      for (final s in host.subsections) sectionKeyOf(host.id, s.title!),
    ];
    expect(keys, hasLength(3));
    final glaze = sectionKeyOf(host.id, 'Mustard Glaze');
    Map<String, String> hashes() => {
      for (final k in keys)
        k: ingredientsHashOf(
          nutritionRecipeOf(db, k)!.recipe,
          ResolverMemo(db),
        ),
    };
    final h0 = hashes();
    final sec0 = nutritionRecipeOf(db, glaze)!.recipe;
    await matchAndCompute(db, fdc, sec0);
    final at = nutritionLines(
      sec0,
    ).indexWhere((l) => l.raw == '1 teaspoon reserved spice rub');
    expect(
      _rowIn(db, glaze, at).description,
      'Reserved from the main recipe — counted in the main recipe’s spice rub',
    );
    final renamed = host.copyWith(
      ingredients: [
        for (final g in host.ingredients)
          g.copyWith(group: g.group == 'SPICE RUB' ? 'RUB MIX' : g.group),
      ],
    );
    db.upsertRecipe(renamed, sourceSlug: _source, contentHash: 'v101-u12');
    final h1 = hashes();
    for (final k in keys) {
      expect(
        nutritionLines(nutritionRecipeOf(db, k)!.recipe).map((l) => l.raw),
        contains('1 teaspoon reserved spice rub'),
        reason: k,
      );
      expect(h1[k], isNot(h0[k]), reason: k);
    }
    expect(nutritionIsFresh(db, nutritionRecipeOf(db, glaze)!.recipe), isFalse);
    // The control (STATED synthesized: 0070's real heading renamed).
    final fajitas = loadCorpusRecipe('0070-skillet-chicken-fajitas.yaml');
    db.upsertRecipe(fajitas, sourceSlug: _source, contentHash: 'v101-c0');
    final radishes = sectionKeyOf(fajitas.id, 'Spicy Pickled Radishes');
    String radishHash() => ingredientsHashOf(
      nutritionRecipeOf(db, radishes)!.recipe,
      ResolverMemo(db),
    );
    final before = radishHash();
    expect(
      fajitas.ingredients.map((g) => g.group),
      contains('RAJAS CON CREMA'),
    );
    final edited = fajitas.copyWith(
      ingredients: [
        for (final g in fajitas.ingredients)
          g.copyWith(group: g.group == 'RAJAS CON CREMA' ? 'RAJAS' : g.group),
      ],
    );
    db.upsertRecipe(edited, sourceSlug: _source, contentHash: 'v101-c1');
    expect(radishHash(), before);
  });
}

/// 1176's hash at v101 — the base tree's with matcherVersion 95 alone.
const _kibbehHash =
    'b7d51339be974de57e5c1ac75c395bb020b9160c0a7966144a3d8cb9e26324bf';

/// U7 (LOW; Sonnet S1): `defatsSentence` had no negation guard — 0492's
/// "(do not skim the fat from the liquid)" counted as skimming, so a person
/// path pointing its meat at a `braisedKept` record took the pair deduction
/// (10–14 %) and the flag "the fat the steps skim". v101: a period-free piece
/// holding 'not skim' / "n't skim" (either apostrophe) / 'without skimming' /
/// 'no need to skim' does not count (substring tests, linear). The fuzz pin
/// (nutrition_v26_cost_test) keeps the design regex as its reference: its
/// atoms hold no negation, so it excludes the negated pieces.
/// U8 (LOW; Sonnet S3): `isZeroNutrientFlavouring` is an exact set read on
/// the normalized item (no singular) — "2 vanilla beans", "1 makrut lime
/// leaf" fell through to the FDC ranking. v101: both numbers listed.
/// U5 (MED; Sonnet S5): the matches GET decoded the whole host document per
/// routed SECTION line (`referenceChildJson` and `compositeFlagOf` read
/// `nutritionRecipeOf`) — 22 s at 24 sections × 400 lines (1.57 MB). v101:
/// both read [childRecipeOf] (the request memo's host, `sectionOf`);
/// `hostDecodes` counts whole-document decodes.
void readers() {
  test("U7: a negated skim never defats — 0492 S3's real sentence reads "
      'false; braisedKeptOf on its recipe with the REAL short-rib line of '
      '1172 nikujaga ("1 pound boneless beef short ribs, trimmed") on '
      "braisedKept 170827 is null (base: the 0.899 / 0.858 pair); 0087's "
      '"strain off the fat" still keeps it (mutant: the guard dropped → '
      'true and the pair)', () {
    const sentence =
        'remove the orange halves, onion, and bay leaves from the cooking '
        'liquid and discard (do not skim the fat from the liquid).';
    final carnitas = loadCorpusRecipe(_carnitas);
    expect(
      carnitas.steps.any((s) => s.text.toLowerCase().contains(sentence)),
      isTrue,
    );
    expect(defatsSentence(sentence), isFalse);
    const rib = '1 pound boneless beef short ribs, trimmed';
    expect(
      nutritionLines(
        loadCorpusRecipe('1172-nikujaga-beef-and-potato-stew.yaml'),
      ).map((l) => l.raw),
      contains(rib),
    );
    expect(braisedKept[170827], isNotNull);
    expect(braisedKeptOf(rib, 170827, carnitas), isNull);
    expect(
      braisedKeptOf(rib, 170827, loadCorpusRecipe(_shortRibs)),
      braisedKept[170827],
    );
    // STATED synthesized (each a real 0492 piece with its negation
    // rewritten): the other three forms refuse too; the un-negated piece
    // counts.
    for (final negated in [
      "remove the bay leaves (don't skim the fat from the liquid).",
      'remove the bay leaves (don’t skim the fat from the liquid).',
      'simmer without skimming the fat from the liquid.',
      'there is no need to skim the fat from the liquid.',
    ]) {
      expect(defatsSentence(negated), isFalse, reason: negated);
    }
    expect(
      defatsSentence('remove the bay leaves (skim the fat from the liquid).'),
      isTrue,
    );
  });

  test('U8: each number of the two zero-nutrient keys — "vanilla beans", '
      '"makrut lime leaf" true (base false); "vanilla bean", "makrut lime '
      'leaves" still true (mutant: an entry dropped → false)', () {
    for (final item in [
      'vanilla beans',
      'makrut lime leaf',
      'vanilla bean',
      'makrut lime leaves',
    ]) {
      expect(
        isZeroNutrientFlavouring(normalizeItem(item)),
        isTrue,
        reason: item,
      );
    }
    expect(
      isZeroNutrientFlavouring(normalizeItem('kaffir lime leaves')),
      isFalse,
    );
  });

  test('U5: the matches GET on 0521 (|9 routed to its own "Basic White '
      'Rice") decodes the host ONCE, the routed item\'s child and flag as '
      "before (the GET JSON byte-identical to base 30c1f83's, the cache "
      'stamps aside — measured on 0521, 0139 and 1176)', () async {
    final db = _db();
    final fdc = FixtureProvider(pending: pendingSearches);
    final stored = await _compute(db, fdc, loadCorpusRecipe(_friedRice));
    hostDecodes = 0;
    final body = await matchesBody(db, fdc, stored);
    expect(hostDecodes, 1);
    final item = (body['items']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere(
          (i) => i['position'] == 9,
        );
    final match = item['match']! as Map<String, Object?>;
    final child = match['child']! as Map<String, Object?>;
    expect(
      (child['state'], child['title'], child['section'], child['share_text']),
      ('routed', 'Basic White Rice', 'Basic White Rice', shareText(1)),
    );
    expect(match['flag'], isNull);
  });

  // closer 2 (verify2 D2): the U9 memo is keyed by the library title map
  // too — one recipe INSTANCE read through memos over two libraries answers
  // each library's titles (the key without the map served the first
  // library's set: an empty first read stayed empty; a held title then read
  // against a library without it threw at `memo.titles[normalized]!`).
  test("U9 KEY: one instance of 0029's real note ('… our Vegetable Broth "
      "Base (this page) …') on its real line 'vegetable broth' — a memo "
      'over an empty library [], over one holding 0035 [0035], over the '
      'empty one again [] (mutant key without the map: [] then [] / '
      'a throw)', () {
    final pistou = loadCorpusRecipe(
      '0029-soupe-au-pistou-provencal-vegetable-soup.yaml',
    );
    final empty = _db();
    final held = _db();
    final base = loadCorpusRecipe('0035-vegetable-broth-base.yaml');
    held.upsertRecipe(
      base,
      sourceSlug: _source,
      contentHash: contentHashOf(base),
    );
    List<String> read(SaltDatabase db) => [
      for (final t in noteNamedTitles(
        pistou,
        'vegetable broth',
        ResolverMemo(db),
      ))
        t.id,
    ];
    expect(read(empty), isEmpty);
    expect(read(held), [base.id]);
    expect(read(empty), isEmpty);
  });
}

/// U1 (MED; Sonnet S2, Opus O4 + critic 3): a person's PICK of a record the
/// line's own moves move AWAY from (R2's lean-only 169566 on 0082's
/// chuck-eye → 168661; the 0" flat 168743 on 0091's brisket → the
/// step-printed 173128) was stored as the value a Confirm of the MOVED row
/// stores, so the carry re-applied the moves: an un-skip kept the pick
/// `auto` (no carry) and the next compute moved it (stored != compute, the
/// recipe fresh: 0082 +730.29 kcal), and the pick reached every other line
/// as the moved record, apply_to_all too. v101: migration 021 `as_picked`
/// — set when no inverse fired and the line's moves would move the pick
/// (`pickedMoveSource`); such a decision is carried as itself
/// (`carriedFoodOf`), and an un-skip of a decided key is the compute's own
/// derivation (`_decidedLineRow`). A Confirm of a MOVED row decides the
/// record bought (as_picked 0) and moves again on each line (v82 closer 2).
/// Through the REAL PUT (`applyMatchOverride`); the computes on the
/// fixtures, every PUT under a provider that answers nothing (0 calls).
void person() {
  Future<void> put(
    SaltDatabase db,
    NutritionProvider p,
    String id,
    int position,
    Map<String, Object?> body,
  ) async {
    final r = nutritionRecipeOf(db, id)!.recipe;
    await applyMatchOverride(db, p, r, position, {
      'raw': nutritionLines(r)[position].raw,
      ...body,
    });
  }

  String energy(SaltDatabase db, String id) =>
      ((jsonDecode(db.nutritionFor(id)!.totalsJson!) as Map)['energy'] as num)
          .toStringAsFixed(2);

  for (final (file, line, engine, picked) in [
    (_potRoast, '1 (3½-pound) boneless chuck-eye roast', 168661, 169566),
    (_corned, '1 (4½- to 5-pound) beef brisket, flat cut', 173128, 168743),
  ]) {
    test('U1: $file|0 "$line" — pick $picked (the move source; the engine '
        'row $engine), skip, un-skip: the row stays $picked `auto`, a full '
        'compute keeps it and the totals; the decision as_picked 1 (mutant: '
        'the flag read dropped in carriedFoodOf → the compute lands '
        '$engine)', () async {
      final db = _db();
      final fdc = FixtureProvider(pending: pendingSearches);
      final stored = await _compute(db, fdc, loadCorpusRecipe(file));
      expect(nutritionLines(stored)[0].raw, line);
      expect(_rowIn(db, stored.id, 0).fdcId, engine);
      final none = _NoNet();
      await put(db, none, stored.id, 0, {'fdc_id': picked});
      final key = lineKeyOf(nutritionLines(stored)[0]);
      expect(
        (db.decisionFor(key)!.fdcId, db.decisionFor(key)!.asPicked),
        (
          picked,
          true,
        ),
      );
      final pickedE = energy(db, stored.id);
      await put(db, none, stored.id, 0, {'skipped': true});
      await put(db, none, stored.id, 0, {'skipped': false});
      final unskipped = _rowIn(db, stored.id, 0);
      expect((unskipped.fdcId, unskipped.status), (picked, 'auto'));
      expect(energy(db, stored.id), pickedE);
      expect(
        nutritionIsFresh(db, db.recipeByIdOrSlug(stored.id)!.recipe),
        isTrue,
      );
      final row = _rowIn(db, stored.id, 0);
      expect(
        await matchAndCompute(db, none, db.recipeByIdOrSlug(stored.id)!.recipe),
        isNull,
      );
      final again = _rowIn(db, stored.id, 0);
      expect(
        (again.fdcId, again.grams, again.gramSource, again.hold),
        (row.fdcId, row.grams, row.gramSource, row.hold),
      );
      expect(energy(db, stored.id), pickedE);
      expect(none.calls, 0);
    });
  }

  test(
    'U1 (the stated limit): 0637|0 (the whole bird on the meat-only '
    '171052, its skin peeled off) picked on the SKIN-ON 171447, skipped, '
    "un-skipped — the un-skip is the compute's own row (the skin step move "
    'back to 171052 applies, as to any engine row), so a full compute '
    'changes nothing (base: 171447 kept `auto`, the compute moved it) '
    "(mutant: the un-skip's decided branch dropped → the compute moves the "
    'row)',
    () async {
      final db = _db();
      final fdc = FixtureProvider(pending: pendingSearches);
      final stored = await _compute(
        db,
        fdc,
        loadCorpusRecipe('0637-grilled-lemon-chicken-with-rosemary.yaml'),
      );
      final none = _NoNet();
      expect(_rowIn(db, stored.id, 0).fdcId, 171052);
      await put(db, none, stored.id, 0, {'fdc_id': 171447});
      await put(db, none, stored.id, 0, {'skipped': true});
      await put(db, none, stored.id, 0, {'skipped': false});
      final unskipped = _rowIn(db, stored.id, 0);
      final e = energy(db, stored.id);
      expect(
        await matchAndCompute(db, none, db.recipeByIdOrSlug(stored.id)!.recipe),
        isNull,
      );
      final again = _rowIn(db, stored.id, 0);
      expect(
        (again.fdcId, again.grams, again.gramSource, again.status),
        (
          unskipped.fdcId,
          unskipped.grams,
          unskipped.gramSource,
          unskipped.status,
        ),
      );
      expect(unskipped.fdcId, 171052);
      expect(energy(db, stored.id), e);
      expect(none.calls, 0);
    },
  );

  test(
    "U1: apply_to_all of 0082|0's pick 169566 lands 0426|0 (the same "
    'line text) on 169566, and its next compute keeps it (base: 168661 '
    'both) (mutant: the flag dropped in applyDecisionToOthers → 168661)',
    () async {
      final db = _db();
      final fdc = FixtureProvider(pending: pendingSearches);
      final roast = await _compute(db, fdc, loadCorpusRecipe(_potRoast));
      final barolo = await _compute(db, fdc, loadCorpusRecipe(_barolo));
      expect(nutritionLines(barolo)[0].raw, nutritionLines(roast)[0].raw);
      expect(_rowIn(db, barolo.id, 0).fdcId, 168661);
      final none = _NoNet();
      await put(db, none, roast.id, 0, {
        'fdc_id': 169566,
        'apply_to_all': true,
      });
      expect(_rowIn(db, barolo.id, 0).fdcId, 169566);
      expect(await matchAndCompute(db, none, barolo), isNull);
      expect(_rowIn(db, barolo.id, 0).fdcId, 169566);
      expect(none.calls, 0);
    },
  );

  test(
    "U1: a Confirm of 0091|0's MOVED 173128 still decides the record "
    'bought 168657 (the ⅛-inch entry key the inverse names, on base 30c1f83 as here — not the brief’s 168743) with as_picked 0, and the carry moves it again on the '
    'line (173128 after a skip, un-skip and a compute) — v82 closer 2 '
    'unchanged (mutant: as_picked set on every decision → the row stays 168657)',
    () async {
      final db = _db();
      final fdc = FixtureProvider(pending: pendingSearches);
      final stored = await _compute(db, fdc, loadCorpusRecipe(_corned));
      expect(_rowIn(db, stored.id, 0).fdcId, 173128);
      final none = _NoNet();
      await put(db, none, stored.id, 0, {'confirmed': true});
      final key = lineKeyOf(nutritionLines(stored)[0]);
      expect(
        (db.decisionFor(key)!.fdcId, db.decisionFor(key)!.asPicked),
        (
          168657,
          false,
        ),
      );
      await put(db, none, stored.id, 0, {'skipped': true});
      await put(db, none, stored.id, 0, {'skipped': false});
      expect(_rowIn(db, stored.id, 0).fdcId, 173128);
      expect(
        await matchAndCompute(db, none, db.recipeByIdOrSlug(stored.id)!.recipe),
        isNull,
      );
      expect(_rowIn(db, stored.id, 0).fdcId, 173128);
      expect(none.calls, 0);
    },
  );

  test(
    "U1 closer 1 (verify1 D1): a DECIDED key's rule-row line un-skips to the "
    "compute's rule row — Confirm 0591|0 '2 tablespoons kosher salt' (decides "
    "'kosher salt' 173468), then skip and un-skip 0264|1 'Kosher salt': the "
    "seasoning rule row, == a full compute (mutant: the un-skip's "
    '_lineRuleRow read dropped → 173468 `auto` 0 g)',
    () async {
      final db = _db();
      final fdc = FixtureProvider(pending: pendingSearches);
      final ribs = await _compute(db, fdc, loadCorpusRecipe(_shortRibs591));
      final salmon = await _compute(db, fdc, loadCorpusRecipe(_salmon));
      expect(nutritionLines(ribs)[0].raw, '2 tablespoons kosher salt');
      expect(nutritionLines(salmon)[1].raw, 'Kosher salt');
      final none = _NoNet();
      await put(db, none, ribs.id, 0, {'confirmed': true});
      expect(
        db.decisionFor(lineKeyOf(nutritionLines(salmon)[1]))!.fdcId,
        173468,
      );
      await put(db, none, salmon.id, 1, {'skipped': true});
      await put(db, none, salmon.id, 1, {'skipped': false});
      final un = _rowIn(db, salmon.id, 1);
      expect(
        (un.fdcId, un.description, un.status, un.grams, un.gramSource),
        (null, engineRuleNotes[1], 'confirmed', null, null),
      );
      expect(
        await matchAndCompute(db, none, db.recipeByIdOrSlug(salmon.id)!.recipe),
        isNull,
      );
      final again = _rowIn(db, salmon.id, 1);
      expect(
        (again.fdcId, again.description, again.status, again.grams),
        (un.fdcId, un.description, un.status, un.grams),
      );
      expect(none.calls, 0);
    },
  );

  test(
    "U1 closer 3 (verify3 D1): the un-skip's reference gate is the "
    "compute's — 0598|3 '1 recipe Basic Spice Rub for Pork Chops (recipe "
    "follows) or 2 teaspoons pepper' with a decision CARRIED to its key "
    "(170931): skip and un-skip give the compute's 170931 4.6 g, and a "
    "full compute keeps it (mutant: the gate's carried-decision term "
    'dropped → the routed Basic Spice Rub row 31.1 g, the next compute '
    '170931 4.6 g). STATED synthesized: no corpus PUT reaches a decision '
    "on a reference line's key (a fresh engine match never lands there); "
    "the decision is inserted with putDecision, as the compute's gate-2 "
    'comment describes (the parent deleted and re-imported); the line is '
    "real (0598's position 3), the record the fixtures' "
    '"Spices, pepper, black"',
    () async {
      final db = _db();
      final fdc = FixtureProvider(pending: pendingSearches);
      final stored = await _compute(
        db,
        fdc,
        loadCorpusRecipe('0598-grilled-pork-chops.yaml'),
      );
      final line = nutritionLines(stored)[3];
      expect(
        line.raw,
        '1 recipe Basic Spice Rub for Pork Chops (recipe follows) or '
        '2 teaspoons pepper',
      );
      final routed = _rowIn(db, stored.id, 3);
      expect((routed.fdcId, routed.grams), (null, 31.1));
      db.putDecision(
        itemKey: lineKeyOf(line),
        item: 'pepper',
        fdcId: 170931,
        description: 'Spices, pepper, black',
        dataType: 'SR Legacy',
        decidedBy: null,
      );
      final none = _NoNet();
      await matchAndCompute(db, none, db.recipeByIdOrSlug(stored.id)!.recipe);
      final carried = _rowIn(db, stored.id, 3);
      expect((carried.fdcId, carried.grams), (170931, 4.6));
      await put(db, none, stored.id, 3, {'skipped': true});
      await put(db, none, stored.id, 3, {'skipped': false});
      final un = _rowIn(db, stored.id, 3);
      expect(
        (un.fdcId, un.grams, un.status),
        (carried.fdcId, carried.grams, carried.status),
      );
      expect(
        await matchAndCompute(db, none, db.recipeByIdOrSlug(stored.id)!.recipe),
        isNull,
      );
      final again = _rowIn(db, stored.id, 3);
      expect((again.fdcId, again.grams, again.status), (170931, 4.6, 'auto'));
      expect(none.calls, 0);
    },
  );

  test(
    "U1 closer 1 (verify1 D2): the matches GET's offer on 0082|0 after the "
    'pick 169566 reaches 0426|0 (the same line text, on 168661) — the offer '
    'is the write: an apply_to_all then changes exactly the lines offered '
    "(mutant: the offer's asPicked forced false → 0426|0 read as left on "
    'its record, offered 0)',
    () async {
      final db = _db();
      final fdc = FixtureProvider(pending: pendingSearches);
      final roast = await _compute(db, fdc, loadCorpusRecipe(_potRoast));
      await _compute(db, fdc, loadCorpusRecipe(_barolo));
      final none = _NoNet();
      await put(db, none, roast.id, 0, {'fdc_id': 169566});
      final recipe = db.recipeByIdOrSlug(roast.id)!.recipe;
      final item =
          ((await matchesBody(db, none, recipe))['items']! as List)[0] as Map;
      expect((item['others'], item['others_lines']), (1, 1));
      final applied = await applyMatchOverride(db, none, recipe, 0, {
        'raw': item['raw'],
        'fdc_id': 169566,
        'apply_to_all': true,
      });
      expect((applied?.recipes, applied?.lines), (1, 1));
      expect(none.calls, 0);
    },
  );

  test(
    "U4 closer 1 (verify1 D3): `skinKeptPart`'s memo answers per ITEM — a "
    'whole bird reads no kept part, a breast line the wings, in either '
    "order on one recipe instance (mutant: the key's item dropped → the "
    "first line's answer served to the second). STATED synthesized (no "
    'corpus recipe holds two skin-off lines with different kept parts — '
    'census over the 1,198: only 0637, every line "wings"): 0637\'s real '
    'sentence "peel skin off chicken, leaving skin on wings" rewritten '
    '"remove skin from chicken breasts, leaving skin on wings", the real '
    'sentence "Discard skin." (0403) appended, and the real line "4 (10- '
    'to 12-ounce) bone-in split chicken breasts, trimmed" (0627) added',
    () {
      Recipe synth() {
        final r = loadCorpusRecipe(
          '0637-grilled-lemon-chicken-with-rosemary.yaml',
        );
        const real = 'peel skin off chicken, leaving skin on wings.';
        expect(r.steps.map((s) => s.text).join(' '), contains(real));
        return r.copyWith(
          ingredients: [
            ...r.ingredients,
            IngredientGroup(
              items: [
                ln(
                  '4 (10- to 12-ounce) bone-in split chicken breasts, trimmed',
                ),
              ],
            ),
          ],
          steps: [
            for (final s in r.steps)
              s.copyWith(
                text: s.text.replaceFirst(
                  real,
                  'remove skin from chicken breasts, leaving skin on wings. '
                  'Discard skin.',
                ),
              ),
          ],
        );
      }

      IngredientLine bird(Recipe r) => nutritionLines(r)[0];
      IngredientLine breast(Recipe r) => nutritionLines(r).last;
      final a = synth();
      expect(bird(a).raw, startsWith('1 (3½- to 4-pound) whole chicken'));
      expect(skinKeptPart(a, bird(a)), isNull);
      expect(skinKeptPart(a, breast(a)), 'wings');
      final b = synth();
      expect(skinKeptPart(b, breast(b)), 'wings');
      expect(skinKeptPart(b, bird(b)), isNull);
    },
  );

  test('U1: migration 021 — user_version ${migrations.length}, '
      'ingredient_decisions.as_picked INTEGER NOT NULL DEFAULT 0; a decision '
      'written with no flag reads false (mutant: DEFAULT 1 → true)', () {
    final dir = Directory.systemTemp.createTempSync('salt-v101-m-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = ServerConfig(
      dataDir: dir.path,
      logLevel: Level.WARNING,
      trustProxy: false,
    ).dbPath;
    SaltDatabase.open(path).dispose();
    final raw = sqlite3.open(path);
    expect(migrations, hasLength(21));
    expect(raw.select('PRAGMA user_version').first.columnAt(0), 21);
    final cols = {
      for (final c in raw.select('PRAGMA table_info(ingredient_decisions)'))
        c['name']: (c['type'], c['notnull'], c['dflt_value']),
    };
    expect(cols['as_picked'], ('INTEGER', 1, '0'));
    raw
      ..execute(
        'INSERT INTO ingredient_decisions (item_key, item, fdc_id) '
        "VALUES ('beef brisket', 'beef brisket', 168743)",
      )
      ..dispose();
    final db = SaltDatabase.open(path);
    addTearDown(db.dispose);
    expect(db.decisionFor('beef brisket')!.asPicked, isFalse);
  });
  test(
    'U1 (verify4 D1): 0091|0 picked 168743 (as_picked 1), then picked the '
    'MOVED 173128 (decides the record bought 168657, as_picked 0): the '
    "second pick's flag REPLACES the first's — the upsert's ON CONFLICT "
    'carries as_picked — so a skip, un-skip and a compute land 173128 '
    '(mutant: `as_picked = excluded.as_picked` dropped from the ON '
    'CONFLICT → the stale flag carries 168657 unmoved)',
    () async {
      final db = _db();
      final fdc = FixtureProvider(pending: pendingSearches);
      final stored = await _compute(db, fdc, loadCorpusRecipe(_corned));
      expect(_rowIn(db, stored.id, 0).fdcId, 173128);
      final none = _NoNet();
      final key = lineKeyOf(nutritionLines(stored)[0]);
      await put(db, none, stored.id, 0, {'fdc_id': 168743});
      expect(
        (db.decisionFor(key)!.fdcId, db.decisionFor(key)!.asPicked),
        (168743, true),
      );
      await put(db, none, stored.id, 0, {'fdc_id': 173128});
      expect(
        (db.decisionFor(key)!.fdcId, db.decisionFor(key)!.asPicked),
        (168657, false),
      );
      await put(db, none, stored.id, 0, {'skipped': true});
      await put(db, none, stored.id, 0, {'skipped': false});
      expect(_rowIn(db, stored.id, 0).fdcId, 173128);
      expect(
        await matchAndCompute(db, none, db.recipeByIdOrSlug(stored.id)!.recipe),
        isNull,
      );
      expect(_rowIn(db, stored.id, 0).fdcId, 173128);
      expect(none.calls, 0);
    },
  );

  test(
    'U1 (verify4 D2): the boot re-key carries as_picked — a decision under '
    "a stale key (item 'onions', picked, on 790646 'Onions, yellow, raw'; "
    "the nutrition_decisions_test form) moves to its item's key 'onion' "
    'still picked (mutant: `asPicked: row.asPicked` dropped in '
    'rekeyDecisions → false: the pick re-moves on every line after a re-key)',
    () {
      final db = _db()
        ..putDecision(
          itemKey: 'stale-key-for-onions',
          item: 'onions',
          fdcId: 790646,
          description: 'Onions, yellow, raw',
          dataType: 'Foundation',
          decidedBy: null,
          asPicked: true,
        )
        ..setSetting(decisionRekeySetting, '1');
      expect(rekeyDecisions(db), 1);
      expect(db.decisionFor('stale-key-for-onions'), isNull);
      expect(
        (db.decisionFor('onion')!.fdcId, db.decisionFor('onion')!.asPicked),
        (790646, true),
      );
    },
  );
}

/// U10 (LOW; Sonnet S7): R-H1's `_hedges` / `_multiplies` single arms were
/// unpinned — dropping one ('to taste', 'up to', 'if using', `per`) left the
/// nine stepAmountsOf files green while real corpus lines' prints changed.
/// One value pin per arm on the REAL lines the fleet named: each line's
/// prints as the tree reads them (the mutant gains a print).
/// U11 (LOW; Sonnet S8): positive alternations unpinned — R-E5's 'contents',
/// 'press ON the solids', 'discard the SOLIDS'; the trim's '¼ inch'; the
/// pan's 'pour off ANY fat'. STATED synthesized (the corpus prints only
/// 'vegetables and liquid', 'press the solids', 'discard the vegetables',
/// '⅛ inch', 'pour off the excess fat'): each real sentence with the one
/// phrase rewritten — 0172 S5 (braised turkey), 0091 S1 (corned beef),
/// 0421 S4 (saltimbocca).
void arms() {
  test('U10: each hedge and multiply arm on its real lines — "to taste" '
      '0289|3; "up to" 0215|1 and 0264|1; "if using" 0337 trapanese|0 and '
      '0692 smashed|1; "per" 0169|0 and 0243|7 (mutant: one arm dropped → '
      'its lines gain a print)', () {
    String prints(String file, int position, String raw) {
      final r = loadCorpusRecipe(file);
      final line = nutritionLines(r)[position];
      expect(line.raw, raw, reason: '$file|$position');
      return [
        for (final p in stepAmountsOf(r, line)) '${p.amount}@${p.step}',
      ].join(', ');
    }

    // 'to taste'
    expect(
      prints('0289-best-crab-cakes.yaml', 3, 'Salt and pepper'),
      '⅛ teaspoon@2',
    );
    // 'up to'
    expect(
      prints('0215-horseradish-crusted-beef-tenderloin.yaml', 1, 'Kosher salt'),
      '¼ teaspoon@1',
    );
    expect(
      prints('0264-roasted-whole-side-of-salmon.yaml', 1, 'Kosher salt'),
      '',
    );
    // 'if using'
    expect(
      prints(
        '0337-pasta-with-pesto-alla-trapanese-tomato-and-almond-pesto.yaml',
        0,
        'Table salt',
      ),
      '1 tablespoon@0',
    );
    expect(
      prints('0692-smashed-potatoes.yaml', 1, 'Table salt'),
      '1 teaspoon@0',
    );
    // 'per'
    expect(prints('0169-roasted-brined-turkey.yaml', 0, 'Salt'), '');
    expect(
      prints(
        '0243-arista-tuscan-style-roast-pork-with-garlic-and-rosemary.yaml',
        7,
        'Kosher salt',
      ),
      '',
    );
  });

  test("U11: R-E5's 'contents', 'press on the solids', 'discard the solids' "
      'each complete the chain on 0172 S5 (the onions `strainedSolid`); the '
      "trim reads '¼ inch' (0091 S1); the pan reads 'pour off any fat' "
      '(0421 S4 → {5}) (mutant: each alternation dropped → null / {})', () {
    final turkey = loadCorpusRecipe('0172-braised-turkey.yaml');
    DiscardedMedium? onions(String from, String to) {
      expect(turkey.steps[4].text, contains(from));
      final r = turkey.copyWith(
        steps: [
          for (final (i, s) in turkey.steps.indexed)
            i == 4 ? s.copyWith(text: s.text.replaceFirst(from, to)) : s,
        ],
      );
      final line = nutritionLines(r)[4];
      return discardedMediumOf(r, line, normalizeItem(lineItemOf(line)));
    }

    for (final (from, to) in const [
      (
        'Strain the vegetables and liquid from the roasting pan',
        'Strain the contents of the roasting pan',
      ),
      ('Press the solids', 'Press on the solids'),
      ('Discard the vegetables.', 'Discard the solids.'),
    ]) {
      expect(onions(from, to), DiscardedMedium.strainedSolid, reason: to);
    }
    const trim = 'trim fat on surface of brisket to ⅛ inch.';
    expect(
      loadCorpusRecipe(_corned).steps[0].text.toLowerCase(),
      startsWith(trim),
    );
    expect(trimsFatSentence(trim), '⅛');
    expect(trimsFatSentence(trim.replaceFirst('⅛', '¼')), '¼');
    final saltimbocca = loadCorpusRecipe('0421-chicken-saltimbocca.yaml');
    expect(panFatLinesOf(saltimbocca), {5});
    const pour = 'Pour off the excess fat from the skillet.';
    expect(saltimbocca.steps.map((s) => s.text).join(' '), contains(pour));
    final any = saltimbocca.copyWith(
      steps: [
        for (final s in saltimbocca.steps)
          s.copyWith(
            text: s.text.replaceFirst(
              pour,
              'Pour off any fat from the skillet.',
            ),
          ),
      ],
    );
    expect(panFatLinesOf(any), {5});
  });
}

/// RULE C at the caps (the v101 families). Each path: every count within
/// [boundsOf] ([expectBounded]), the new counters pinned EXACTLY, the clock
/// a backstop. The cap shapes' lines are real corpus lines repeated
/// (STATED synthesized: the repetition, the filler steps, the padded
/// titles / servings / note).
void costShapes() {
  Future<Map<String, Map<String, int>>> paths(
    SaltDatabase db,
    NutritionProvider provider,
    Recipe Function() stored,
    String shape, {
    bool hash = false,
    void Function(String step, Map<String, int> counts)? exact,
  }) async {
    final seen = <String, Map<String, int>>{};
    for (final (step, run) in <(String, Future<Object?> Function())>[
      if (hash)
        ('hash', () async => ingredientsHashOf(stored(), ResolverMemo(db))),
      ('compute', () => matchAndCompute(db, provider, stored())),
      ('GET', () => matchesBody(db, provider, stored())),
      ('recompute', () async => recomputeTotals(db, stored())),
    ]) {
      stepIndexCounts.clear();
      final sw = Stopwatch()..start();
      await run();
      final ms = sw.elapsedMilliseconds;
      final counts = seen[step] = Map.of(stepIndexCounts)..remove('names');
      expectBounded(
        stored(),
        counts,
        '$shape $step',
        copies: counts['indexes'] ?? 1,
      );
      // The exact counts first: a count pin kills, never the clock.
      exact?.call(step, counts);
      expect(ms, lessThan(backstopMs), reason: '$shape $step: ${ms}ms');
    }
    return seen;
  }

  // U2: 60 sections, each a 250-character title (the cap) holding 0241's
  // real line; 400 of 0241's real lines. Base 30c1f83 accepted 30,000
  // characters a title (Opus O5: a hash 46 s, a compute 137 s); at the cap
  // the readers pay ≤ 250 a title.
  test('U2 TITLES: 60 × 250-character section titles, 400 lines — hash, '
      'compute, GET and recompute bounded; 251 refused', () async {
    final base = loadCorpusRecipe(pork);
    final real = [for (final g in base.ingredients) ...g.items];
    final r = base.copyWith(
      ingredients: [
        IngredientGroup(
          items: [
            for (var i = 0; i < capLines; i++) ln(real[i % real.length].raw),
          ],
        ),
      ],
      subsections: [
        for (var s = 0; s < 60; s++)
          Subsection(
            title: '$s ${fill('pie dough ', 250)}'.substring(0, 250),
            ingredients: [
              IngredientGroup(items: [ln(real[0].raw)]),
            ],
          ),
      ],
    );
    expect(r.subsections.every((s) => s.title!.length == 250), isTrue);
    validateRecipeDocument(r);
    expect(
      () => validateRecipeDocument(
        r.copyWith(
          subsections: [
            r.subsections.first.copyWith(
              title: '${r.subsections.first.title}x',
            ),
            ...r.subsections.skip(1),
          ],
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    final db = wp.tempDb();
    wp.saveRecipe(db, r);
    await paths(
      db,
      FixtureProvider(pending: pendingSearches),
      () => db.recipeByIdOrSlug(r.id)!.recipe,
      'TITLES',
      hash: true,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  // U2: a section yield of 200 characters (the cap) in the critic's
  // quadratic shape for `_tokenTrim` ("MAKES 4 x a" + a run of "!" + "a"):
  // the SECTION nutrition GET's `basisKindOf` reads it (base: 16 s at
  // 40,000 characters; 200² is nothing).
  test('U2 SERVINGS: a 200-character section yield through the section '
      'nutrition GET under the backstop; 201 refused', () async {
    final real = loadCorpusRecipe(_peruvian);
    final servings = 'MAKES 4 x a${'!' * 188}a';
    expect(servings.length, 200);
    final r = real.copyWith(
      subsections: [real.subsections.single.copyWith(servings: servings)],
    );
    validateRecipeDocument(r);
    expect(
      () => validateRecipeDocument(
        real.copyWith(
          subsections: [
            real.subsections.single.copyWith(servings: '${servings}a'),
          ],
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    final db = _db();
    final fdc = FixtureProvider(pending: pendingSearches);
    final stored = await _compute(db, fdc, r);
    final key = sectionKeyOf(stored.id, 'Spicy Mayonnaise');
    final section = nutritionRecipeOf(db, key)!.recipe;
    expect(section.servings, servings);
    final sw = Stopwatch()..start();
    final body = nutritionBody(db, section, forAdmin: true);
    expect(sw.elapsedMilliseconds, lessThan(backstopMs));
    expect(body['status'], isNot('none'));
  });

  // U4: the caps (400 × 0070's real "1 teaspoon salt", 120 × 10,000-
  // character steps of filler), the first step opening 0706's REAL
  // part-less skin sentence. Base 30c1f83: compute 16,508 ms, recompute
  // 16,715 (the fleet's 'Remove and discard the skin.': 17,287 / 16,957);
  // without the sentence 831 / 742; the tree 730 / 726. Counted EXACTLY:
  // one scan per item and index (the one item text: 1 a path).
  test('U4 SKIN-KEPT: a part-less skin sentence trips every line — '
      '`skinKeptPart` scans once per index and item (skinKeptScans 1 a '
      'path), every other family as without the sentence', () async {
    const skin =
        'Using sharp vegetable peeler or chef’s knife, remove skin and '
        'fibrous threads from squash just below skin (peel until squash is '
        'completely orange with no white flesh remaining, roughly ⅛ inch '
        'deep). ';
    expect(
      loadCorpusRecipe(
        '0706-roasted-butternut-squash-with-browned-butter-and-hazelnuts.yaml',
      ).steps.map((s) => s.text).join(' '),
      contains(skin.trim()),
    );
    expect(
      nutritionLines(
        loadCorpusRecipe('0070-skillet-chicken-fajitas.yaml'),
      ).map((l) => l.raw),
      contains('1 teaspoon salt'),
    );
    final seen = <bool, Map<String, Map<String, int>>>{};
    for (final withSkin in [false, true]) {
      final steps = [
        for (var i = 0; i < capSteps; i++)
          (withSkin && i == 0 ? skin : '') +
              fill('Stir well. ', capStep - skin.length),
      ];
      final r = capped(
        loadCorpusRecipe(pork),
        List.filled(capLines, '1 teaspoon salt'),
        steps,
      );
      final db = wp.tempDb();
      wp.saveRecipe(db, r);
      seen[withSkin] = await paths(
        db,
        FixtureProvider(pending: pendingSearches),
        () => db.recipeByIdOrSlug(r.id)!.recipe,
        'SKIN-KEPT $withSkin',
      );
    }
    // A recompute weighs no line (no skin read either way).
    for (final (step, n) in [('compute', 1), ('GET', 1), ('recompute', null)]) {
      final quiet = seen[false]![step]!;
      final loud = seen[true]![step]!;
      expect(quiet['skinKeptScans'], isNull, reason: step);
      expect(loud['skinKeptScans'], n, reason: step);
      expect(loud['memo:skinKeptPart'], n, reason: step);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  // U5: the fleet's shape — 400 reference lines "1 recipe Classic Sauce
  // Number X (recipe follows)" over 24 own sections of 400 "1 teaspoon
  // salt" lines (1.57 MB). Base 30c1f83: the GET 22,030 ms, a host decode
  // per routed line (401); the tree 1,040 ms, ONE.
  test('U5 HOSTS: the matches GET decodes the host once (hostDecodes 1) at '
      '24 sections × 400 reference lines', () async {
    String title(int i) =>
        'Classic Sauce Number ${String.fromCharCode(65 + i)}';
    final r = loadCorpusRecipe(pork).copyWith(
      ingredients: [
        IngredientGroup(
          items: [
            for (var i = 0; i < capLines; i++)
              ln('1 recipe ${title(i % 24)} (recipe follows)'),
          ],
        ),
      ],
      subsections: [
        for (var s = 0; s < 24; s++)
          Subsection(
            title: title(s),
            kind: 'component',
            servings: 'MAKES 2 CUPS',
            ingredients: [
              IngredientGroup(
                items: [
                  for (var j = 0; j < capLines; j++) ln('1 teaspoon salt'),
                ],
              ),
            ],
            steps: const [RecipeStep(number: 1, text: 'Stir well.')],
          ),
      ],
    );
    final db = wp.tempDb();
    wp.saveRecipe(db, r);
    Recipe stored() => db.recipeByIdOrSlug(r.id)!.recipe;
    final none = _NoNet();
    await matchAndCompute(db, none, stored());
    hostDecodes = 0;
    final sw = Stopwatch()..start();
    await matchesBody(db, none, stored());
    final ms = sw.elapsedMilliseconds;
    expect(hostDecodes, 1);
    expect(ms, lessThan(backstopMs));
  }, timeout: const Timeout(Duration(minutes: 3)));

  // U9: 400 reference lines naming library titles, a 50,000-character note
  // (the cap) naming one "(this page)"; a library of 1,200 titles. Base
  // 30c1f83 (the fleet's 20 lines at a 48 k note): the hash 1,663 ms
  // (~100 ms a line); the tree 88 ms. Counted EXACTLY: the note's titles
  // once per recipe instance and memo (memo:noteTitles).
  test('U9 NOTE: the note normalised and the library scanned once per '
      'recipe instance — the hash, compute and GET bounded', () async {
    final db = wp.tempDb();
    for (var i = 0; i < 1200; i++) {
      final lib = wp.saveLines(db, ['1 teaspoon salt'], id: 'lib$i');
      db.upsertRecipe(
        lib.copyWith(title: 'Library Dish Number $i', slug: 'lib-$i'),
        sourceSlug: 'src',
        contentHash: 'lib$i',
      );
    }
    final note =
        'Make Library Dish Number 7 first (this page). '
        '${fill('Mix gently and set aside. ', 50000 - 47)}';
    expect(note.length, lessThanOrEqualTo(50000));
    final host = Recipe(
      id: 'host',
      title: 'Host Dish',
      slug: 'host',
      source: const RecipeSource(name: 'Test', type: 'book'),
      prepNotes: note,
      ingredients: [
        IngredientGroup(
          items: [
            for (var i = 0; i < capLines; i++)
              ln('1 recipe Library Dish Number ${i % 1200} (recipe follows)'),
          ],
        ),
      ],
    );
    validateRecipeDocument(host);
    db.upsertRecipe(host, sourceSlug: 'src', contentHash: 'host');
    final seen = await paths(
      db,
      _NoNet(),
      () => db.recipeByIdOrSlug('host')!.recipe,
      'NOTE',
      hash: true,
      // EXACTLY: once per recipe instance and memo — the GET reads two
      // instances (the request's document and its memo's host read).
      exact: (step, counts) => expect(
        counts['memo:noteTitles'],
        const {'hash': 1, 'compute': 1, 'GET': 2, 'recompute': 1}[step],
        reason: 'NOTE $step',
      ),
    );
    expect(seen['hash']!['memo:noteTitles'], 1);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// verify4 (the batch's final verifier round: four LOW missing pins, the
/// code right in each — D1 and D2 in [person]): D3 the U13 suffix at its
/// cap boundary (8 printing steps named, the count past 8); D4 a one-word
/// library title is never a noted title. Each pin kills its mutant by value.
void verify4() {
  test(
    'U13 (verify4 D3): the basis names at most 8 printing steps and the '
    "count past 8 — 0523's 14 real lines under 9 steps each 'Heat 1 "
    "teaspoon of the reserved oil.' print 'from steps 1, 2, 3, 4, 5, 6, "
    "7, 8, … (9 in all)'; under 8 such steps 'from steps 1, 2, 3, 4, 5, "
    "6, 7, 8' (STATED synthesized: the real line, the v26 R2 sentence "
    'repeated) (mutant: the gate > 9 → the 9th step dropped, no count)',
    () async {
      final base = loadCorpusRecipe(_nasi);
      final real = base.ingredients.single.items;
      expect(real, hasLength(14));
      expect(real[9].raw, '½ cup vegetable oil');
      final prints = List.filled(8, '1 teaspoon').join(' + ');
      for (final n in [8, 9]) {
        final r = base.copyWith(
          subsections: const [],
          steps: [
            for (var i = 0; i < n; i++)
              RecipeStep(
                number: i + 1,
                text: 'Heat 1 teaspoon of the reserved oil.',
              ),
          ],
        );
        final db = wp.tempDb();
        final fdc = FixtureProvider(pending: pendingSearches);
        wp.saveRecipe(db, r);
        final stored = db.recipeByIdOrSlug(r.id)!.recipe;
        expect(await matchAndCompute(db, fdc, stored), isNull);
        final body = await matchesBody(db, fdc, stored);
        final items = (body['items']! as List).cast<Map<String, Object?>>();
        final basis =
            (items[9]['match']! as Map<String, Object?>)['gram_basis']!
                as String;
        expect(
          basis,
          startsWith(
            n == 9
                ? 'only $prints + … (9 in all) of it used (from steps 1, 2, 3, '
                      '4, 5, 6, 7, 8, … (9 in all)) —'
                : 'only $prints of it used (from steps 1, 2, 3, 4, 5, 6, 7, 8) —',
          ),
          reason: '$n steps',
        );
      }
    },
  );

  test('U9 (verify4 D4): a one-word library title is never a noted title — '
      "0467's real note ('… A ciabatta of similar size will work … See this "
      "page for our recipe for Foolproof Hard-Cooked Eggs.') over a library "
      "holding 0803 'Ciabatta': 'ciabatta' names nothing (mutant: the "
      'two-word gate → [0803]); the empty library names nothing either', () {
    final pan = loadCorpusRecipe(
      '0467-pan-bagnat-provencal-tuna-sandwich.yaml',
    );
    expect(pan.prepNotes, contains('this page'));
    expect(pan.prepNotes, contains('A ciabatta of similar size'));
    final ciabatta = loadCorpusRecipe('0803-ciabatta.yaml');
    expect(ciabatta.title, 'Ciabatta');
    final empty = _db();
    final held = _db()
      ..upsertRecipe(
        ciabatta,
        sourceSlug: _source,
        contentHash: contentHashOf(ciabatta),
      );
    expect(held.recipeByIdOrSlug(ciabatta.id), isNotNull);
    List<String> read(SaltDatabase db) => [
      for (final t in noteNamedTitles(pan, 'ciabatta', ResolverMemo(db))) t.id,
    ];
    expect(read(held), isEmpty);
    expect(read(empty), isEmpty);
  });
}
