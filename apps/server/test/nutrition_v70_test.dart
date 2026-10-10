// ignore_for_file: lines_longer_than_80_chars

// Matcher v70 (review Run 063/064 fixes F1–F11; matcherVersion unchanged,
// 68 — no corpus row moves: the replay of snapshot 26 is byte-identical to
// the v69 rows, fix70 r1). Each pin is a finding's reproduction, now
// showing the right behaviour, on real corpus recipes over recorded real
// FDC answers (FixtureProvider; no fixture added), never the network.
// Synthesized, STATED (the review's inputs are edits no corpus recipe
// holds — the fixes have corpus reach 0): F3 0863 with a second pear line;
// F4 0224's flat printing "⅛" / "⅛ to ¼"; F5 1105's cutter as "3 1/2",
// "3½", "3 ½", "3-1/2"; F6 a basil line printing a weight and a volume; F7
// 1105 regrouped / a heading renamed; F8 amount-less lines (amounts: [])
// printing a paren weight (the parser would promote it); F1 0154's gravy
// steps rewritten (the stir gate); F11 0154 with a weight-less turkey line
// before the bird; F10 subsections past the editor caps; closer 1
// (verify1): D2 1105's cutter and sheet as decimals and ".5"; D4 0418's one
// group headed, renamed, unheaded; D5 0466's fillets "1 ½ inch thick". F9
// is the real 1105 and 0418 through the real PUT, D3 the real 1081.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/services/recipe_edit_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';
const _turkey = '0154-classic-roast-turkey.yaml';
const _pomegranate =
    '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml';
const _doughnuts = '1105-yeasted-doughnuts.yaml';
const _pear = '0863-pear-walnut-upside-down-cake.yaml';
const _piccata = '0418-chicken-piccata.yaml';
const _eggplant = '0407-eggplant-parmesan.yaml';
const _gravy = 'Giblet Pan Gravy';
const _fish = '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml';
const _meuniere = '0466-fish-meuniere-with-browned-butter-and-lemon.yaml';

IngredientLine _ln(String raw) {
  final p = parseIngredientLine(raw);
  return IngredientLine(
    raw: raw,
    item: p.item,
    prep: p.prep,
    amounts: p.amounts,
  );
}

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v70-');
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

NutritionProvider _fdc() => FixtureProvider(pending: {...pendingSearches});

/// [r] saved under its own id and computed as the bulk job does: its
/// sections first, then the recipe; the stored recipe.
Future<Recipe> _compute(
  SaltDatabase db,
  NutritionProvider fdc,
  Recipe r,
) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: r.id);
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

/// [base] renamed [tag] (its own id and slug).
Recipe _copy(
  Recipe base,
  String tag, {
  List<IngredientGroup>? ingredients,
  List<RecipeStep>? steps,
}) => base.copyWith(
  id: '${base.id}-$tag',
  slug: '${base.slug}-$tag',
  ingredients: ingredients,
  steps: steps,
);

IngredientMatchRow _row(SaltDatabase db, String id, int position) =>
    db.ingredientMatchesFor(id).singleWhere((m) => m.position == position);

String _g2(double v) => v.toStringAsFixed(2);

void main() {
  group('v70 (review Run 063/064 fixes)', skip: skipIfNoCorpus, () {
    giblets();
    readers();
    writes();
  });
}

/// F1 (the stir gate linear and once per index, the bird once per section),
/// F8 (the amount-less 0 g rule skips the giblet reader's weight only), F11
/// (the first turkey line WITH a printed weight).
void giblets() {
  test('F1: the stir gate reads "stir … giblets … into" in one period-free '
      'stretch, as the v68 regex did (STATED: 0154 gravy steps rewritten)', () {
    final host = loadCorpusRecipe(_turkey);
    double? weighed(String step) {
      final sub = host.subsections.singleWhere((s) => s.title == _gravy);
      final h = host.copyWith(
        subsections: [
          sub.copyWith(steps: [RecipeStep(number: 1, text: step)]),
        ],
      );
      final section = sectionRecipeOf(h, h.subsections.single);
      final line = nutritionLines(section)[1];
      return hostWeighedGiblets(
        _db(),
        section,
        line,
        normalizeItem(lineItemOf(line)),
      )?.grams;
    }

    // The corpus sentence (0154 step 5's).
    expect(
      _g2(weighed('Stir the reserved giblets into the gravy and serve.')!),
      '291.37',
    );
    expect(
      _g2(weighed('Stir in the giblets; spoon into a gravy boat.')!),
      '291.37',
    );
    // Out of order, across a period, or with no 'into': none.
    expect(weighed('Into the gravy, stir the reserved giblets.'), isNull);
    expect(weighed('Stir the giblets. Pour into a gravy boat.'), isNull);
    expect(weighed('Stir the giblets 1.5 times into the gravy.'), isNull);
    expect(weighed('Stir the reserved giblets well.'), isNull);
    expect(weighed('Stirring the giblets into the gravy.'), isNull);
  });

  test('F1: one bird read per section instance, off the host it was built '
      'from (memo:hostBird), the gate once per index (memo:stirsGiblets)', () {
    final host = loadCorpusRecipe(_turkey);
    final section = sectionRecipeOf(
      host,
      host.subsections.singleWhere((s) => s.title == _gravy),
    );
    final line = nutritionLines(section)[1];
    stepIndexCounts.clear();
    final db = _db(); // empty: the bird is read off [host], never the DB
    final first = hostWeighedGiblets(
      db,
      section,
      line,
      normalizeItem(lineItemOf(line)),
    );
    for (var i = 0; i < 399; i++) {
      expect(
        identical(
          hostWeighedGiblets(
            db,
            section,
            line,
            normalizeItem(lineItemOf(line)),
          ),
          first,
        ),
        isTrue,
      );
    }
    expect(_g2(first!.grams), '291.37');
    expect(stepIndexCounts['memo:hostBird'], 1);
    expect(stepIndexCounts['memo:stirsGiblets'], 1);
  });

  test('F11: the bird is the first turkey line WITH a printed weight — a '
      'weight-less one before it is passed over (STATED: 0154 with "1 turkey" '
      'or "Table salt, for the turkey" before its bird)', () async {
    final db = _db();
    final fdc = _fdc();
    final base = loadCorpusRecipe(_turkey);
    for (final (tag, extra) in [
      ('corpus', null),
      (
        'turkey',
        '1 turkey',
      ), // head 'turkey', no weight: v69 stopped here (0 g)
      ('salt', 'Table salt, for the turkey'), // head 'salt': never a bird line
    ]) {
      final g = base.ingredients.first;
      final r = await _compute(
        db,
        fdc,
        _copy(
          base,
          tag,
          ingredients: [
            g.copyWith(
              items: [
                g.items[0],
                if (extra != null) _ln(extra),
                ...g.items.skip(1),
              ],
            ),
            ...base.ingredients.skip(1),
          ],
        ),
      );
      final giblets = _row(db, sectionKeyOf(r.id, _gravy), 1);
      expect(
        (_g2(giblets.grams!), giblets.gramSource, giblets.fdcId),
        ('291.37', 'weight', 171083),
        reason: tag,
      );
    }
  });

  test('F8: an amount-less line printing a paren weight counts 0 g '
      'unmeasured, as v68 (STATED: amounts: [] on 0418); the giblets keep '
      'their weight', () async {
    final db = _db();
    final base = loadCorpusRecipe(_piccata);
    final g = base.ingredients.first;
    final extra = [
      for (final (raw, item) in [
        ('Parmesan cheese (about 1 ounce)', 'Parmesan cheese'),
        ('Unsalted butter (about 2 ounces)', 'Unsalted butter'),
      ])
        IngredientLine(raw: raw, item: item), // amounts: []
    ];
    final r = await _compute(
      db,
      _fdc(),
      _copy(
        base,
        'f8',
        ingredients: [
          g.copyWith(items: [...g.items, ...extra]),
          ...base.ingredients.skip(1),
        ],
      ),
    );
    for (var i = 0; i < extra.length; i++) {
      final m = _row(db, r.id, g.items.length + i);
      expect(
        (m.raw, m.grams, m.gramSource, m.hold),
        (extra[i].raw, 0.0, 'unmeasured', null),
      );
      expect(m.fdcId, isNotNull);
    }
  });
}

/// F3 (one set-aside half, one line), F4 (the brisket's flag and deduction
/// on the move's own phrase), F5 (a cutter or sheet dimension read whole),
/// F6 (the chopped-portion note only where it sized the line).
void readers() {
  test('F3: "Set aside 1 pear half" takes from ONE line — the head\'s '
      'largest count line; a garnish pear line counts whole (STATED: 0863 '
      'with "1 Bosc pear (8 ounces), sliced, for garnish")', () async {
    final db = _db();
    final base = loadCorpusRecipe(_pear);
    final pear = base.ingredients
        .expand((g) => g.items)
        .firstWhere((l) => l.raw.contains('Bosc pears'));
    final garnish = _ln('1 Bosc pear (8 ounces), sliced, for garnish');
    final r = await _compute(
      db,
      _fdc(),
      _copy(
        base,
        'f3',
        ingredients: [
          for (final g in base.ingredients)
            g.copyWith(
              items: [
                for (final l in g.items) ...[l, if (l.raw == pear.raw) garnish],
              ],
            ),
        ],
      ),
    );
    final lines = nutritionLines(r);
    final main = lines.indexWhere((l) => l.raw == pear.raw);
    final extra = lines.indexWhere((l) => l.raw == garnish.raw);
    final m = _row(db, r.id, main);
    final x = _row(db, r.id, extra);
    expect((_g2(m.grams!), m.gramSource), ('442.25', 'discarded'));
    expect((_g2(x.grams!), x.gramSource), ('176.90', 'weight'));
    expect(
      gramBasisFor(db, lines[main], m, recipe: r),
      endsWith(
        '1 pear half saved for another use (step 2) — only the rest counted',
      ),
    );
    expect(
      gramBasisFor(db, lines[extra], x, recipe: r),
      isNot(contains('saved for another use')),
    );
  });

  test('F4: a flat printing "⅛" or "⅛ to ¼" is moved, flagged and deducted '
      'as the ¼ line is — 794.35 kcal per serving each (STATED: 0224 '
      're-printed)', () async {
    final db = _db();
    final base = loadCorpusRecipe(_pomegranate);
    for (final (tag, depth) in [
      ('quarter', '¼'),
      ('eighth', '⅛'),
      ('both', '⅛ to ¼'),
    ]) {
      String at(String? s) =>
          s?.replaceAll(
            'fat trimmed to ¼ inch',
            'fat trimmed to $depth inch',
          ) ??
          '';
      final r = await _compute(
        db,
        _fdc(),
        _copy(
          base,
          tag,
          ingredients: [
            for (final g in base.ingredients)
              g.copyWith(
                items: [
                  for (final l in g.items)
                    l.copyWith(
                      raw: at(l.raw),
                      item: l.item == null ? null : at(l.item),
                      prep: l.prep == null ? null : at(l.prep),
                    ),
                ],
              ),
          ],
        ),
      );
      final m = _row(db, r.id, 0);
      final printed = depth == '⅛ to ¼' ? '⅛- to ¼' : depth;
      expect((m.fdcId, _g2(m.grams!)), (173128, '2041.16'), reason: tag);
      expect(
        _g2(db.nutritionFor(r.id)!.caloriesPerServing!),
        '794.35',
        reason: tag,
      );
      expect(
        gramBasisFor(db, nutritionLines(r)[0], m, recipe: r),
        "from the printed weight (4–5 lb, the midpoint) · approximate (the printed $printed-inch fat cap counted at USDA's ⅛-inch flat trim; USDA's braised pair 173128 → 173130 keeps 67.6 % of the energy by the protein tracer — the fat the steps skim, deducted)",
        reason: tag,
      );
    }
    // The move's other brisket arms read the same phrase.
    expect(
      trimStandInFlagOf(
        '1 (4- to 5-pound) beef brisket, flat cut, fat trimmed to ⅛ inch',
        168743,
      ),
      'approximate (the printed ⅛-inch fat cap renders and is skimmed (step 5); counted as the 0-inch trimmed flat)',
    );
    expect(
      trimStandInFlagOf(
        '1 (9- to 11-pound) whole beef brisket, fat trimmed to ⅛ inch',
        168664,
      ),
      startsWith(
        "approximate (the printed ⅛-inch fat cap counted at USDA's ⅛-inch trim",
      ),
    );
    expect(
      trimStandInFlagOf('1 (4- to 5-pound) beef brisket, flat cut', 173128),
      isNull,
    );
  });

  test('F5: a cutter or sheet printed as a mixed number reads whole — 88.81 % '
      'for "3 1/2", "3½" and "3 ½"; "3-1/2" reads the whole dough; the '
      'corpus 3-inch keeps 65.25 % (STATED: 1105 re-printed)', () async {
    final db = _db();
    final base = loadCorpusRecipe(_doughnuts);
    for (final (tag, cutter, grams, share) in [
      ('corpus', '3-inch', '416.20', '65.25 %: 12 × 3-inch rounds'),
      ('ascii', '3 1/2-inch', '566.49', '88.81 %: 12 × 3 1/2-inch rounds'),
      ('unicode', '3½-inch', '566.49', '88.81 %: 12 × 3½-inch rounds'),
      ('spaced', '3 ½-inch', '566.49', '88.81 %: 12 × 3 ½-inch rounds'),
      ('hyphen', '3-1/2-inch', '637.86', null),
    ]) {
      final r = await _compute(
        db,
        _fdc(),
        _copy(
          base,
          tag,
          steps: [
            for (final s in base.steps)
              s.copyWith(
                text: s.text.replaceAll(
                  '3-inch round cutter',
                  '$cutter round cutter',
                ),
              ),
          ],
        ),
      );
      final m = _row(db, r.id, 0);
      final basis = gramBasisFor(db, nutritionLines(r)[0], m, recipe: r)!;
      expect(_g2(m.grams!), grams, reason: tag);
      if (share == null) {
        expect(
          (m.gramSource, basis),
          ('weight', 'from 22 1/2 ounce'),
          reason: tag,
        );
      } else {
        expect(
          basis,
          contains("the cut share $share from the steps' 10 by 13-inch sheet"),
          reason: tag,
        );
      }
    }
  });

  test('verify1 D2: a decimal cutter or sheet reads whole — "3.5-inch" × 6 '
      '44.41 %, "3.2-inch" × 12 74.24 %, "10 by 13.5-inch" 62.83 %; a figure '
      'after a period (".5-inch" × 6, never 5-inch 90.62 %) reads the whole '
      'dough (STATED: 1105 re-printed)', () async {
    final db = _db();
    final base = loadCorpusRecipe(_doughnuts);
    const cut = 'Using 3-inch round cutter dipped in flour, cut 12 rounds';
    const sheet = '10 by 13-inch rectangle';
    for (final (tag, from, to, grams, share) in [
      (
        'd35',
        cut,
        'Using 3.5-inch round cutter dipped in flour, cut 6 rounds',
        '283.24',
        "44.41 %: 6 × 3.5-inch rounds from the steps' 10 by 13-inch sheet",
      ),
      (
        'd32',
        cut,
        'Using 3.2-inch round cutter dipped in flour, cut 12 rounds',
        '473.54',
        "74.24 %: 12 × 3.2-inch rounds from the steps' 10 by 13-inch sheet",
      ),
      (
        'sheet',
        sheet,
        '10 by 13.5-inch rectangle',
        '400.78',
        "62.83 %: 12 × 3-inch rounds from the steps' 10 by 13.5-inch sheet",
      ),
      (
        'dot',
        cut,
        'Using .5-inch round cutter dipped in flour, cut 6 rounds',
        '637.86',
        null,
      ),
    ]) {
      expect(base.steps.where((s) => s.text.contains(from)), hasLength(1));
      final r = await _compute(
        db,
        _fdc(),
        _copy(
          base,
          tag,
          steps: [
            for (final s in base.steps)
              s.copyWith(text: s.text.replaceAll(from, to)),
          ],
        ),
      );
      final m = _row(db, r.id, 0);
      final basis = gramBasisFor(db, nutritionLines(r)[0], m, recipe: r)!;
      expect(_g2(m.grams!), grams, reason: tag);
      expect(
        basis,
        share == null ? 'from 22 1/2 ounce' : contains('the cut share $share'),
        reason: tag,
      );
    }
  });

  test('verify1 D5: a fillet printed "1 ½ inch thick" is no thin piece — the '
      'dredge stays held; the real "⅜ inch thick" reads thin, C4 25.66 g '
      '(STATED: 0466 re-printed)', () async {
    final db = _db();
    final fdc = _fdc();
    final sole = loadCorpusRecipe(_meuniere);
    final fish = sole.ingredients.first.items[1];
    expect(
      fish.raw,
      '4 (5- to 6-ounce) sole or flounder fillets, ⅜ inch thick (see note)',
    );
    final real = await _compute(db, fdc, sole);
    expect(
      (_g2(_row(db, real.id, 0).grams!), _row(db, real.id, 0).gramSource),
      ('25.66', 'discarded'),
    );
    final thick = await _compute(
      db,
      fdc,
      _copy(
        sole,
        'thick',
        ingredients: [
          sole.ingredients.first.copyWith(
            items: [
              sole.ingredients.first.items.first,
              fish.copyWith(
                raw: fish.raw.replaceAll('⅜ inch', '1 ½ inch'),
                prep: fish.prep?.replaceAll('3/8 inch', '1 ½ inch'),
              ),
              ...sole.ingredients.first.items.skip(2),
            ],
          ),
          ...sole.ingredients.skip(1),
        ],
      ),
    );
    expect(_row(db, thick.id, 1).grams, _row(db, real.id, 1).grams);
    final flour = _row(db, thick.id, 0);
    expect((flour.hold, flour.grams), ('coating', null));
  });

  test(
    'F6: a basil line printing a weight beside its volume is weighed and '
    'says nothing of the chopped portion (STATED lines on FNDDS 2709780)',
    () async {
      final db = _db();
      final fdc = _fdc();
      await _compute(db, fdc, loadCorpusRecipe(_eggplant)); // caches SR 172232
      final food = (await fdc.food(2709780))!;
      for (final (raw, grams, basis) in [
        (
          '2 tablespoons chopped fresh basil',
          '5.30',
          '2 tablespoon · USDA portion · chopped: 2.65 g per tablespoon — USDA SR 172232 "Basil, fresh" \'tbsp, chopped\' × 2 = 5.3 g',
        ),
        (
          '1 ounce (about 1 cup) fresh basil leaves, chopped',
          '28.35',
          'from 1 ounce',
        ),
        (
          '1 ounce fresh basil leaves (about ½ cup), minced',
          '28.35',
          'from 1 ounce',
        ),
      ]) {
        final g = lineGrams(db, _ln(raw), food)!;
        expect((_g2(g.grams), g.basis), (grams, basis), reason: raw);
      }
    },
  );
}

/// F7 (the group layout in the hash), F9 (an orphaned plan row back to its
/// engine form), F10 (the editor caps per subsection).
void writes() {
  test('F7: a regroup or a heading edit alone stales the totals; the '
      'recompute reaches the new value (STATED: 1105 split after line 4, its '
      'heading renamed)', () async {
    final db = _db();
    final fdc = _fdc();
    final base = loadCorpusRecipe(_doughnuts);
    final r = await _compute(db, fdc, base);
    expect(_g2(db.nutritionFor(r.id)!.caloriesPerServing!), '432.75');
    final g = base.ingredients.first;
    for (final (tag, groups, perServing) in [
      (
        'split',
        [
          g.copyWith(items: g.items.sublist(0, 4)),
          g.copyWith(group: 'DOUGH 2', items: g.items.sublist(4)),
          ...base.ingredients.skip(1),
        ],
        '425.50',
      ),
      (
        'renamed',
        [g.copyWith(group: '${g.group ?? ''} X'), ...base.ingredients.skip(1)],
        '432.75',
      ),
    ]) {
      db.upsertRecipe(
        base.copyWith(ingredients: groups),
        sourceSlug: _source,
        contentHash: tag,
      );
      final stored = db.recipeByIdOrSlug(r.id)!.recipe;
      expect(
        nutritionLines(stored).map((l) => l.raw),
        nutritionLines(base).map((l) => l.raw),
        reason: tag,
      );
      expect(
        nutritionIsFresh(db, stored, db.nutritionFor(r.id)),
        isFalse,
        reason: tag,
      );
      expect(await matchAndCompute(db, fdc, stored), isNull);
      expect(
        nutritionIsFresh(db, stored, db.nutritionFor(r.id)),
        isTrue,
        reason: tag,
      );
      expect(
        _g2(db.nutritionFor(r.id)!.caloriesPerServing!),
        perServing,
        reason: tag,
      );
      db.upsertRecipe(base, sourceSlug: _source, contentHash: 'back-$tag');
      expect(
        await matchAndCompute(db, fdc, db.recipeByIdOrSlug(r.id)!.recipe),
        isNull,
      );
    }
  });

  /// The rows and totals as stored, for comparing a PUT with a compute.
  (String, String, String, String) state(SaltDatabase db, String id) {
    final n = db.nutritionFor(id)!;
    return (
      n.status,
      _g2(n.caloriesPerServing!),
      _g2(batchTotalsOf(n)['energy']!),
      [
        for (final m in db.ingredientMatchesFor(id))
          (m.position, m.status, m.grams, m.gramSource, m.hold),
      ].join('; '),
    );
  }

  test('F7b: a group boundary moved between two EXISTING groups, both names '
      "unchanged, stales the totals (the owner's mutant on the layout term: "
      'the names alone would not see it; STATED: 1105 split after line 4, '
      'then after line 3)', () async {
    final db = _db();
    final fdc = _fdc();
    final base = loadCorpusRecipe(_doughnuts);
    final g = base.ingredients.first;
    List<IngredientGroup> splitAt(int n) => [
      g.copyWith(items: g.items.sublist(0, n)),
      g.copyWith(group: 'DOUGH 2', items: g.items.sublist(n)),
      ...base.ingredients.skip(1),
    ];
    final r = await _compute(db, fdc, base.copyWith(ingredients: splitAt(4)));
    expect(nutritionIsFresh(db, r, db.nutritionFor(r.id)), isTrue);
    db.upsertRecipe(
      base.copyWith(ingredients: splitAt(3)),
      sourceSlug: _source,
      contentHash: 'moved',
    );
    final stored = db.recipeByIdOrSlug(r.id)!.recipe;
    expect(
      stored.ingredients.map((x) => x.group),
      r.ingredients.map((x) => x.group),
      reason: 'the group names are unchanged',
    );
    expect(
      nutritionLines(stored).map((l) => l.raw),
      nutritionLines(r).map((l) => l.raw),
      reason: 'the flat lines are unchanged',
    );
    expect(nutritionIsFresh(db, stored, db.nutritionFor(r.id)), isFalse);
    expect(await matchAndCompute(db, fdc, stored), isNull);
    expect(nutritionIsFresh(db, stored, db.nutritionFor(r.id)), isTrue);
  });

  test('F9: the oil |7 skipped, typed or picked through the real PUT — the '
      "cut dough's rows go back to their whole lines in that write, and a "
      'full compute changes nothing (1105)', () async {
    final fdc = _fdc();
    for (final (tag, body) in [
      ('skip', {'skipped': true}),
      ('typed', {'grams': 100}),
      ('pick', {'fdc_id': -1}), // the stored oil record, picked by a person
    ]) {
      final db = _db();
      final r = await _compute(db, fdc, loadCorpusRecipe(_doughnuts));
      expect(_g2(_row(db, r.id, 0).grams!), '416.20');
      final oil = _row(db, r.id, 7);
      await applyMatchOverride(db, fdc, r, 7, {
        'raw': nutritionLines(r)[7].raw,
        for (final MapEntry(:key, :value) in body.entries)
          key: key == 'fdc_id' ? oil.fdcId : value,
      });
      final put = state(db, r.id);
      expect(
        [
          for (final m in db.ingredientMatchesFor(r.id).take(7))
            (m.status, _g2(m.grams!), m.gramSource, m.hold),
        ],
        [
          ('auto', '637.86', 'weight', null),
          ('auto', '99.22', 'weight', null),
          ('auto', '3.15', 'density', null),
          ('auto', '366.00', 'portion', null),
          ('auto', '50.00', 'piece', null),
          ('auto', '9.02', 'density', null),
          ('auto', '113.44', 'density', null),
        ],
        reason: tag,
      );
      expect(
        gramBasisFor(db, nutritionLines(r)[0], _row(db, r.id, 0), recipe: r),
        'from 22 1/2 ounce',
        reason: tag,
      );
      expect(recomputeTotals(db, r), isTrue);
      expect(state(db, r.id), put, reason: '$tag: a second recompute');
      expect(await matchAndCompute(db, fdc, r), isNull);
      expect(state(db, r.id), put, reason: '$tag: a full compute');
      if (tag == 'skip') {
        expect((put.$1, put.$2, put.$3), ('complete', '439.26', '5271.13'));
      }
    }
  });

  test("F9 (Run 064's critic): the chicken |1 skipped — the flour |3 goes "
      'back to the held coat, as a full compute writes it (0418)', () async {
    final fdc = _fdc();
    final db = _db();
    final r = await _compute(db, fdc, loadCorpusRecipe(_piccata));
    final flour = _row(db, r.id, 3);
    expect(
      (_g2(flour.grams!), flour.gramSource, flour.hold),
      ('27.99', 'discarded', null),
    );
    await applyMatchOverride(db, fdc, r, 1, {
      'raw': nutritionLines(r)[1].raw,
      'skipped': true,
    });
    final put = state(db, r.id);
    final held = _row(db, r.id, 3);
    expect(
      (held.status, held.grams, held.gramSource, held.hold),
      ('auto', null, null, 'coating'),
    );
    expect(put.$3, '877.91');
    expect(await matchAndCompute(db, fdc, r), isNull);
    expect(state(db, r.id), put);
  });

  test('verify1 D4: a heading added to, renamed on or dropped from the ONE '
      'group of a recipe stales its totals; the compute stamps them fresh '
      '(STATED: 0418 headed)', () async {
    final db = _db();
    final fdc = _fdc();
    final base = loadCorpusRecipe(_piccata);
    expect(base.ingredients, hasLength(1));
    expect(base.ingredients.single.group, isNull);
    final r = await _compute(db, fdc, base);
    final g = base.ingredients.single;
    for (final (tag, heading) in [
      ('added', 'FOR THE CHICKEN'),
      ('renamed', 'CHICKEN'),
      ('dropped', null),
    ]) {
      db.upsertRecipe(
        base.copyWith(ingredients: [g.copyWith(group: heading)]),
        sourceSlug: _source,
        contentHash: tag,
      );
      final stored = db.recipeByIdOrSlug(r.id)!.recipe;
      expect(stored.ingredients.single.group, heading, reason: tag);
      expect(
        nutritionIsFresh(db, stored, db.nutritionFor(r.id)),
        isFalse,
        reason: tag,
      );
      expect(await matchAndCompute(db, fdc, stored), isNull);
      expect(
        nutritionIsFresh(db, stored, db.nutritionFor(r.id)),
        isTrue,
        reason: tag,
      );
    }
  });

  test('verify1 D3: the haddock |12 skipped through the real PUT — the batter '
      'goes back to its whole lines AND the oil |11 is planned on them, '
      '26.09 g, 815.36 per serving, as a second recompute and a full '
      'compute write it (1081)', () async {
    final fdc = _fdc();
    final db = _db();
    final r = await _compute(db, fdc, loadCorpusRecipe(_fish));
    final fish = _row(db, r.id, 12);
    expect((_g2(fish.grams!), fish.gramSource), ('566.99', 'weight'));
    await applyMatchOverride(db, fdc, r, 12, {
      'raw': nutritionLines(r)[12].raw,
      'skipped': true,
    });
    final put = state(db, r.id);
    expect(
      [
        for (final p in [6, 7, 9, 10, 11])
          (p, _g2(_row(db, r.id, p).grams!), _row(db, r.id, p).gramSource),
      ],
      [
        (6, '60.33', 'density'),
        (7, '63.88', 'density'),
        (9, '2.27', 'density'),
        (10, '180.00', 'portion'),
        (11, '26.09', 'discarded'),
      ],
    );
    expect(
      gramBasisFor(db, nutritionLines(r)[11], _row(db, r.id, 11), recipe: r),
      contains("frying oil absorbed: 8.43 % of the raw batter's weight"),
    );
    expect((put.$1, put.$2, put.$3), ('complete', '815.36', '3261.43'));
    expect(nutritionIsFresh(db, r, db.nutritionFor(r.id)), isTrue);
    expect(recomputeTotals(db, r), isTrue);
    expect(state(db, r.id), put, reason: 'a second recompute');
    expect(await matchAndCompute(db, fdc, r), isNull);
    expect(state(db, r.id), put, reason: 'a full compute');
  });

  test('F10: a subsection is held to the editor caps of the recipe — 400 '
      'lines, 60 groups, 120 steps of 1–10,000 characters (STATED: 0154 '
      'gravy past each); every corpus recipe still validates', () {
    final host = loadCorpusRecipe(_turkey);
    final sub = host.subsections.singleWhere((s) => s.title == _gravy);
    final line = sub.ingredients!.first.items.first;
    Recipe withSection(Subsection s) => host.copyWith(
      subsections: [
        for (final x in host.subsections) x.title == _gravy ? s : x,
      ],
    );
    void refused(Subsection s, String message) => expect(
      () => validateRecipeDocument(withSection(s)),
      throwsA(
        isA<ValidationException>().having((e) => e.message, 'message', message),
      ),
    );
    refused(
      sub.copyWith(
        ingredients: [IngredientGroup(items: List.filled(401, line))],
      ),
      'At most 400 ingredient lines.',
    );
    refused(
      sub.copyWith(
        ingredients: List.filled(61, IngredientGroup(items: [line])),
      ),
      'At most 60 ingredient groups.',
    );
    refused(
      sub.copyWith(
        steps: [
          for (var i = 0; i < 121; i++)
            RecipeStep(number: i + 1, text: 'Stir.'),
        ],
      ),
      'At most 120 steps.',
    );
    refused(
      sub.copyWith(steps: [RecipeStep(number: 1, text: 'x' * 10001)]),
      "'step text' must be 1-10000 characters.",
    );
    refused(
      sub.copyWith(
        ingredients: [
          IngredientGroup(items: [line.copyWith(raw: 'x' * 1001)]),
        ],
      ),
      "'ingredient raw' must be 1-1000 characters.",
    );
    // At the caps: accepted.
    validateRecipeDocument(
      withSection(
        sub.copyWith(
          ingredients: [IngredientGroup(items: List.filled(400, line))],
          steps: [
            for (var i = 0; i < 120; i++)
              RecipeStep(number: i + 1, text: 'x' * 10000),
          ],
        ),
      ),
    );
    var n = 0;
    for (final f in Directory(corpusRecipesDir).listSync().whereType<File>()) {
      if (f.path.endsWith('.yaml')) {
        validateRecipeDocument(loadCorpusRecipe(f.uri.pathSegments.last));
        n++;
      }
    }
    expect(n, 1198);
  });
}
