// Real corpus lines wrap across adjacent literals; the tables keep each
// corpus line verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

// Matcher v50 (batch M50, discards and partial use; matcherVersion 49;
// prep47 design_v2 §1 Q16, Q17, Q18, Q20, Q21, Q7 and §2 "M50", decided
// under the owner's 2026-10-07 standing authorization; zero requests): a
// strain that presses or discards its solids zeroes the aromatics, herbs,
// whole spices and zest strips in it (never a ground spice, powder or
// paste, nor a line its own steps blend smooth — critic F3), cured pork
// and ground stock meat with it only when a sentence skims the pot's fat
// (else held `discarded_medium` — Q17, critic F4); a whole-piece aromatic
// removed and discarded by name, or tied into a bundle a step removes, is
// 0 g (only the discarded pieces of a "1 of the lemons" count line — F12);
// a printed part kept counts the kept part (a remainder subtracted, a
// potato's kept cooked weight to raw by FDC carbohydrate — F18 — a food
// reserved or the rest discarded 0 g); a kept volume, a dip left in the
// bowl and a marinade lifted from are flagged. Every value is the v50
// replay's row (rp43 on snapshot 21); the classifications read each REAL
// corpus recipe's own lines and steps (no FDC), the rows compute each WHOLE
// recipe on recorded real FDC answers (FixtureProvider; entries added
// --from-db from snapshot 21, JSON-equal), never the network.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

const _source = 'atk-tv-2023';

/// (file, section title or null, position, raw, the medium the line's own
/// recipe gives it — null: none).
const List<(String, String?, int, String, DiscardedMedium?)> _media = [
  // D1: the processor lines carried into the pot by "Add the vegetable mixture", the ground beef (skimmed), bay, peppercorns
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    0,
    '1 small onion, peeled and cut into rough ½-inch pieces',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    1,
    '1 small carrot, peeled and cut into rough ½-inch pieces',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    2,
    '8 ounces cremini mushrooms, trimmed and halved',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    3,
    '2 medium garlic cloves, peeled',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    5,
    '8 ounces 85 percent lean ground beef',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    10,
    '2 bay leaves',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    11,
    '2 teaspoons whole black peppercorns',
    DiscardedMedium.strainedSolid,
  ),
  // D1: oil, paste, wine, broth, gelatin pass the strainer
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    4,
    '1 tablespoon vegetable oil',
    null,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    6,
    '1 tablespoon tomato paste',
    null,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    7,
    '2 cups dry red wine',
    null,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    8,
    '4 cups beef broth',
    null,
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    12,
    '5 teaspoons unflavored gelatin',
    null,
  ),
  // D1 + Q17: the pancetta zeroed (its fat skimmed in step 3)
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    2,
    '4 ounces pancetta (about 4 slices), cut into ¼-inch cubes (see note)',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    3,
    '2 medium onions, chopped medium',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    4,
    '2 medium carrots, chopped medium',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    5,
    '2 medium celery ribs, chopped medium',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    7,
    '3 medium garlic cloves, minced or pressed through a garlic press (about 1 tablespoon)',
    DiscardedMedium.strainedSolid,
  ),
  // D1: the roast, the wine, the tomatoes kept
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    0,
    '1 (3½-pound) boneless chuck-eye roast',
    null,
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    10,
    '1 (750-milliliter) bottle Barolo wine',
    null,
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    11,
    '1 (14.5-ounce) can diced tomatoes, drained',
    null,
  ),
  // D1: the shallots strained and pressed
  (
    '0211-french-style-pork-chops-with-apples-and-calvados.yaml',
    null,
    4,
    '3 shallots, sliced',
    DiscardedMedium.strainedSolid,
  ),
  // D1: the apples named after the strain ("apple solids … into sauce")
  (
    '0211-french-style-pork-chops-with-apples-and-calvados.yaml',
    null,
    2,
    '4 Gala or Golden Delicious apples, peeled and cored',
    null,
  ),
  // Q17: no sentence skims the pan
  (
    '0211-french-style-pork-chops-with-apples-and-calvados.yaml',
    null,
    3,
    '2 slices bacon, cut into ½-inch pieces',
    DiscardedMedium.fatKept,
  ),
  // D1
  (
    '0402-italian-wedding-soup.yaml',
    null,
    0,
    '1 onion, chopped',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0402-italian-wedding-soup.yaml',
    null,
    2,
    '4 garlic cloves, peeled and smashed',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0402-italian-wedding-soup.yaml',
    null,
    6,
    '1 bay leaf',
    DiscardedMedium.strainedSolid,
  ),
  // F4: the only skim is the make-ahead parenthesis
  (
    '0402-italian-wedding-soup.yaml',
    null,
    4,
    '4 ounces ground pork',
    DiscardedMedium.fatKept,
  ),
  (
    '0402-italian-wedding-soup.yaml',
    null,
    5,
    '4 ounces 85 percent lean ground beef',
    DiscardedMedium.fatKept,
  ),
  // the meatball meat: mixer and bowl; "beef broth" is no mention of beef
  ('0402-italian-wedding-soup.yaml', null, 18, '6 ounces ground pork', null),
  (
    '0402-italian-wedding-soup.yaml',
    null,
    20,
    '6 ounces 85 percent lean ground beef',
    null,
  ),
  // F3: a ground spice passes the strainer (audit L214)
  (
    '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
    null,
    9,
    '1½ teaspoons ground cardamom',
    null,
  ),
  // F3: ground allspice
  (
    '0209-red-winebraised-pork-chops.yaml',
    null,
    8,
    '⅛ teaspoon ground allspice',
    null,
  ),
  // F3: blended "until smooth paste forms" / "process until smooth"
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    0,
    '25 garlic cloves, unpeeled',
    null,
  ),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    3,
    '1 tablespoon peppercorns',
    null,
  ),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    6,
    '2 tablespoons Mexican oregano',
    null,
  ),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    12,
    '1 onion, sliced into ¾-inch-thick rounds',
    null,
  ),
  // D1: the bay leaves
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    14,
    '8 bay leaves',
    DiscardedMedium.strainedSolid,
  ),
  // widened "strain broth"; the beef blanched and drained (F4)
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    0,
    '1 pound 85 percent lean ground beef',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    4,
    '1 (4-inch) piece ginger, sliced into thin rounds',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    5,
    '1 cinnamon stick',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    7,
    '6 star anise pods',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    10,
    '1 teaspoon black peppercorns',
    DiscardedMedium.strainedSolid,
  ),
  // the onions and scallions named after the strain
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    1,
    '2 onions, quartered through root end',
    null,
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    14,
    '3 scallions, sliced thin (optional)',
    null,
  ),
  // widened: "Strain the stock" (R01)
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    'Turkey Gravy',
    1,
    '2 small onions, chopped coarse',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    'Turkey Gravy',
    2,
    '1 medium carrot, cut into 1-inch pieces',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    'Turkey Gravy',
    3,
    '1 celery rib, cut into 1-inch pieces',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    'Turkey Gravy',
    4,
    '6 garlic cloves, unpeeled',
    DiscardedMedium.strainedSolid,
  ),
  // the celery bundle (audit L217): CLOSER 1 RE-PIN (V1-D1) — lifted out
  // with "the vegetables" before the strain ("Using slotted spoon, transfer
  // vegetables to serving platter, discarding celery bundle"), so D2's
  // bundle reads it (0 g either way; was strainedSolid)
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    null,
    10,
    '2 celery ribs, halved crosswise',
    DiscardedMedium.removedAromatic,
  ),
  // closer 1 (V1-D1): the carrots lifted out with the vegetables are
  // served; the peppercorns and garlic sprinkled "over vegetables" are set
  // apart from them and strained
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    null,
    19,
    '2 carrots, peeled and cut into ½-inch lengths',
    null,
  ),
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    null,
    21,
    '8 whole peppercorns',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    null,
    22,
    '2 garlic cloves, peeled',
    DiscardedMedium.strainedSolid,
  ),
  // closer 1 (V1-D3): a part kept out of the strained pan (the salmon's
  // "remaining 2 tablespoons shallot" in the bowl) — the medium here, its
  // share in _rows; a strain whose next sentence keeps solids ("Measure 1
  // tablespoon of solids", grilled potatoes) zeroes nothing
  (
    '0260-poached-salmon-with-herb-and-caper-vinaigrette.yaml',
    null,
    1,
    '1 large shallot, minced (about 4 tablespoons)',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0659-grilled-potatoes-with-garlic-and-rosemary.yaml',
    null,
    1,
    '9 garlic cloves, minced',
    null,
  ),
  (
    '0659-grilled-potatoes-with-garlic-and-rosemary.yaml',
    null,
    2,
    '1 teaspoon chopped fresh rosemary',
    null,
  ),
  // closer 1 (V1-D4): the "garlic-lemon mixture" the strain strains is the
  // liquid when named again — the kept tablespoon is strained out too
  (
    '0572-ultracreamy-hummus.yaml',
    null,
    2,
    '4 garlic cloves, peeled',
    DiscardedMedium.strainedSolid,
  ),
  // closer 1 (V1-D3): the cilantro bundle is only the remaining 10 sprigs
  (
    '0679-drunken-beans.yaml',
    null,
    2,
    '30 sprigs fresh cilantro (1 bunch)',
    DiscardedMedium.removedAromatic,
  ),
  // a baking sheet IS the strained pan ("pour pan juices through")
  (
    '0230-roast-butterflied-leg-of-lamb-with-coriander-cumin-and-mustard-seeds.yaml',
    null,
    4,
    '4 garlic cloves, peeled and smashed',
    DiscardedMedium.strainedSolid,
  ),
  (
    '0230-roast-butterflied-leg-of-lamb-with-coriander-cumin-and-mustard-seeds.yaml',
    null,
    10,
    '2 (2-inch) strips lemon zest',
    DiscardedMedium.strainedSolid,
  ),
  // the sheet beside the skillet whose sauce is strained
  (
    '0143-best-roast-chicken-with-root-vegetables.yaml',
    null,
    4,
    '12 ounces carrots, peeled, halved crosswise, thick ends halved lengthwise',
    null,
  ),
  // "Meanwhile, strain the hot broth": a second pot
  (
    '0412-butternut-squash-risotto.yaml',
    null,
    7,
    '2 small onions, minced (about 1½ cups)',
    null,
  ),
  (
    '0412-butternut-squash-risotto.yaml',
    null,
    8,
    '2 medium garlic cloves, minced or pressed through a garlic press (about 2 teaspoons)',
    null,
  ),
  // a purée strain
  (
    '0015-creamy-pea-soup.yaml',
    null,
    1,
    '4 large shallots, minced (about 1 cup), or 2 medium leeks, white and light green parts chopped fine and rinsed thoroughly (about 1⅓ cups)',
    null,
  ),
  // the yolks: no strained class
  ('0927-classic-creme-brulee.yaml', null, 4, '12 large egg yolks', null),
  // Q17: skimmed
  (
    '0459-modern-beef-burgundy.yaml',
    null,
    2,
    '6 ounces salt pork, cut into ¼-inch pieces',
    DiscardedMedium.strainedSolid,
  ),
  // Q17: skimmed
  (
    '0127-coq-au-riesling.yaml',
    null,
    2,
    '2 slices bacon, chopped',
    DiscardedMedium.strainedSolid,
  ),
  // Q17: discarded, step 6 skims
  (
    '0005-best-beef-stew.yaml',
    null,
    10,
    '4 ounces salt pork, rinsed of excess salt',
    DiscardedMedium.removedAromatic,
  ),
  // Q17: discarded, skimmed
  (
    '0456-daube-provencal.yaml',
    null,
    5,
    '5 ounces salt pork, rind removed',
    DiscardedMedium.removedAromatic,
  ),
  // Q17: drippings to a fat separator
  (
    '0156-old-fashioned-stuffed-turkey.yaml',
    null,
    3,
    '12 ounces salt pork, cut into ¼-inch-thick slices and rinsed',
    DiscardedMedium.removedAromatic,
  ),
  // Q17: never skimmed
  (
    '1120-new-england-fish-chowder.yaml',
    null,
    2,
    '4 ounces salt pork, rind removed, rinsed, and cut into 2 pieces',
    DiscardedMedium.fatKept,
  ),
  // Q17: "discard salt pork, leaving fat in pot"
  (
    '0237-milk-braised-pork-loin.yaml',
    null,
    3,
    '2 ounces salt pork, chopped coarse',
    DiscardedMedium.fatKept,
  ),
  // Q17: never skimmed
  (
    '0023-modern-ham-and-split-pea-soup.yaml',
    null,
    6,
    '3 slices thick-cut bacon',
    DiscardedMedium.fatKept,
  ),
  // D2
  (
    '0103-cuban-style-black-beans-and-rice.yaml',
    null,
    4,
    '2 large green bell peppers, stemmed, seeded, and halved',
    DiscardedMedium.removedAromatic,
  ),
  (
    '0103-cuban-style-black-beans-and-rice.yaml',
    null,
    5,
    '1 large onion, halved at equator and peeled, root end left intact',
    DiscardedMedium.removedAromatic,
  ),
  // D2 (the lemons partitioned, F12)
  (
    '0137-classic-roast-lemon-chicken.yaml',
    null,
    2,
    '2 lemons',
    DiscardedMedium.removedAromatic,
  ),
  (
    '0137-classic-roast-lemon-chicken.yaml',
    null,
    3,
    '6 medium garlic cloves, crushed and peeled',
    DiscardedMedium.removedAromatic,
  ),
  // D2: "remove herb bundle" (audit L232)
  (
    '0030-farmhouse-vegetable-and-barley-soup.yaml',
    null,
    3,
    '1 bay leaf',
    DiscardedMedium.removedAromatic,
  ),
  // D2: partly chopped and minced
  (
    '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    null,
    1,
    '2 medium onions, 1 quartered and 1 chopped fine',
    null,
  ),
  (
    '0491-spicy-mexican-shredded-pork-tostadas.yaml',
    null,
    2,
    '5 medium garlic cloves, 3 peeled and smashed and 2 minced or pressed through a garlic press (about 2 teaspoons)',
    null,
  ),
  // the shipped drained pot wins
  (
    '0063-lentil-salad-with-olives-mint-and-feta.yaml',
    null,
    4,
    '5 garlic cloves, lightly crushed and peeled',
    DiscardedMedium.saltBath,
  ),
  (
    '0063-lentil-salad-with-olives-mint-and-feta.yaml',
    null,
    5,
    '1 bay leaf',
    DiscardedMedium.saltBath,
  ),
  // Q20 (i)
  (
    '0755-blueberry-scones.yaml',
    null,
    0,
    '16 tablespoons (2 sticks) unsalted butter, frozen whole',
    DiscardedMedium.partialUse,
  ),
  // Q20 (ii) baked
  (
    '0365-potato-gnocchi-with-browned-butter-and-sage-sauce.yaml',
    null,
    0,
    '2 pounds russet potatoes',
    DiscardedMedium.partialUse,
  ),
  // Q20 (ii) boiled, the prep note's weight
  (
    '0790-potato-burger-buns.yaml',
    null,
    0,
    '1 pound russet potatoes, peeled and cut into 1-inch pieces',
    DiscardedMedium.partialUse,
  ),
  // Q20 (iii) reserved
  (
    '0178-baked-bread-stuffing-with-sausage-dried-cherries-and-pecans.yaml',
    null,
    1,
    '3 pounds turkey wings, divided at joints',
    DiscardedMedium.partialUse,
  ),
  // Q20 (iii) the rest discarded
  (
    '0640-grill-roasted-beer-can-chicken.yaml',
    null,
    0,
    '1 (12-ounce) can beer',
    DiscardedMedium.partialUse,
  ),
  // M49's D3, never a discard of the food: "Discard all but 3 tablespoons
  // of the rendered bacon fat" (rule B1 keeps both rows' parts).
  (
    '0724-scrambled-eggs-with-bacon-onion-and-pepper-jack-cheese.yaml',
    null,
    4,
    '4 ounces bacon (about 4 slices), halved lengthwise, then cut crosswise into ½-inch pieces',
    null,
  ),
  (
    '0158-classic-roast-stuffed-turkey.yaml',
    'Bread Stuffing with Bacon, Apples, Sage, and Caramelized Onions',
    0,
    '1 pound bacon, cut crosswise into ¼-inch strips',
    null,
  ),
  // Q20 (iv): counted whole, flagged
  (
    '0386-deep-dish-pizza-with-tomatoes-mozzarella-and-basil.yaml',
    null,
    0,
    '1 medium russet potato (about 9 ounces), peeled and quartered',
    null,
  ),
];

/// (file, section title or null, position, raw, fdc id, grams, hold,
/// gram_basis) — the row its WHOLE recipe computes.
const List<(String, String?, int, String, int?, String?, String?, String?)>
_rows = [
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    0,
    '1 small onion, peeled and cut into rough ½-inch pieces',
    790646,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    1,
    '1 small carrot, peeled and cut into rough ½-inch pieces',
    2258586,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    2,
    '8 ounces cremini mushrooms, trimmed and halved',
    168434,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    3,
    '2 medium garlic cloves, peeled',
    1104647,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    4,
    '1 tablespoon vegetable oil',
    2710180,
    '14.00',
    null,
    '1 tablespoon · USDA portion',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    5,
    '8 ounces 85 percent lean ground beef',
    171796,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    6,
    '1 tablespoon tomato paste',
    2685580,
    '16.27',
    null,
    '1 tablespoon ≈ 15 mL',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    7,
    '2 cups dry red wine',
    2710688,
    '468.44',
    null,
    '2 cup ≈ 473 mL',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    8,
    '4 cups beef broth',
    172889,
    '946.35',
    null,
    '4 cup ≈ 946 mL',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    9,
    '4 sprigs fresh thyme',
    173470,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    10,
    '2 bay leaves',
    170917,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    11,
    '2 teaspoons whole black peppercorns',
    170931,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml',
    'Sauce Base',
    12,
    '5 teaspoons unflavored gelatin',
    169599,
    '11.67',
    null,
    '5 teaspoon · USDA portion',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    0,
    '1 (3½-pound) boneless chuck-eye roast',
    168661,
    '1587.57',
    null,
    'from the printed weight',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    2,
    '4 ounces pancetta (about 4 slices), cut into ¼-inch cubes (see note)',
    168277,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted) · approximation (counted as Pork, cured, bacon, unprepared)',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    3,
    '2 medium onions, chopped medium',
    790646,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    4,
    '2 medium carrots, chopped medium',
    2258586,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    5,
    '2 medium celery ribs, chopped medium',
    2346405,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    7,
    '3 medium garlic cloves, minced or pressed through a garlic press (about 1 tablespoon)',
    1104647,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    10,
    '1 (750-milliliter) bottle Barolo wine',
    2710688,
    '750.00',
    null,
    '1 bottle · USDA portion',
  ),
  (
    '0426-beef-braised-in-barolo.yaml',
    null,
    11,
    '1 (14.5-ounce) can diced tomatoes, drained',
    333281,
    '221.98',
    null,
    'from the printed weight × 0.54 drained · approximate (ATK: 2 (28-ounce) cans whole tomatoes, drained, give 3 cups juice)',
  ),
  (
    '0211-french-style-pork-chops-with-apples-and-calvados.yaml',
    null,
    2,
    '4 Gala or Golden Delicious apples, peeled and cored',
    168202,
    '728.00',
    null,
    '4 × 182 g each',
  ),
  (
    '0211-french-style-pork-chops-with-apples-and-calvados.yaml',
    null,
    3,
    '2 slices bacon, cut into ½-inch pieces',
    168277,
    null,
    'discarded_medium',
    null,
  ),
  (
    '0211-french-style-pork-chops-with-apples-and-calvados.yaml',
    null,
    4,
    '3 shallots, sliced',
    170499,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0402-italian-wedding-soup.yaml',
    null,
    0,
    '1 onion, chopped',
    790646,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0402-italian-wedding-soup.yaml',
    null,
    4,
    '4 ounces ground pork',
    2514745,
    null,
    'discarded_medium',
    null,
  ),
  (
    '0402-italian-wedding-soup.yaml',
    null,
    5,
    '4 ounces 85 percent lean ground beef',
    171796,
    null,
    'discarded_medium',
    null,
  ),
  (
    '0402-italian-wedding-soup.yaml',
    null,
    18,
    '6 ounces ground pork',
    2514745,
    '170.10',
    null,
    'from 6 ounce',
  ),
  (
    '0402-italian-wedding-soup.yaml',
    null,
    20,
    '6 ounces 85 percent lean ground beef',
    171796,
    '170.10',
    null,
    'from 6 ounce',
  ),
  (
    '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
    null,
    9,
    '1½ teaspoons ground cardamom',
    170919,
    '3.03',
    null,
    '1 1/2 teaspoon ≈ 7 mL',
  ),
  (
    '0209-red-winebraised-pork-chops.yaml',
    null,
    8,
    '⅛ teaspoon ground allspice',
    171315,
    '0.24',
    null,
    '1/8 teaspoon ≈ 1 mL',
  ),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    0,
    '25 garlic cloves, unpeeled',
    1104647,
    '75.00',
    null,
    '25 × 3 g each',
  ),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    3,
    '1 tablespoon peppercorns',
    170931,
    '8.72',
    null,
    '1 tablespoon ≈ 15 mL',
  ),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    6,
    '2 tablespoons Mexican oregano',
    171328,
    '6.00',
    null,
    '2 tablespoon · USDA portion',
  ),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    12,
    '1 onion, sliced into ¾-inch-thick rounds',
    790646,
    '110.00',
    null,
    '1 × 110 g each',
  ),
  (
    '0493-sous-vide-cochinita-pibil.yaml',
    null,
    14,
    '8 bay leaves',
    170917,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0010-vietnamese-beef-pho.yaml',
    null,
    0,
    '1 pound 85 percent lean ground beef',
    171796,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0137-classic-roast-lemon-chicken.yaml',
    null,
    2,
    '2 lemons',
    2709168,
    '58.00',
    null,
    'removed and discarded (step 6): 1 of 2 — only the rest counted',
  ),
  (
    '0137-classic-roast-lemon-chicken.yaml',
    null,
    3,
    '6 medium garlic cloves, crushed and peeled',
    1104647,
    '0.00',
    null,
    'removed and discarded (step 6) — counted as 0 g',
  ),
  (
    '0237-milk-braised-pork-loin.yaml',
    null,
    3,
    '2 ounces salt pork, chopped coarse',
    168287,
    null,
    'discarded_medium',
    null,
  ),
  (
    '0005-best-beef-stew.yaml',
    null,
    10,
    '4 ounces salt pork, rinsed of excess salt',
    168287,
    '0.00',
    null,
    'removed and discarded (step 5) — counted as 0 g',
  ),
  (
    '0755-blueberry-scones.yaml',
    null,
    0,
    '16 tablespoons (2 sticks) unsalted butter, frozen whole',
    173430,
    '141.81',
    null,
    'the remaining 6 tablespoons saved for another use (step 1) — only the rest counted',
  ),
  (
    '0365-potato-gnocchi-with-browned-butter-and-sage-sauce.yaml',
    null,
    0,
    '2 pounds russet potatoes',
    2346401,
    '551.32',
    null,
    "from 16 ounces cooked (step 3) · approximate (the steps keep 16 ounces of the baked potato; its raw weight by FDC's carbohydrate, 170033)",
  ),
  (
    '0790-potato-burger-buns.yaml',
    null,
    0,
    '1 pound russet potatoes, peeled and cut into 1-inch pieces',
    2346401,
    '256.52',
    null,
    "from ½ pound cooked (step 2) · approximate (the steps keep ½ pound of the boiled potato; its raw weight by FDC's carbohydrate, 170114)",
  ),
  (
    '0178-baked-bread-stuffing-with-sausage-dried-cherries-and-pecans.yaml',
    null,
    1,
    '3 pounds turkey wings, divided at joints',
    171497,
    '0.00',
    null,
    'reserved for another use (step 7) — counted as 0 g',
  ),
  (
    '0640-grill-roasted-beer-can-chicken.yaml',
    null,
    0,
    '1 (12-ounce) can beer',
    2710616,
    '0.00',
    null,
    'the rest discarded (step 7) — counted as 0 g',
  ),
  (
    '0386-deep-dish-pizza-with-tomatoes-mozzarella-and-basil.yaml',
    null,
    0,
    '1 medium russet potato (about 9 ounces), peeled and quartered',
    2346401,
    '206.67',
    null,
    'from 9 ounce × 0.81 edible · approximate (USDA AH-102 item 2018: potatoes, raw whole, all samples → pared 81 % (61–94)) · approximate (the steps keep only 1⅓ cups of it)',
  ),
  (
    '1209-chocolate-dipped-triple-coconut-macaroons.yaml',
    null,
    7,
    '10 ounces semisweet chocolate, chopped, divided',
    170271,
    '283.50',
    null,
    'from 10 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0070-skillet-chicken-fajitas.yaml',
    null,
    0,
    '¼ cup vegetable oil',
    2710180,
    '56.00',
    null,
    '1/4 cup · USDA portion · approximate (lifted out of its marinade — how much clings is not written)',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    null,
    0,
    '¾ cup regular or light coconut milk',
    170173,
    '182.76',
    null,
    '3/4 cup ≈ 177 mL',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    null,
    1,
    '3 tablespoons packed dark brown sugar',
    168833,
    '41.26',
    null,
    '3 tablespoon ≈ 44 mL',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    null,
    2,
    '3 tablespoons fish sauce',
    2706457,
    '48.00',
    null,
    '3 tablespoon · USDA portion',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    null,
    3,
    '2 tablespoons vegetable oil',
    2710180,
    '28.00',
    null,
    '2 tablespoon · USDA portion',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    null,
    4,
    '3 shallots, minced',
    170499,
    '90.00',
    null,
    '3 × 30 g each',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    null,
    5,
    '2 lemon grass stalks, trimmed to bottom 6 inches and minced',
    168573,
    '20.00',
    null,
    '2 × 10 g each · approximate (reference figure: a stalk trimmed to its bottom 5–6 inches)',
  ),
  (
    '0621-grilled-beef-satay.yaml',
    null,
    6,
    '2 tablespoons grated fresh ginger',
    169231,
    '15.97',
    null,
    '2 tablespoon ≈ 30 mL',
  ),
  // closer 1 (V1-D1): the carrots served; the celery bundle discarded; the
  // garlic sprinkled over the vegetables strained
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    null,
    19,
    '2 carrots, peeled and cut into ½-inch lengths',
    2258586,
    '122.00',
    null,
    '2 × 61 g each',
  ),
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    null,
    10,
    '2 celery ribs, halved crosswise',
    2346405,
    '0.00',
    null,
    'removed and discarded (step 5) — counted as 0 g',
  ),
  (
    '0454-french-style-chicken-and-stuffing-in-a-pot.yaml',
    null,
    22,
    '2 garlic cloves, peeled',
    1104647,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  // closer 1 (V1-D2): "1 bell pepper half, 1 onion half" in the beans' pot,
  // "the remaining peppers and onion" in the sofrito — only the pieces
  // discarded (238 × 3/4, 150 × 1/2)
  (
    '0103-cuban-style-black-beans-and-rice.yaml',
    null,
    4,
    '2 large green bell peppers, stemmed, seeded, and halved',
    2258588,
    '178.50',
    null,
    'removed and discarded (step 2): 1 of 4 halves — only the rest counted',
  ),
  (
    '0103-cuban-style-black-beans-and-rice.yaml',
    null,
    5,
    '1 large onion, halved at equator and peeled, root end left intact',
    790646,
    '75.00',
    null,
    'removed and discarded (step 2): 1 of 2 halves — only the rest counted',
  ),
  // closer 1 (V1-D3): 2 of 4 tablespoons strained (40 g × 1/2); the leaves
  // of 20 of 30 sprigs eaten (30 g × 2/3)
  (
    '0260-poached-salmon-with-herb-and-caper-vinaigrette.yaml',
    null,
    1,
    '1 large shallot, minced (about 4 tablespoons)',
    170499,
    '20.00',
    null,
    'discarded in cooking: 2 of 4 tablespoons — only the rest counted · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  (
    '0679-drunken-beans.yaml',
    null,
    2,
    '30 sprigs fresh cilantro (1 bunch)',
    2709782,
    '20.00',
    null,
    'removed and discarded (step 4): 10 of 30 — only the rest counted',
  ),
  // closer 1 (V1-D4): 0 g, no "keep only" flag
  (
    '0572-ultracreamy-hummus.yaml',
    null,
    2,
    '4 garlic cloves, peeled',
    1104647,
    '0.00',
    null,
    'discarded in cooking — counted as 0 g · approximate (strained out and discarded — what it gives the liquid is not counted)',
  ),
  // closer 1 (V1-D5): the batter's flour mixture made in step 2 (audit L206)
  (
    '0255-fish-and-chips.yaml',
    null,
    8,
    '1 teaspoon baking powder',
    172804,
    '4.53',
    null,
    '1 teaspoon ≈ 5 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0255-fish-and-chips.yaml',
    null,
    3,
    '½ cup cornstarch',
    169698,
    '63.88',
    null,
    '1/2 cup ≈ 118 mL · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
  (
    '0255-fish-and-chips.yaml',
    null,
    10,
    '1½ cups (12 ounces) cold beer',
    2710616,
    '340.19',
    null,
    'from 12 ounce · approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)',
  ),
];

/// Closer 1 (V1-D4, V1-D5): (file, position, raw, the flag [m50FlagOf]
/// reads in the line's own recipe — null: none). No FDC: a flag reads the
/// steps alone.
const List<(String, int, String, String?)> _flags = [
  // (iv) named by the line's own word "porcini" (P1 D4e)
  (
    '0030-farmhouse-vegetable-and-barley-soup.yaml',
    0,
    '⅛ ounce dried porcini mushrooms, rinsed',
    'approximate (the steps keep only 2 teaspoons of it)',
  ),
  // D5: a coating sifted the step before ("Sift cocoa and sugar")
  (
    '0852-chocolate-truffles.yaml',
    6,
    '1 cup (3 ounces) Dutch-processed cocoa',
    _bowl,
  ),
  (
    '0852-chocolate-truffles.yaml',
    7,
    '¼ cup (1 ounce) confectioners’ sugar',
    _bowl,
  ),
  // D5: a glaze read from the step that reduces it ("Discard remaining glaze")
  (
    '0516-negimaki-japanese-grilled-steak-and-scallion-rolls.yaml',
    1,
    '⅓ cup soy sauce',
    _bowl,
  ),
  (
    '0516-negimaki-japanese-grilled-steak-and-scallion-rolls.yaml',
    4,
    '2 tablespoons sake',
    _bowl,
  ),
  (
    '0516-negimaki-japanese-grilled-steak-and-scallion-rolls.yaml',
    5,
    '16 scallions, trimmed and halved crosswise',
    null,
  ),
  // D5: the discarded dough's flour mixture (step 1) and its milk mixture
  (
    '0758-british-style-currant-scones.yaml',
    0,
    '3 cups (15 ounces) all-purpose flour',
    _bowl,
  ),
  ('0758-british-style-currant-scones.yaml', 7, '2 large eggs', _bowl),
  // D6: "Process all ingredients in blender" — the first ingredient group
  (
    '0619-grilled-beef-kebabs-with-lemon-and-rosemary-marinade.yaml',
    0,
    '1 onion, chopped',
    _marinade,
  ),
  (
    '0619-grilled-beef-kebabs-with-lemon-and-rosemary-marinade.yaml',
    9,
    '¾ teaspoon pepper',
    _marinade,
  ),
  (
    '0619-grilled-beef-kebabs-with-lemon-and-rosemary-marinade.yaml',
    10,
    '2 pounds sirloin steak tips, trimmed and cut into 2-inch chunks',
    null,
  ),
  // STATED CEILINGS (0 kcal): the spareribs' glaze is the braising liquid
  // whisked two steps before the step that reduces it; A13 gives the
  // batter's one "pepper" to the cayenne line, never the black pepper
  ('0538-chinese-style-barbecued-spareribs.yaml', 2, '1 cup honey', null),
  ('0255-fish-and-chips.yaml', 6, '⅛ teaspoon ground black pepper', null),
];

const String _bowl =
    'approximate (the steps leave an excess of it in the bowl — how much is eaten is not written)';
const String _marinade =
    'approximate (lifted out of its marinade — how much clings is not written)';

void main() {
  test('the matcher version carries the batch (update the literal with a '
      'bump)', () {
    expect(matcherVersion, 49);
  });

  group('matcher v50 (batch M50)', skip: skipIfNoCorpus, () {
    late Directory tempDir;
    late SaltDatabase db;
    late FixtureProvider provider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('salt-v50-');
      final config = ServerConfig(
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

    /// [file]'s recipe, or its section [section].
    Recipe of(Recipe host, String? section) => section == null
        ? host
        : sectionOf(host, sectionKeyOf(host.id, section))!;

    test('each line reads its medium from its own recipe: D1 strained '
        'solids (the vessel, purée, ground and line-history exclusions), Q17 '
        'and F4 by the skim test, D2 by name and by bundle, D4 partial use, '
        'the shipped readers first', () {
      for (final (file, section, position, raw, medium) in _media) {
        final recipe = of(loadCorpusRecipe(file), section);
        final line = nutritionLines(recipe)[position];
        final reason = '$file|$section|$position';
        expect(line.raw, raw, reason: reason);
        expect(
          discardedMediumOf(recipe, line, normalizeItem(lineItemOf(line))),
          medium,
          reason: reason,
        );
      }
    });

    test('closer 1: each flag reads its own recipe (V1-D4 the kept volume '
        'named by its own word; V1-D5 the dip mixture made earlier, a coating '
        'sifted, a glaze reduced, a marinade of "all ingredients")', () {
      for (final (file, position, raw, flag) in _flags) {
        final recipe = loadCorpusRecipe(file);
        final line = nutritionLines(recipe)[position];
        final reason = '$file|$position';
        expect(line.raw, raw, reason: reason);
        expect(m50FlagOf(recipe, line), flag, reason: reason);
      }
    });

    test('each line computed in its WHOLE recipe lands its grams, hold and '
        'basis (a section computed under its own key first, as the per-recipe '
        'job does)', () async {
      // The raw russet record's DETAIL cached, as snapshot 21 holds it: Q20
      // (ii) reads the line's own record's carbohydrate (17.77125 g); a
      // weight line no portion ever fetched reads its search hit's rounded
      // 17.8 g instead (the gnocchi 550.43 g — fix50 discloses it).
      db.fdcFoodCachePut(
        2346401,
        jsonEncode((await provider.food(2346401))!.toJson()),
      );
      final computed = <String>{};
      for (final (file, section, position, raw, fdcId, grams, hold, basis)
          in _rows) {
        final host = loadCorpusRecipe(file);
        if (computed.add(file)) {
          db.upsertRecipe(host, sourceSlug: _source, contentHash: host.id);
          final stored = db.recipeByIdOrSlug(host.id)!.recipe;
          // The sections the pins read (the host's others are not
          // recorded).
          for (final title in {
            for (final pin in _rows)
              if (pin.$1 == file && pin.$2 != null) pin.$2!,
          }) {
            final key = sectionKeyOf(stored.id, title);
            expect(
              await matchAndCompute(
                db,
                provider,
                nutritionRecipeOf(db, key)!.recipe,
              ),
              isNull,
            );
          }
          expect(await matchAndCompute(db, provider, stored), isNull);
        }
        final recipe = of(db.recipeByIdOrSlug(host.id)!.recipe, section);
        final line = nutritionLines(recipe)[position];
        final row = db
            .ingredientMatchesFor(recipe.id)
            .singleWhere((r) => r.position == position);
        final reason = '$file|$section|$position';
        expect(line.raw, raw, reason: reason);
        expect(row.fdcId, fdcId, reason: reason);
        expect(row.status, 'auto', reason: reason);
        expect(row.grams?.toStringAsFixed(2), grams, reason: reason);
        expect(row.hold, hold, reason: reason);
        expect(
          gramBasisFor(db, line, row, recipe: recipe),
          basis,
          reason: reason,
        );
      }
    });

    test('the Sauce Base parent re-reads its strained section: 1,021.25 → '
        '728.35 g (the audit L010 721.5 g; P1 printed 728.1 from probe grams '
        'rounded to 0.1 g)', () async {
      const file =
          '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';
      final host = loadCorpusRecipe(file);
      db.upsertRecipe(host, sourceSlug: _source, contentHash: host.id);
      final stored = db.recipeByIdOrSlug(host.id)!.recipe;
      final key = sectionKeyOf(stored.id, 'Sauce Base');
      expect(
        await matchAndCompute(db, provider, nutritionRecipeOf(db, key)!.recipe),
        isNull,
      );
      expect(await matchAndCompute(db, provider, stored), isNull);
      final parent = db
          .ingredientMatchesFor(stored.id)
          .singleWhere((r) => r.position == 3);
      expect(parent.raw, '¼ cup Sauce Base (½ recipe; recipe follows)');
      expect(parent.childRecipeId, key);
      expect(parent.grams?.toStringAsFixed(2), '728.35');
      expect(db.nutritionFor(key)!.totalGrams?.toStringAsFixed(2), '1456.70');
    });

    test('the reserved wings keep their own weighing: AH-102 item 2602 '
        '(the v43 figure, its counted vehicle gone with Q20 (iii))', () async {
      const file =
          '0178-baked-bread-stuffing-with-sausage-dried-cherries-and-pecans.yaml';
      final host = loadCorpusRecipe(file);
      db.upsertRecipe(host, sourceSlug: _source, contentHash: host.id);
      final recipe = db.recipeByIdOrSlug(host.id)!.recipe;
      expect(await matchAndCompute(db, provider, recipe), isNull);
      final line = nutritionLines(recipe)[1];
      expect(line.raw, '3 pounds turkey wings, divided at joints');
      final weighed = lineGrams(
        db,
        line,
        knownFood(db, 171497, line: line),
        recipe: recipe,
      )!;
      expect(weighed.grams.toStringAsFixed(2), '585.13');
      expect(
        weighed.basis,
        'from 3 pound × 0.43 edible · approximate (USDA AH-102 item 2602: turkey wing, raw, fryer-roaster class → meat 43 % (42–45))',
      );
    });
  });
}
