// Real corpus lines wrap across adjacent literals; the table keeps each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v40, edible yields part 2 — the live step's answers (the owner's
/// 13 requests, 2026-10-05; snapshot 17). E1: a whole bird or pieces on
/// 171447 whose recipe discards the skin moves to SR 171052 at its own
/// ready-to-cook yield (the whole bird unflagged, pieces flagged). E2: clams
/// bought in the shell by weight on SR 174214 at its "lb (with shell)"
/// shell yield, counted. N1–N4: what the live step did not enable. Each row
/// is a real corpus line at the record, grams, bucket and basis the
/// cache-only replay of snapshot 17 derives at v40; the answers are copied
/// from snapshot 17 (tool/record_fdc_fixtures.dart --from-db). v43
/// (re-pinned from the snapshot-19 replay): pieces on 171052 read AH-102's
/// derived pieces meat figure (Y2, Y13 — the record decides, so skin-eaten
/// pieces put there read it too), the five breast lines' four that discard
/// the skin move to 2646170 (Y3), the whole turkey 0.6515 (Y5).
void main() {
  /// [from]'s line at [position], alone in a recipe with [from]'s steps and
  /// prep notes, matched and computed on the fixtures; its one row and line.
  Future<(SaltDatabase, IngredientMatchRow, IngredientLine)> computed(
    Recipe from,
    int position,
  ) async {
    final line = nutritionLines(from)[position];
    final dir = Directory.systemTemp.createTempSync('salt-v40');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    db.upsertSource(slug: 'src', name: 'Test', type: 'book');
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      prepNotes: from.prepNotes,
      steps: from.steps,
      ingredients: [
        IngredientGroup(items: [line]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
    await matchAndCompute(db, FixtureProvider(), recipe);
    return (db, db.ingredientMatchesFor('r').single, line);
  }

  group('in their recipes', skip: skipIfNoCorpus, () {
    test('E1, E2 and the N1–N4 non-trips, line by line', () async {
      for (final (file, position, raw, fdcId, grams, bucket, hold, basis)
          in _pins) {
        final (db, row, line) = await computed(
          loadCorpusRecipe(file),
          position,
        );
        expect(line.raw, raw, reason: file);
        expect(row.fdcId, fdcId, reason: raw);
        expect(row.grams?.toStringAsFixed(2), grams, reason: raw);
        expect(row.hold, hold, reason: raw);
        expect(
          matchBucketFor(
            status: row.status,
            fdcId: row.fdcId,
            grams: row.grams,
            confidence: row.confidence,
            hold: row.hold,
            gramSource: row.gramSource,
          ).wire,
          bucket,
          reason: raw,
        );
        expect(
          gramBasisFor(
            db,
            line,
            row,
            recipe: db.recipeByIdOrSlug('r')!.recipe,
          ),
          basis,
          reason: raw,
        );
      }
    });

    test('E1: a decision written from a moved row names the skin-on '
        'record bought (171447), as v39 Y3', () {
      final recipe = loadCorpusRecipe(
        '0637-grilled-lemon-chicken-with-rosemary.yaml',
      );
      final line = nutritionLines(recipe)[0];
      expect(skinDiscarded(recipe, line), isTrue);
      expect(decisionRecordOf(recipe, line, 171052), 171447);
    });

    test('E1 whole bird: the part a skin-off sentence leaves the skin on '
        '(0637 "leaving skin on wings"); none where the whole skin goes', () {
      final lemon = loadCorpusRecipe(
        '0637-grilled-lemon-chicken-with-rosemary.yaml',
      );
      expect(skinKeptPart(lemon, nutritionLines(lemon)[0]), 'wings');
      for (final (file, position) in [
        ('0100-moroccan-chicken-with-olives-and-lemon.yaml', 8),
        ('0004-pressure-cooker-chicken-noodle-soup.yaml', 8),
      ]) {
        final recipe = loadCorpusRecipe(file);
        final line = nutritionLines(recipe)[position];
        expect(skinDiscarded(recipe, line), isTrue, reason: file);
        expect(skinKeptPart(recipe, line), isNull, reason: file);
      }
    });

    test(
      'E1 pieces (v43 Y13): the record decides — skin-eaten pieces put '
      'on 171052 read the pieces meat figure, as discarded ones do',
      () async {
        final recipe = loadCorpusRecipe('0148-crispy-fried-chicken.yaml');
        final line = nutritionLines(recipe)[6];
        expect(
          line.raw,
          '4 pounds bone-in, skin-on chicken pieces (split breasts cut in '
          'half, drumsticks, and/or thighs), trimmed',
        );
        expect(skinDiscarded(recipe, line), isFalse);
        final dir = Directory.systemTemp.createTempSync('salt-v40');
        addTearDown(() => dir.deleteSync(recursive: true));
        final db = SaltDatabase.open('${dir.path}/salt.db');
        addTearDown(db.dispose);
        final meatOnly = (await FixtureProvider().food(171052))!;
        final grams = lineGrams(db, line, meatOnly, recipe: recipe);
        expect(grams?.grams.toStringAsFixed(2), '1097.55');
        expect(grams?.basis, 'from 4 pound $_piecesMeat');
      },
    );

    test('E1 non-trip: a step taking the skin "from the breast pieces" '
        'does not trip a whole-bird line (0002); "from the chicken thighs" '
        'still trips a thigh line (0455)', () {
      final soup = loadCorpusRecipe('0002-classic-chicken-noodle-soup.yaml');
      final bird = nutritionLines(soup)[1];
      expect(bird.raw, startsWith('1 (4-pound) whole chicken, breast removed'));
      expect(skinDiscarded(soup, bird), isFalse);
      expect(decisionRecordOf(soup, bird, 171052), 171052);
      final provencal = loadCorpusRecipe('0455-chicken-provencal.yaml');
      final thighs = nutritionLines(provencal).firstWhere(
        (l) => l.raw.contains('chicken thighs'),
      );
      expect(skinDiscarded(provencal, thighs), isTrue);
    });

    // RE-PIN (M47 batch, v49 Q11): its detail still publishes no
    // with-shell portion, so the line reads AH-102 item 1531 ([ah102Shells])
    // and is counted (was held in_shell at the gross 1,814.37 g).
    test('N3: a mussel line on SR 174216 — whose detail publishes no '
        'with-shell portion — reads AH-102 item 1531, counted', () async {
      final recipe = loadCorpusRecipe('0294-oven-steamed-mussels.yaml');
      final line = nutritionLines(recipe)[6];
      expect(line.raw, '4 pounds mussels, scrubbed and debearded');
      final dir = Directory.systemTemp.createTempSync('salt-v40');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = SaltDatabase.open('${dir.path}/salt.db');
      addTearDown(db.dispose);
      final mussel = (await FixtureProvider().food(174216))!;
      final grams = lineGrams(db, line, mussel, recipe: recipe);
      expect(grams?.grams.toStringAsFixed(2), '526.17');
      expect(
        grams?.basis,
        'from 4 pound × 0.29 edible · approximate (USDA AH-102 item 1531: mussels, whole → drained solids, raw 29 % (25–33); the liquor in the pot is not counted)',
      );
      expect(engineOutcome(recipe, line, mussel, grams).hold, isNull);
    });
  });
}

/// (corpus file, position, raw, fdc id, grams, bucket, hold, basis).
const List<(String, int, String, int?, String?, String, String?, String?)>
_pins = [
  // E1 whole birds: 171052's own "unit (yield from 1 lb ready-to-cook
  // chicken)" 197 g (4 pounds: 1,814.37 × 197/453.59 = 788.0) — unflagged
  // where the whole skin goes; 0637's S1 "peel skin off chicken, leaving
  // skin on wings" keeps the wing skin, which the flag names
  // (prep39/plan.md, the owner-approved plan).
  (
    '0637-grilled-lemon-chicken-with-rosemary.yaml',
    0,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171052,
    // RE-PIN (M48): 788.00 → 738.75 g, the printed 3½–4 lb range at its
    // midpoint (was its top); the basis names the range.
    '738.75',
    'counted',
    null,
    'from the printed weight (3½–4 lb, the midpoint) × 0.43 edible (USDA ready-to-cook yield) · '
        "approximate (skin discarded except the wings; the bird's meat-only "
        'yield)',
  ),
  (
    '0100-moroccan-chicken-with-olives-and-lemon.yaml',
    8,
    '1 (3½ to 4-pound) whole chicken, cut into 8 pieces (4 breast pieces, 2 thighs, 2 drumsticks), wings discarded, and trimmed',
    171052,
    // RE-PIN (M48): 788.00 → 738.75 g, the printed 3½–4 lb range at its
    // midpoint (was its top); the basis names the range.
    '738.75',
    'counted',
    null,
    'from the printed weight (3½–4 lb, the midpoint) × 0.43 edible (USDA ready-to-cook yield)',
  ),
  (
    '0004-pressure-cooker-chicken-noodle-soup.yaml',
    8,
    '1 (4-pound) whole chicken, giblets discarded',
    171052,
    '788.00',
    'counted',
    null,
    'from the printed weight × 0.43 edible (USDA ready-to-cook yield)',
  ),
  // A non-trip (prep39/skin_render.md: outside the narrow signal): Step 3
  // takes "the skin and bones from the breast pieces" of a whole bird —
  // a part the line's item does not name — so it stays on 171447 at v39's
  // whole-bird yield.
  (
    '0002-classic-chicken-noodle-soup.yaml',
    1,
    '1 (4-pound) whole chicken, breast removed, split, and reserved; remaining chicken cut into 2-inch pieces',
    171447,
    '1104.00',
    'counted',
    null,
    'from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
  ),
  // E1 pieces: v43 (Y2) AH-102's derived pieces meat figure (v40: the whole
  // bird's 0.43 per pound).
  (
    '0141-pollo-en-mole-poblano-chicken-in-puebla-style-mole.yaml',
    15,
    '3½ pounds bone-in chicken pieces (split breasts, legs, and/or thighs), skin removed, trimmed',
    171052,
    '960.36',
    'counted',
    null,
    'from 3 1/2 pound $_piecesMeat',
  ),
  (
    '0569-tandoori-chicken.yaml',
    9,
    '3 pounds bone-in, skin-on chicken pieces (split breasts cut in half, drumsticks, and/or thighs), trimmed and skin removed',
    171052,
    '823.16',
    'counted',
    null,
    'from 3 pound $_piecesMeat',
  ),
  // E2: 174214's "lb (with shell), yield after shell removed" 68 g a pound.
  (
    '0034-new-england-clam-chowder.yaml',
    0,
    '7 pounds medium-size hard-shell clams, such as cherrystones, washed and scrubbed clean',
    174214,
    '476.00',
    'counted',
    null,
    'from 7 pound × 0.15 edible (USDA yield after shell removed)',
  ),
  (
    '0106-paella-on-the-grill.yaml',
    14,
    '1 pound littleneck clams, scrubbed',
    174214,
    '68.00',
    'counted',
    null,
    'from 1 pound × 0.15 edible (USDA yield after shell removed)',
  ),
  (
    '0108-cioppino.yaml',
    11,
    '1 pound littleneck clams, scrubbed',
    174214,
    '68.00',
    'counted',
    null,
    'from 1 pound × 0.15 edible (USDA yield after shell removed)',
  ),
  (
    '0295-indoor-clambake.yaml',
    0,
    '2 pounds small littleneck or cherrystone clams, scrubbed',
    174214,
    '136.00',
    'counted',
    null,
    'from 2 pound × 0.15 edible (USDA yield after shell removed)',
  ),
  (
    '0348-linguine-allo-scoglio-linguine-with-seafood.yaml',
    3,
    '1 pound littleneck clams, scrubbed',
    174214,
    '68.00',
    'counted',
    null,
    'from 1 pound × 0.15 edible (USDA yield after shell removed)',
  ),
  (
    '1120-cataplana-portuguese-seafood-stew.yaml',
    13,
    '3 pounds littleneck or Manila clams, scrubbed',
    174214,
    '204.00',
    'counted',
    null,
    'from 3 pound × 0.15 edible (USDA yield after shell removed)',
  ),
  // N1: at v40 a breast line stayed at the Y1 bone yield (171077 publishes
  // no half breast); v43 (Y3) moves it to 2646170 at AH-102 584's meat 65.
  (
    '0496-white-chicken-chili.yaml',
    0,
    '3 pounds bone-in, skin-on chicken breast halves, trimmed',
    2646170,
    '884.50',
    'counted',
    null,
    'from 3 pound × 0.65 edible · approximate (USDA AH-102 item 584: chicken breast, raw → meat 65 % (50–77))',
  ),
  // N2: at v40 the whole turkey kept the interim 0.608; v43 (Y5) 0.6515.
  (
    '0154-classic-roast-turkey.yaml',
    1,
    '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and reserved for gravy',
    171081,
    // RE-PIN (M48): 4137.40 → 3841.87 g, the printed 12–14 lb range at its
    // midpoint (was its top); the basis names the range.
    '3841.87',
    'counted',
    null,
    'from the printed weight (12–14 lb, the midpoint) × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))',
  ),
  // N3: mussels by weight stayed on FNDDS 2706350, held. RE-PIN (M47
  // batch, v49 Q11): moved to raw SR 174216 at AH-102 item 1531, counted.
  (
    '0294-oven-steamed-mussels.yaml',
    6,
    '4 pounds mussels, scrubbed and debearded',
    174216,
    '526.17',
    'counted',
    null,
    'from 4 pound × 0.29 edible · approximate (USDA AH-102 item 1531: mussels, whole → drained solids, raw 29 % (25–33); the liquor in the pot is not counted)',
  ),
  // N4: no drained ÷ whole read at v40; since v42 (the owner's ruling (b))
  // the chickpea pair's 0.565 (nutrition_v42_test.dart).
  (
    '0044-mediterranean-chopped-salad.yaml',
    6,
    '1 (15-ounce) can chickpeas, drained and rinsed',
    2644288,
    '240.26',
    'counted',
    null,
    "from the printed weight × 0.565 drained · approximate (drained weight: FDC's canned chickpea pair, 253 g of 448 g)",
  ),
];

/// v43 (Y2): pieces on the meat-only 171052, AH-102's derived meat figure.
const String _piecesMeat =
    '× 0.60 edible · approximate (derived from USDA AH-102 items 584–586 by '
    "583's carcass shares: pieces (breast, thigh, drumstick), raw → meat "
    '60.5 %)';
