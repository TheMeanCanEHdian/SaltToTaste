// Real corpus lines wrap across adjacent literals; the table keeps each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v43, the poultry half of the USDA Agriculture Handbook 102
/// yields (the owner's 2026-10-06 rulings Y1–Y7, Y12, Y13): a bone-in bird
/// part reads the AH-102 raw figure of the part its line names first
/// ([ah102Parts], [birdPartOf]), the record deciding meat or meat and skin
/// ([ah102Records]). Each row is a real corpus line at the record, grams
/// and basis the cache-only replay of snapshot 19 derives at v43.
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v43p');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  /// [file]'s line at [position], alone in a recipe with its steps and prep
  /// notes, matched and computed on the fixtures.
  Future<(SaltDatabase, Recipe)> computed(String file, int position) async {
    final from = loadCorpusRecipe(file);
    final db = tempDb()..upsertSource(slug: 'src', name: 'Test', type: 'book');
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      prepNotes: from.prepNotes,
      steps: from.steps,
      ingredients: [
        IngredientGroup(items: [nutritionLines(from)[position]]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
    await matchAndCompute(db, FixtureProvider(), recipe);
    return (db, recipe);
  }

  group('in their recipes', skip: skipIfNoCorpus, () {
    test('each bird line at its record, grams and basis', () async {
      for (final (file, position, raw, fdcId, grams, basis) in _pins) {
        final (db, recipe) = await computed(file, position);
        final line = recipe.ingredients.single.items.single;
        expect(line.raw, raw, reason: file);
        final row = db.ingredientMatchesFor('r').single;
        expect(row.fdcId, fdcId, reason: raw);
        expect(row.status, 'auto', reason: raw);
        expect(row.hold, isNull, reason: raw);
        expect(row.grams?.toStringAsFixed(2), grams, reason: raw);
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: raw,
        );
      }
    });

    test('Y13: the record decides — a pick of the meat-only thigh for a '
        'thigh whose skin is eaten reads the meat figure', () async {
      final (db, recipe) = await computed('0524-chicken-teriyaki.yaml', 0);
      final line = recipe.ingredients.single.items.single;
      expect(skinDiscarded(recipe, line), isFalse);
      String rowOf() {
        final row = db.ingredientMatchesFor('r').single;
        return '${row.fdcId} ${row.grams?.toStringAsFixed(2)} ${row.status}';
      }

      // Left on the skin-on record: meat and skin. RE-PIN (M48): the
      // "(5- to 6-ounce)" thighs at their midpoint (was 952.54, the top).
      expect(rowOf(), '2727567 873.16 auto');
      await applyMatchOverride(db, FixtureProvider(), recipe, 0, {
        'raw': line.raw,
        'fdc_id': 2646171,
      });
      // Picked onto the meat-only record: 586's meat 59, not v39's skin
      // trip (meat and skin grams on a meat record). RE-PIN (M48): at the
      // midpoint, 8 × 156 g (was 802.86, 8 × 170 g); the basis names it.
      expect(rowOf(), '2646171 735.95 overridden');
      expect(
        gramBasisFor(
          db,
          line,
          db.ingredientMatchesFor('r').single,
          recipe: recipe,
        ),
        '8 × 156 g (printed 5–6 oz, the midpoint) × 0.59 edible · approximate (USDA AH-102 item 586: chicken thigh, raw → meat 59 % (48–68))',
      );
    });

    test('the skin signal: all five breast lines trip, Hearty Chicken '
        'Noodle Soup\'s "reserved cooked chicken" included', () {
      bool trips(String file, int position) {
        final recipe = loadCorpusRecipe(file);
        return skinDiscarded(recipe, nutritionLines(recipe)[position]);
      }

      for (final (file, position) in [
        ('0002-hearty-chicken-noodle-soup.yaml', 9),
        ('0003-old-fashioned-slow-cooker-chicken-noodle-soup.yaml', 12),
        ('0454-french-style-chicken-and-stuffing-in-a-pot.yaml', 15),
        ('0473-tortilla-soup.yaml', 3),
        ('0496-white-chicken-chili.yaml', 0),
      ]) {
        expect(trips(file, position), isTrue, reason: '$file|$position');
      }
    });
  });

  test('birdPartOf: whole, then pieces, then the part named first, then '
      "the record's own part", () async {
    final provider = FixtureProvider();
    final chicken = (await provider.food(171447))!;
    final breast = (await provider.food(2727569))!;
    final thighs = (await provider.food(171533))!;
    final legs = (await provider.food(172378))!;
    for (final (raw, food, part) in [
      (
        '1 (3½ to 4-pound) whole chicken, cut into 8 pieces (4 breast pieces, 2 thighs, 2 drumsticks), wings discarded, and trimmed',
        chicken,
        'whole',
      ),
      (
        '2½–3 pounds bone-in split chicken breasts and/or leg quarters, trimmed',
        breast,
        'pieces',
      ),
      (
        '3 pounds split bone-in chicken breast (or thighs or drumsticks), skin-on, trimmed of excess fat',
        breast,
        'breast',
      ),
      (
        '1½–2 pounds chicken leg quarters, separated into drumsticks and thighs, trimmed',
        legs,
        'leg',
      ),
      (
        '4 (1½- to 2-pound) turkey leg quarters, trimmed',
        thighs,
        'leg quarter',
      ),
      ('4 pounds turkey drumsticks and thighs, trimmed', thighs, 'leg'),
    ]) {
      expect(birdPartOf(raw, food), part, reason: raw);
    }
  });

  test(
    "the derived figures are the printed items by 583's carcass shares",
    () {
      expect(ah102Parts['chicken leg']!.skin, closeTo(0.6669, 1e-4));
      expect(ah102Parts['chicken leg']!.meat, closeTo(0.5711, 1e-4));
      expect(ah102Parts['chicken pieces']!.skin, closeTo(0.6983, 1e-4));
      expect(ah102Parts['chicken pieces']!.meat, closeTo(0.6049, 1e-4));
      expect(ah102Parts['turkey whole']!.skin, closeTo(0.6515, 1e-4));
      // Kept (Y4): no figure, the record's own.
      expect(ah102Parts.containsKey('chicken whole'), isFalse);
      // RE-PIN (M60 batch, v59): Y7 closed — the bone-in turkey breast is
      // derived from 2591's breast 33 of the breast-plus-rib 43 × 2593's
      // 87 % (meat 78 %); 171093 is a meat-and-skin turkey record.
      expect(ah102Parts['turkey breast']!.skin, closeTo(0.6677, 1e-4));
      expect(ah102Parts['turkey breast']!.meat, closeTo(0.5986, 1e-4));
      expect(ah102Records[171093], (species: 'turkey', meatOnly: false));
    },
  );
}

/// (corpus file, position, raw, fdc id, grams, basis) — every row bucket
/// counted, status auto, no hold.
const List<(String, int, String, int, String, String)> _pins = [
  // Y12: a skin-discarded thigh or leg reads its meat figure in one step.
  (
    '0455-chicken-provencal.yaml',
    0,
    '8 (5- to 6-ounce) bone-in, skin-on chicken thighs, trimmed',
    2646171,
    // RE-PIN (M48): 802.86 → 735.95 g, the printed 5–6 oz range at its midpoint
    // (was its top); the basis names the range.
    '735.95',
    '8 × 156 g (printed 5–6 oz, the midpoint) × 0.59 edible · approximate (USDA AH-102 item 586: chicken thigh, raw → meat 59 % (48–68))',
  ),
  (
    '0461-simplified-cassoulet-with-pork-and-kielbasa.yaml',
    2,
    '10 (5- to 6-ounce) bone-in, skin-on chicken thighs, trimmed and skin removed',
    2646171,
    // RE-PIN (M48): 1003.57 → 919.94 g, the printed 5–6 oz range at its
    // midpoint (was its top); the basis names the range.
    '919.94',
    '10 × 156 g (printed 5–6 oz, the midpoint) × 0.59 edible · approximate (USDA AH-102 item 586: chicken thigh, raw → meat 59 % (48–68))',
  ),
  (
    '0634-barbecued-pulled-chicken.yaml',
    3,
    '8 (14-ounce) chicken leg quarters, trimmed',
    173619,
    '1813.36',
    "8 × 397 g (printed weight) × 0.57 edible · approximate (derived from USDA AH-102 items 585–586 by 583's carcass shares: leg (thigh + drumstick), raw → meat 57.1 %; a leg quarter's back portion is not in this figure)",
  ),
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    16,
    '2 (12-ounce) bone-in chicken leg quarters, trimmed',
    173619,
    '388.58',
    "2 × 340 g (printed weight) × 0.57 edible · approximate (derived from USDA AH-102 items 585–586 by 583's carcass shares: leg (thigh + drumstick), raw → meat 57.1 %; a leg quarter's back portion is not in this figure)",
  ),
  // Y3: a skin-discarded breast moves to 2646170 at 584 meat.
  (
    '0003-old-fashioned-slow-cooker-chicken-noodle-soup.yaml',
    12,
    '1 (12-ounce) bone-in, skin-on split chicken breast, trimmed',
    2646170,
    '221.13',
    'from the printed weight × 0.65 edible · approximate (USDA AH-102 item 584: chicken breast, raw → meat 65 % (50–77))',
  ),
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    15,
    '2 (12-ounce) bone-in split chicken breasts, trimmed',
    2646170,
    '442.25',
    '2 × 340 g (printed weight) × 0.65 edible · approximate (USDA AH-102 item 584: chicken breast, raw → meat 65 % (50–77))',
  ),
  (
    '0473-tortilla-soup.yaml',
    3,
    '2 bone-in, skin-on split chicken breasts (about 1½ pounds) or 4 bone-in, skin-on chicken thighs (about 1¼ pounds), skin removed and trimmed',
    2646170,
    '442.25',
    'from 1 1/2 pound × 0.65 edible · approximate (USDA AH-102 item 584: chicken breast, raw → meat 65 % (50–77))',
  ),
  (
    '0496-white-chicken-chili.yaml',
    0,
    '3 pounds bone-in, skin-on chicken breast halves, trimmed',
    2646170,
    '884.50',
    'from 3 pound × 0.65 edible · approximate (USDA AH-102 item 584: chicken breast, raw → meat 65 % (50–77))',
  ),
  // Closer 1 (D1): "the reserved cooked chicken" no longer vetoes the skin
  // signal, so the fifth breast line moves too.
  (
    '0002-hearty-chicken-noodle-soup.yaml',
    9,
    '2 (12-ounce) bone-in, skin-on chicken breast halves, cut in half crosswise',
    2646170,
    '442.25',
    '2 × 340 g (printed weight) × 0.65 edible · approximate (USDA AH-102 item 584: chicken breast, raw → meat 65 % (50–77))',
  ),
  // Y1: the part the line names, skin kept.
  (
    '0120-roasted-bone-in-chicken-breasts.yaml',
    0,
    '4 (10- to 12-ounce) bone-in chicken breasts, trimmed',
    2727569,
    // RE-PIN (M48): 1006.97 → 923.06 g, the printed 10–12 oz range at its
    // midpoint (was its top); the basis names the range.
    '923.06',
    '4 × 312 g (printed 10–12 oz, the midpoint) × 0.74 edible · approximate (USDA AH-102 item 584: chicken breast, raw → meat and skin 74 % (59–84))',
  ),
  (
    '0524-chicken-teriyaki.yaml',
    0,
    '8 (5- to 6-ounce) bone-in, skin-on chicken thighs, trimmed',
    2727567,
    // RE-PIN (M48): 952.54 → 873.16 g, the printed 5–6 oz range at its midpoint
    // (was its top); the basis names the range.
    '873.16',
    '8 × 156 g (printed 5–6 oz, the midpoint) × 0.70 edible · approximate (USDA AH-102 item 586: chicken thigh, raw → meat and skin 70 % (63–81))',
  ),
  (
    '0630-grilled-spice-rubbed-chicken-drumsticks.yaml',
    1,
    '5 pounds chicken drumsticks',
    2727566,
    '1428.81',
    'from 5 pound × 0.63 edible · approximate (USDA AH-102 item 585: chicken drumstick, raw → meat and skin 63 % (50–75))',
  ),
  (
    '0151-buffalo-wings.yaml',
    10,
    '18 chicken wings (about 3 pounds), wings separated into 2 parts at joint and wingtips removed',
    2727568,
    '680.39',
    'from 3 pound × 0.50 edible · approximate (USDA AH-102 item 590: chicken wing, raw → meat and skin 50 % (41–60))',
  ),
  (
    '0450-chicken-bouillabaisse.yaml',
    0,
    '3 pounds split bone-in chicken breast (or thighs or drumsticks), skin-on, trimmed of excess fat',
    2727569,
    '1006.97',
    'from 3 pound × 0.74 edible · approximate (USDA AH-102 item 584: chicken breast, raw → meat and skin 74 % (59–84))',
  ),
  // Y2: the derived leg and pieces.
  (
    '0125-braised-chicken-with-mustard-and-herbs.yaml',
    2,
    '1½–2 pounds chicken leg quarters, separated into drumsticks and thighs, trimmed',
    172378,
    '529.41',
    // RE-PIN (M48): the basis names the range (1 1/2–2 pound, already read at
    // its midpoint; grams unchanged).
    "from 1 1/2–2 pound (the midpoint) × 0.67 edible · approximate (derived from USDA AH-102 items 585–586 by 583's carcass shares: leg (thigh + drumstick), raw → meat and skin 66.7 %; a leg quarter's back portion is not in this figure)",
  ),
  (
    '0631-peri-peri-grilled-chicken.yaml',
    13,
    '6 pounds bone-in chicken pieces (breasts, thighs, and/or drumsticks), trimmed',
    171447,
    '1900.33',
    "from 6 pound × 0.70 edible · approximate (derived from USDA AH-102 items 584–586 by 583's carcass shares: pieces (breast, thigh, drumstick), raw → meat and skin 69.8 %)",
  ),
  (
    '0124-chicken-marbella.yaml',
    10,
    '2½–3 pounds bone-in split chicken breasts and/or leg quarters, trimmed',
    2727569,
    '870.99',
    // RE-PIN (M48): the basis names the range (2 1/2–3 pound, already read at
    // its midpoint; grams unchanged).
    "from 2 1/2–3 pound (the midpoint) × 0.70 edible · approximate (derived from USDA AH-102 items 584–586 by 583's carcass shares: pieces (breast, thigh, drumstick), raw → meat and skin 69.8 %)",
  ),
  (
    '0569-tandoori-chicken.yaml',
    9,
    '3 pounds bone-in, skin-on chicken pieces (split breasts cut in half, drumsticks, and/or thighs), trimmed and skin removed',
    171052,
    '823.16',
    "from 3 pound × 0.60 edible · approximate (derived from USDA AH-102 items 584–586 by 583's carcass shares: pieces (breast, thigh, drumstick), raw → meat 60.5 %)",
  ),
  // Y5: the whole turkey.
  (
    '0154-classic-roast-turkey.yaml',
    1,
    '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and reserved for gravy',
    171081,
    // RE-PIN (M48): 4137.40 → 3841.87 g, the printed 12–14 lb range at its
    // midpoint (was its top); the basis names the range.
    '3841.87',
    'from the printed weight (12–14 lb, the midpoint) × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))',
  ),
  (
    '0155-roast-turkey-for-a-crowd.yaml',
    6,
    '1 (18- to 22-pound) frozen Butterball or kosher turkey, fully thawed; giblets, neck, and tailpiece removed and reserved for gravy',
    171081,
    // RE-PIN (M48): 6501.63 → 5910.57 g, the printed 18–22 lb range at its
    // midpoint (was its top); the basis names the range.
    '5910.57',
    'from the printed weight (18–22 lb, the midpoint) × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))',
  ),
  (
    '0169-roasted-brined-turkey.yaml',
    1,
    '1 turkey (12–22 pounds gross weight), rinsed thoroughly, giblets and neck reserved for gravy, if making',
    171081,
    // RE-PIN (M48): 6501.63 → 5023.98 g, the printed 12–22 lb range at its
    // midpoint (was its top); the basis names the range.
    '5023.98',
    'from the printed weight (12–22 lb, the midpoint) × 0.65 edible · approximate (USDA AH-102 turkey dressing data, 12 lb and over (neck and giblets off 78 of 85); carcass → meat and skin, item 2592, fryer-roaster class, 71 % (67–75))',
  ),
  // Y6: turkey parts.
  (
    '1077-turkey-thigh-confit-with-citrus-mustard-sauce.yaml',
    5,
    '4 pounds bone-in turkey thighs',
    171533,
    '1487.78',
    'from 4 pound × 0.82 edible · approximate (USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class → meat and skin 82 % (77–85))',
  ),
  (
    '0172-braised-turkey.yaml',
    3,
    '4 pounds turkey drumsticks and thighs, trimmed',
    171533,
    '1360.78',
    'from 4 pound × 0.75 edible · approximate (USDA AH-102 item 2596: turkey leg, raw, fryer-roaster class → meat and skin 75 % (70–79)) · approximation (counted as Turkey, retail parts, thigh, meat and skin, raw)',
  ),
  (
    '0163-turkey-and-gravy-for-a-crowd.yaml',
    12,
    '4 (1½- to 2-pound) turkey leg quarters, trimmed',
    171533,
    // RE-PIN (M48): 2576.40 → 2254.35 g, the printed 1½–2 lb range at its
    // midpoint (was its top); the basis names the range.
    '2254.35',
    '4 × 794 g (printed 1½–2 lb, the midpoint) × 0.71 edible · approximate (USDA AH-102 item 2595: turkey leg quarter, raw, fryer-roaster class → meat and skin 71 % (69–73)) · approximation (counted as Turkey, retail parts, thigh, meat and skin, raw)',
  ),
  (
    '0309-juicy-grilled-turkey-burgers.yaml',
    0,
    '1 (2-pound) bone-in turkey thigh, skinned, boned, trimmed, and cut into ½-inch pieces',
    174518,
    '698.53',
    'from the printed weight × 0.77 edible · approximate (USDA AH-102 item 2598: turkey thigh, raw, fryer-roaster class → meat 77 % (76–80))',
  ),
  // RE-PIN (M50 batch, v50, Q20 (iii)): the steps "transfer the wings to a
  // dinner plate to reserve for another use" — 0 g (was 585.13 g, the
  // AH-102 item 2602 wing yield, which nutrition_v50_test.dart keeps pinned
  // on the line's own weighing, lineGrams).
  (
    '0178-baked-bread-stuffing-with-sausage-dried-cherries-and-pecans.yaml',
    1,
    '3 pounds turkey wings, divided at joints',
    171497,
    '0.00',
    'reserved for another use (step 7) — counted as 0 g',
  ),
  // Unchanged: whole chickens (Y4), the deferred breast (Y7), per-item and hen portions.
  (
    '0134-perfect-roast-chicken.yaml',
    2,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    // RE-PIN (M48): 1104.00 → 1035.00 g, the printed 3½–4 lb range at its
    // midpoint (was its top); the basis names the range.
    '1035.00',
    'from the printed weight (3½–4 lb, the midpoint) × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0004-pressure-cooker-chicken-noodle-soup.yaml',
    8,
    '1 (4-pound) whole chicken, giblets discarded',
    171052,
    '788.00',
    'from the printed weight × 0.43 edible (USDA ready-to-cook yield)',
  ),
  (
    '0637-grilled-lemon-chicken-with-rosemary.yaml',
    0,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171052,
    // RE-PIN (M48): 788.00 → 738.75 g, the printed 3½–4 lb range at its
    // midpoint (was its top); the basis names the range.
    '738.75',
    "from the printed weight (3½–4 lb, the midpoint) × 0.43 edible (USDA ready-to-cook yield) · approximate (skin discarded except the wings; the bird's meat-only yield)",
  ),
  (
    '0150-oven-fried-chicken.yaml',
    6,
    '4 whole chicken legs, separated into drumsticks and thighs and skin removed',
    173619,
    '1060.00',
    '4 · USDA per-item weight',
  ),
  (
    '0147-roasted-cornish-game-hens.yaml',
    0,
    '4 (1¼- to 1½-pound) Cornish game hens, giblets discarded',
    171507,
    '1344.00',
    '4 × 336 g (USDA edible bird portion)',
  ),
  (
    '1126-porchetta-style-turkey-breast.yaml',
    8,
    '1 (7- to 8-pound) bone-in turkey breast',
    171093,
    // RE-PIN (M48): 2208.00 → 2070.00 g, the printed 7–8 lb range at its
    // midpoint (was its top); the basis names the range.
    // RE-PIN (M60 batch, v59): 2070.00 → 2271.39 g, AH-102's derived
    // bone-in turkey breast 66.77 % (2591 × 2593), Y7 closed.
    '2271.39',
    "from the printed weight (7–8 lb, the midpoint) × 0.67 edible · approximate (derived from USDA AH-102 items 2591 and 2593, fryer-roaster class: a breast sold with its upper back (rib) attached — the breast's meat and skin, 87 % (85–89) of its 33 of 43 parts, 66.8 %; the back is not counted)",
  ),
];
