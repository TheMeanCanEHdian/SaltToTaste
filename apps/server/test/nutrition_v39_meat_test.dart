// Real corpus lines wrap across adjacent literals; the table keeps each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// Matcher v39, the meat half of edible yields part 1 (the owner's ruling
/// 2026-10-05 on prep39/plan.md Q1, Q3, Q4): Y1 the bone-in class yields
/// ([boneInClassYields], revising CP6 #11 and #5), Y2 the five shellfish
/// lines counted rather than held `in_shell` ([shellCounted]), Y3 a
/// skin-discarded thigh or leg on its meat-only record ([skinDiscarded],
/// [skinShares]). Each row is a real corpus line at the record, grams,
/// bucket and basis the cache-only replay of snapshot 16 derives at v39;
/// the answers are copied from snapshot 16 (tool/record_fdc_fixtures.dart
/// --from-db).
void main() {
  SaltDatabase tempDb() {
    final dir = Directory.systemTemp.createTempSync('salt-v39');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = SaltDatabase.open('${dir.path}/salt.db');
    addTearDown(db.dispose);
    return db;
  }

  IngredientLine lineOf(String raw) {
    final parsed = parseIngredientLine(raw);
    return IngredientLine(raw: raw, item: parsed.item, amounts: parsed.amounts);
  }

  /// [raw] alone in a recipe — or [from]'s line at [position] with its
  /// steps and prep notes — matched and computed on the fixtures; its one
  /// row and line.
  Future<(SaltDatabase, IngredientMatchRow, IngredientLine)> computed(
    String raw, {
    Recipe? from,
    int? position,
  }) async {
    final line = from == null ? lineOf(raw) : nutritionLines(from)[position!];
    final db = tempDb()..upsertSource(slug: 'src', name: 'Test', type: 'book');
    final recipe = Recipe(
      id: 'r',
      title: 'r',
      slug: 'r',
      source: const RecipeSource(name: 'Test', type: 'book'),
      prepNotes: from?.prepNotes,
      steps: from?.steps ?? const [],
      ingredients: [
        IngredientGroup(items: [line]),
      ],
    );
    db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: 'hr');
    await matchAndCompute(db, FixtureProvider(), recipe);
    return (db, db.ingredientMatchesFor('r').single, line);
  }

  void expectRow(
    SaltDatabase db,
    IngredientMatchRow row,
    IngredientLine line,
    (String, int, String, int?, String?, String, String?) pin,
  ) {
    final (file, _, raw, fdcId, grams, bucket, basis) = pin;
    expect(row.fdcId, fdcId, reason: '$file: $raw');
    expect(row.grams?.toStringAsFixed(2), grams, reason: raw);
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
    // As the matches GET reads it: on the stored recipe (the skin trip).
    expect(
      gramBasisFor(db, line, row, recipe: db.recipeByIdOrSlug('r')!.recipe),
      basis,
      reason: raw,
    );
  }

  test('Y1 class yields, Y2 counted shellfish and their non-trips, line '
      'by line', () async {
    for (final pin in _single) {
      final (db, row, line) = await computed(pin.$3);
      expectRow(db, row, line, pin);
    }
  });

  group('in their recipes', skip: skipIfNoCorpus, () {
    test('Y2 shrimp eaten shell and all; Y3 the skin discarded on its '
        'meat-only record, stacked on the bone yield', () async {
      for (final pin in _inRecipe) {
        final (db, row, line) = await computed(
          pin.$3,
          from: loadCorpusRecipe(pin.$1),
          position: pin.$2,
        );
        expect(line.raw, pin.$3, reason: pin.$1);
        expectRow(db, row, line, pin);
      }
    });

    test('every row is a real corpus line at its position', () {
      for (final (file, position, raw, _, _, _, _) in _single) {
        final line = nutritionLines(loadCorpusRecipe(file))[position];
        expect(line.raw, raw, reason: file);
        expect(lineOf(raw).amounts, line.amounts, reason: raw);
      }
    });

    test('the skin signal trips exactly the 13 thigh and leg lines plan Q4 '
        'names, and none of its non-trips', () {
      bool trips(String file, int position) {
        final recipe = loadCorpusRecipe(file);
        return skinDiscarded(recipe, nutritionLines(recipe)[position]);
      }

      for (final (file, position) in _skinTrips) {
        expect(trips(file, position), isTrue, reason: '$file|$position');
      }
      for (final (file, position) in _skinNonTrips) {
        expect(trips(file, position), isFalse, reason: '$file|$position');
      }
    });

    test('a Confirm of a moved row decides the skin-on record: the skin '
        'share never reaches a thigh whose skin is eaten', () async {
      // The closer's pin for the round-1 verifier's D-1: Chicken
      // Provençal's thighs (skin discarded) confirmed with apply_to_all;
      // Chicken Teriyaki's (the same key, the skin eaten) stays on the
      // skin-on record at the bone yield; Skillet Jambalaya's (discarded)
      // still moves. Three real lines, each with its recipe's own steps.
      final db = tempDb()
        ..upsertSource(slug: 'src', name: 'Test', type: 'book');
      Future<Recipe> stored(String id, String file) async {
        final from = loadCorpusRecipe(file);
        final recipe = Recipe(
          id: id,
          title: id,
          slug: id,
          source: const RecipeSource(name: 'Test', type: 'book'),
          prepNotes: from.prepNotes,
          steps: from.steps,
          ingredients: [
            IngredientGroup(items: [nutritionLines(from)[0]]),
          ],
        );
        db.upsertRecipe(recipe, sourceSlug: 'src', contentHash: id);
        await matchAndCompute(db, FixtureProvider(), recipe);
        return recipe;
      }

      final provencal = await stored(
        'provencal',
        '0455-chicken-provencal.yaml',
      );
      final teriyaki = await stored('teriyaki', '0524-chicken-teriyaki.yaml');
      final jambalaya = await stored(
        'jambalaya',
        '0079-skillet-jambalaya.yaml',
      );
      String rowOf(Recipe recipe) {
        final row = db.ingredientMatchesFor(recipe.id).single;
        return '${row.fdcId} ${row.grams?.toStringAsFixed(2)} ${row.status}';
      }

      expect(rowOf(provencal), '2646171 657.92 auto');
      expect(rowOf(teriyaki), '2727567 828.00 auto');
      expect(rowOf(jambalaya), '2646171 328.96 auto');
      final line = nutritionLines(provencal)[0];
      await applyMatchOverride(db, FixtureProvider(), provencal, 0, {
        'raw': line.raw,
        'confirmed': true,
        'apply_to_all': true,
      });
      // This line keeps what it showed; the key decides the record bought.
      expect(rowOf(provencal), '2646171 657.92 confirmed');
      expect(db.decisionFor(lineKeyOf(line))!.fdcId, 2727567);
      for (var pass = 0; pass < 2; pass++) {
        // As apply_to_all wrote them, then as their next compute derives.
        expect(rowOf(teriyaki), '2727567 828.00 auto', reason: '$pass');
        expect(rowOf(jambalaya), '2646171 328.96 auto', reason: '$pass');
        await matchAndCompute(db, FixtureProvider(), teriyaki);
        await matchAndCompute(db, FixtureProvider(), jambalaya);
      }
      final shown = db.ingredientMatchesFor('teriyaki').single;
      expect(shown.confidence, 1);
      expect(
        gramBasisFor(
          db,
          nutritionLines(teriyaki)[0],
          shown,
          recipe: teriyaki,
        ),
        isNot(contains('skin discarded')),
      );
      // A person's own pick of the meat-only record on a line whose skin
      // is eaten: their food, at the bone yield — no skin share.
      await applyMatchOverride(db, FixtureProvider(), teriyaki, 0, {
        'raw': nutritionLines(teriyaki)[0].raw,
        'fdc_id': 2646171,
      });
      expect(rowOf(teriyaki), '2646171 828.00 overridden');
    });
  });

  test('the class figures are the FDC portions they cite', () async {
    final provider = FixtureProvider();
    final chicken = (await provider.food(171447))!;
    final readyToCook = chicken.portions.singleWhere(
      (p) => (p.description ?? '').contains('ready-to-cook'),
    );
    expect(
      boneInClassYields[2727567]!.share,
      readyToCook.gramWeight / 453.59237,
    );
    final oxtail = (await provider.food(2705843))!;
    final yields = oxtail.portions.singleWhere(
      (p) => p.description == '1 oz yields',
    );
    expect(boneInClassYields[2705843]!.share, yields.gramWeight / 28.349523125);
    final meat = (await provider.food(173619))!;
    final skin = (await provider.food(172378))!;
    double grams(FdcFood food, String description) => food.portions
        .singleWhere((p) => p.description == description)
        .gramWeight;
    expect(
      skinShares[2646171],
      grams(meat, 'thigh bone and skin removed') /
          grams(skin, 'thigh with skin'),
    );
    expect(
      skinShares[173619],
      grams(
            meat,
            'leg, bone and skin removed (Sum of drumstick+thigh+back meat only)',
          ) /
          grams(skin, 'leg, with skin (Sum of drumstick+thigh+back)'),
    );
    expect(boneInClassYields[173405]!.share, closeTo(0.6574, 1e-4));
    expect(boneInClassYields[167822]!.share, 133 / 201);
    expect(boneInClassYields[167853]!.share, 128 / 196);
    expect(boneInClassYields[168675]!.share, 288 / 380);
    // A cut BOUGHT skinless takes no meat share on the meat-only record,
    // only the bone yield. No corpus line is a bone-in skinless cut on
    // 2646171: synthesized (a stated negative-path exception).
    const bought = '1½ pounds bone-in, skinless chicken thighs';
    final parsed = parseIngredientLine(bought);
    final skinless = (await provider.food(2646171))!;
    final read = resolveGrams(
      amounts: parsed.amounts,
      food: skinless,
      normalizedItem: normalizeItem(parsed.item ?? bought),
      raw: bought,
    )!;
    expect(read.grams, closeTo(1.5 * 276, 0.01));
    expect(read.basis, isNot(contains('meat-only share')));
    // Stay gross: the line allows boneless; FDC has no ham-hock figure.
    expect(boneInClassYields.containsKey(173403), isFalse);
    expect(boneInClassYields.containsKey(2705900), isFalse);
  });
}

/// The 13 lines whose skin the recipe discards (plan Q4, prep39/skin_render.md).
const List<(String, int)> _skinTrips = [
  ('0003-old-fashioned-slow-cooker-chicken-noodle-soup.yaml', 0),
  ('0079-skillet-jambalaya.yaml', 0),
  ('0095-chicken-and-dumplings.yaml', 0),
  ('0095-lighter-chicken-and-dumplings.yaml', 0),
  ('0101-arroz-con-pollo-latin-style-chicken-and-rice.yaml', 4),
  (
    '0126-pollo-en-pepitoria-spanish-braised-chicken-with-sherry-and-saffron.yaml',
    0,
  ),
  ('0403-italian-chicken-soup-with-parmesan-dumplings.yaml', 0),
  ('0454-french-style-chicken-and-stuffing-in-a-pot.yaml', 16),
  ('0455-chicken-provencal.yaml', 0),
  ('0461-simplified-cassoulet-with-pork-and-kielbasa.yaml', 2),
  ('0566-chicken-biryani.yaml', 11),
  ('0634-barbecued-pulled-chicken.yaml', 3),
  ('1179-chicken-and-spiced-freekeh-with-cilantro-and-preserved-lemon.yaml', 0),
];

/// Skin lines the signal must leave alone: the other 11 bone-in thighs and
/// legs (the skin is eaten, or only the tapered pieces' and "if desired"),
/// and the plan's non-trips — skin laid or peeled back, stretched over,
/// reserved, trimmed only, the "skin is … crispy" sentence.
const List<(String, int)> _skinNonTrips = [
  ('0101-chicken-vesuvio.yaml', 0),
  ('0125-braised-chicken-with-mustard-and-herbs.yaml', 2),
  ('0125-oven-roasted-chicken-thighs.yaml', 0),
  ('0128-filipino-chicken-adobo.yaml', 0),
  ('0129-mahogany-chicken-thighs.yaml', 6),
  ('0422-chicken-canzanese.yaml', 3),
  ('0524-chicken-teriyaki.yaml', 0),
  ('0629-best-grilled-chicken-thighs.yaml', 0),
  ('1092-poulet-au-vinaigre-chicken-with-vinegar.yaml', 0),
  ('1178-chicken-teriyaki.yaml', 0),
  ('0120-roasted-bone-in-chicken-breasts.yaml', 0),
  ('0176-grillroasted-boneless-turkey-breast.yaml', 1),
  ('1126-porchetta-style-turkey-breast.yaml', 8),
  ('0125-braised-chicken-with-mustard-and-herbs.yaml', 1),
  ('0137-one-hour-broiled-chicken-and-pan-sauce.yaml', 0),
  ('0121-crispy-skinned-chicken-breasts-with-vinegar-pepper-pan-sauce.yaml', 0),
  // Skin set aside and rendered (coq au Riesling), taken "if desired" (the
  // multicooker chicken in a pot).
  ('0127-coq-au-riesling.yaml', 0),
  ('1177-multicooker-chicken-in-a-pot-with-lemon-herb-sauce.yaml', 7),
  // "remove the skin and bones from the reserved cooked chicken and
  // discard": the literal signal reads "reserve" in the skin sentence, so
  // this breast line — one of plan Q4's ten provisional lines (part 2) —
  // does not trip (reported to the orchestrator; v39 builds no breast swap).
  ('0002-hearty-chicken-noodle-soup.yaml', 9),
];

/// (corpus file, position, raw, fdc id, grams, bucket, basis).
const List<(String, int, String, int?, String?, String, String?)> _single = [
  (
    '0618-texas-style-barbecued-beef-ribs.yaml',
    17,
    '3–4 beef rib slabs (3 to 4 ribs per slab, about 5 pounds total), trimmed',
    173405,
    '1490.90',
    'counted',
    'from the printed weight × 0.66 edible · approximate (yield of bony beef, lamb and veal from FDC 167895 and 168242 (the median))',
  ),
  (
    '1126-porchetta-style-turkey-breast.yaml',
    8,
    '1 (7- to 8-pound) bone-in turkey breast',
    171093,
    '2208.00',
    'counted',
    'from the printed weight × 0.61 edible · approximate (yield of turkey parts (the chicken figure) from FDC 171447)',
  ),
  (
    '0222-best-prime-rib.yaml',
    0,
    '1 (7-pound) first-cut beef standing rib roast (3 bones), meat removed from bones, bones reserved',
    168675,
    '2406.42',
    'counted',
    'from the printed weight × 0.76 edible · approximate (yield of a bone-in roast (the pork butt figure) from FDC 167849)',
  ),
  (
    '0209-red-winebraised-pork-chops.yaml',
    1,
    '4 (10- to 12-ounce) bone-in pork blade chops, 1 inch thick',
    167822,
    '900.41',
    'counted',
    '4 × 340 g (printed weight) × 0.66 edible · approximate (yield of bone-in pork chops from FDC 168242)',
  ),
  (
    '0089-braised-oxtails-with-white-beans-tomatoes-and-aleppo-pepper.yaml',
    0,
    '4 pounds oxtails, trimmed',
    2705843,
    '1024.00',
    'counted',
    'from 4 pound × 0.56 edible · approximate (yield of oxtails from FDC 2705843)',
  ),
  (
    '0151-buffalo-wings.yaml',
    10,
    '18 chicken wings (about 3 pounds), wings separated into 2 parts at joint and wingtips removed',
    2727568,
    '828.00',
    'counted',
    'from 3 pound × 0.61 edible · approximate (yield of chicken parts from FDC 171447)',
  ),
  (
    '0462-french-style-pork-stew.yaml',
    9,
    '1 meaty smoked ham shank or 2–3 smoked ham hocks (1¼ pounds)',
    2705900,
    '566.99',
    'counted',
    'from 1 1/4 pound · approximate (gross weight, no USDA refuse portion)',
  ),
  (
    '0203-skillet-barbecued-pork-chops.yaml',
    1,
    '4 (8- to 10-ounce) bone-in rib loin pork chops, ¾ to 1 inch thick, trimmed of excess fat',
    168242,
    '750.34',
    'counted',
    '4 × 283 g (printed weight) × 0.66 edible (USDA refuse)',
  ),
  (
    '0637-grilled-lemon-chicken-with-rosemary.yaml',
    0,
    '1 (3½- to 4-pound) whole chicken, giblets discarded',
    171447,
    '1104.00',
    'counted',
    'from the printed weight × 0.61 edible (USDA ready-to-cook yield)',
  ),
  (
    '0150-oven-fried-chicken.yaml',
    6,
    '4 whole chicken legs, separated into drumsticks and thighs and skin removed',
    173619,
    '1060.00',
    'counted',
    '4 · USDA per-item weight',
  ),
  (
    '0092-simple-pot-au-feu.yaml',
    2,
    '1½ pounds marrow bones',
    169800,
    '680.39',
    'check',
    'from 1 1/2 pound',
  ),
  (
    '0482-tinga-de-pollo-shredded-chicken-tacos.yaml',
    0,
    '2 pounds boneless, skinless chicken thighs, trimmed',
    2646171,
    '907.18',
    'counted',
    'from 2 pound',
  ),
  (
    '0105-paella.yaml',
    14,
    '1 dozen mussels, scrubbed and debearded',
    2706350,
    '180.00',
    'counted',
    '12 · USDA per-item weight',
  ),
  (
    '1184-roasted-oysters-on-the-half-shell-with-mustard-butter.yaml',
    3,
    '24 oysters, 2½ to 3 inches long, well scrubbed',
    2706351,
    '360.00',
    'counted',
    '24 · USDA per-item weight',
  ),
  (
    '0291-flambeed-pan-roasted-lobster.yaml',
    0,
    '2 (1½- to 2-pound) live lobsters',
    2706349,
    '400.00',
    'counted',
    "2 × 200 g · approximate (FDC's 1-lobster portion)",
  ),
  (
    '0295-indoor-clambake.yaml',
    5,
    '2 (1½-pound) live lobsters',
    2706349,
    '400.00',
    'counted',
    "2 × 200 g · approximate (FDC's 1-lobster portion)",
  ),
  (
    '0034-new-england-clam-chowder.yaml',
    0,
    '7 pounds medium-size hard-shell clams, such as cherrystones, washed and scrubbed clean',
    2706338,
    '3175.14',
    'check',
    'from 7 pound · approximate (gross weight, no USDA refuse portion)',
  ),
  (
    '0294-oven-steamed-mussels.yaml',
    6,
    '4 pounds mussels, scrubbed and debearded',
    2706350,
    '1814.37',
    'check',
    'from 4 pound · approximate (gross weight, no USDA refuse portion)',
  ),
  (
    '0280-garlicky-roasted-shrimp-with-parsley-and-anise.yaml',
    1,
    '2 pounds shell-on jumbo shrimp (16 to 20 per pound)',
    175179,
    '907.18',
    'check',
    'from 2 pound · approximate (gross weight, no USDA refuse portion)',
  ),
  (
    '0295-indoor-clambake.yaml',
    0,
    '2 pounds small littleneck or cherrystone clams, scrubbed',
    2706338,
    '907.18',
    'check',
    'from 2 pound · approximate (gross weight, no USDA refuse portion)',
  ),
  (
    '0295-indoor-clambake.yaml',
    1,
    '2 pounds mussels, scrubbed and debearded',
    2706350,
    '907.18',
    'check',
    'from 2 pound · approximate (gross weight, no USDA refuse portion)',
  ),
];

const List<(String, int, String, int?, String?, String, String?)> _inRecipe = [
  (
    '0584-grilled-strip-or-rib-eye-steaks.yaml',
    0,
    '4 (12- to 16-ounce) strip or rib-eye steaks, with or without bone, 1¼ to 1½ inches thick',
    173403,
    '1814.37',
    'counted',
    '4 × 454 g (printed weight) · approximate (gross weight, no USDA refuse portion)',
  ),
  (
    '0154-classic-roast-turkey.yaml',
    1,
    '1 (12- to 14-pound) turkey; giblets, neck, and tailpiece removed and reserved for gravy',
    171081,
    '3864.00',
    'counted',
    'from the printed weight × 0.61 edible · approximate (yield of a whole turkey (interim: the chicken figure) from FDC 171447)',
  ),
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml',
    0,
    '1½ pounds shell-on shrimp (31 to 40 per pound)',
    175179,
    '680.39',
    'counted',
    'from 1 1/2 pound · approximate (gross weight, no USDA refuse portion)',
  ),
  (
    '0455-chicken-provencal.yaml',
    0,
    '8 (5- to 6-ounce) bone-in, skin-on chicken thighs, trimmed',
    2646171,
    '657.92',
    'counted',
    '8 × 170 g (printed weight) × 0.61 edible · approximate (yield of chicken parts from FDC 171447) × 0.79 meat · approximate (skin discarded; USDA meat-only share)',
  ),
  (
    '0461-simplified-cassoulet-with-pork-and-kielbasa.yaml',
    2,
    '10 (5- to 6-ounce) bone-in, skin-on chicken thighs, trimmed and skin removed',
    2646171,
    '822.40',
    'counted',
    '10 × 170 g (printed weight) × 0.61 edible · approximate (yield of chicken parts from FDC 171447) × 0.79 meat · approximate (skin discarded; USDA meat-only share)',
  ),
  (
    '0634-barbecued-pulled-chicken.yaml',
    3,
    '8 (14-ounce) chicken leg quarters, trimmed',
    173619,
    '1488.31',
    'counted',
    '8 × 397 g (printed weight) × 0.61 edible · approximate (yield of chicken parts from FDC 171447) × 0.77 meat · approximate (skin discarded; USDA meat-only share)',
  ),
  (
    '0125-braised-chicken-with-mustard-and-herbs.yaml',
    2,
    '1½–2 pounds chicken leg quarters, separated into drumsticks and thighs, trimmed',
    172378,
    '483.00',
    'counted',
    'from 1 1/2–2 pound × 0.61 edible · approximate (yield of chicken parts from FDC 171447)',
  ),
];
