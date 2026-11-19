// The v119 pins (batch M106, prep52 P7: shell and produce refuse;
// matcherVersion 105). S5: shrimp "…, shells (removed and) reserved" is
// bought in the shell — `boughtInShell` gains the clause and `buysRefuse`
// reads `boughtInShell`, so the line counts AH-102 item 2333's 0.81 (the
// shipped `ah102Shells` row). S6: new `produceYields` rows, read by the
// shipped `produceYieldOf` (a weight in the line's head, the word in its
// tail): kale 323505 'stemmed' 0.64 (item 1305), edible-podded peas 170010
// 'trimmed|strings removed|snapped' 0.94 (1748), iceberg 2346388 'cored'
// 0.93 (1425), green peas 2709797 'shelled' 0.38 (1751); asparagus 2710823
// 'trimmed' 0.53 (100), snap beans 2346400 'trimmed' 0.88 (200),
// tomatoes 170457 / 1999634 / 2709719 'cored' 0.88 (2541), mushrooms
// 168434 / 1999629 / 1999627 'trimmed' 0.97 (1507), radish 2709803
// 'trimmed' 0.92 (2149), napa 2727583 'cored' 0.93 (446), mustard greens
// 169256 'stemmed|trimmed' 0.93 (1532). Shiitake, Swiss chard, spinach and
// the in-pod fava record stay gross. Corpus-backed groups skip without
// SALT_CORPUS_DIR; every corpus read sits inside a test body. Each pinned
// line is computed ALONE (its own line in its recipe's real steps) on the
// fixtures; every value below is the replay's (snapshot 33, the v119 tree).
//
// Hand derivations (the printed weight at grams.dart's 453.592 g a pound /
// 28.3495 g an ounce × the share × the record's kcal per 100 g, nutrient
// 208, else 958):
//   shrimp-cocktail|0 "1 pound jumbo shrimp …, shells reserved": 453.59 ×
//     0.81 = 367.41 g × 0.85 = 312.30 (was 453.59 g, 385.55).
//   braised-greens-with-bacon-and-onion|4 "2 pounds kale …, stemmed":
//     907.18 × 0.64 = 580.60 g × 0.35 = 203.21 (was 317.51).
//   fava-beans-with-artichokes-asparagus-and-peas|10 "1 pound fresh peas,
//     shelled": 453.592 × 0.38 = 172.365 g (stored 172.36) × 0.81 =
//     139.62 (was 453.59 g, 367.41).
//   broiled-asparagus|0 "2 pounds thin asparagus …, tough ends trimmed":
//     907.18 × 0.53 = 480.81 g × 0.235292 = 113.13 (was 213.45).
// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'nutrition_v25_decided_test.dart' as d;
import 'nutrition_v26_rule_a_test.dart' as a;
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

final _fx = FixtureProvider(pending: pendingSearches);

/// The moved rows the fixtures compute whole — 92 of the replay's 98 (the
/// other six below): "file|position", record, description, status, hold,
/// gram source, confidence, grams, kcal, basis — every column the rules
/// write, each the replay's.
const _moved = [
  '0740-asparagus-ham-and-gruyere-frittata.yaml|5\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t120.20\t28.28\tfrom 8 ounce × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '0461-beef-en-cocotte-with-mushroom-sauce.yaml|2\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t137.50\t30.25\tfrom 5 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '1129-beef-wellington.yaml|10\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t879.97\t193.59\tfrom 2 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0708-best-summer-tomato-gratin.yaml|3\t1999634\tTomato, roma\tauto\t\tweight\t0.920000\t1197.48\t226.98\tfrom 3 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0415-better-chicken-marsala.yaml|9\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t439.98\t96.80\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0681-blanched-green-beans.yaml|1\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t399.16\t133.99\tfrom 1 pound × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0685-braised-greens-with-bacon-and-onion.yaml|4\t323505\tKale, raw\tauto\t\tweight\t0.970000\t580.60\t203.21\tfrom 2 pound × 0.64 edible · approximate (USDA AH-102 item 1305: kale, raw, untrimmed → leaves without stems 64 % (no range printed))',
  '1123-briam.yaml|9\t1999634\tTomato, roma\tauto\t\tweight\t0.920000\t598.74\t113.49\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0665-broiled-asparagus.yaml|0\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t480.81\t113.13\tfrom 2 pound × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '0667-buttery-spring-vegetables.yaml|1\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t240.40\t56.57\tfrom 1 pound × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '0667-buttery-spring-vegetables.yaml|2\t170010\tPeas, edible-podded, raw\tauto\t\tweight\t1.000000\t213.19\t89.54\tfrom 8 ounce × 0.94 edible · approximate (USDA AH-102 item 1748: peas, edible-podded, raw, untrimmed → trimmed pea pods 94 % (92–95))',
  '1207-caldo-de-siete-mares.yaml|9\t175179\tCrustaceans, shrimp, raw\tauto\t\tweight\t0.953333\t367.41\t312.30\tfrom 1 pound × 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))',
  '0341-campanelle-with-asparagus-basil-and-balsamic-glaze.yaml|4\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t240.40\t56.57\tfrom 1 pound × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '0084-catalan-style-beef-stew-with-mushrooms.yaml|17\t1999627\tMushroom, oyster\tauto\t\tweight\t1.000000\t219.99\t73.30\tfrom 8 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0098-chicken-pot-pie-with-savory-crumble-topping.yaml|7\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t274.99\t60.50\tfrom 10 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '1179-chicken-pot-pie-with-spring-vegetables.yaml|14\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t240.40\t56.57\tfrom 1 pound × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '0061-chilled-soba-noodles-with-cucumber-snow-peas-and-radishes.yaml|9\t170010\tPeas, edible-podded, raw\tauto\t\tweight\t1.000000\t106.59\t44.77\tfrom 4 ounce × 0.94 edible · approximate (USDA AH-102 item 1748: peas, edible-podded, raw, untrimmed → trimmed pea pods 94 % (92–95))',
  '0031-classic-gazpacho.yaml|0\t170457\tTomatoes, red, ripe, raw, year round average\tauto\t\tweight\t0.530476\t598.74\t107.77\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0179-classic-green-bean-casserole.yaml|6\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t798.32\t267.98\tfrom 2 pound × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0127-coq-au-riesling.yaml|13\t1999629\tMushrooms, white button\tauto\t\tweight\t0.983333\t439.98\t109.44\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0032-creamy-gazpacho-andaluz.yaml|0\t170457\tTomatoes, red, ripe, raw, year round average\tauto\t\tweight\t0.847143\t1197.48\t215.55\tfrom 3 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0107-creole-style-shrimp-and-sausage-gumbo.yaml|0\t175179\tCrustaceans, shrimp, raw\tauto\t\tweight\t0.953333\t551.11\t468.45\tfrom 1 1/2 pound × 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))',
  '0386-deep-dish-pizza-with-tomatoes-mozzarella-and-basil.yaml|6\t2709719\tTomatoes, raw\tauto\t\tweight\t0.910000\t598.74\t119.75\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0329-farfalle-with-tomatoes-olives-and-feta.yaml|2\t170457\tTomatoes, red, ripe, raw, year round average\tauto\t\tweight\t0.847143\t598.74\t107.77\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0048-fattoush-pita-bread-salad-with-tomatoes-and-cucumber.yaml|5\t1999634\tTomato, roma\tauto\t\tweight\t0.920000\t399.16\t75.66\tfrom 1 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0680-fava-beans-with-artichokes-asparagus-and-peas.yaml|10\t2709797\tGreen peas, raw\tauto\t\tweight\t1.000000\t172.36\t139.62\tfrom 1 pound × 0.38 edible · approximate (USDA AH-102 item 1751: peas, green, immature, raw, in pods → shelled 38 % (20–80))',
  '0680-fava-beans-with-artichokes-asparagus-and-peas.yaml|9\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t240.40\t56.57\tfrom 1 pound × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '1192-gado-gado.yaml|13\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t199.58\t67.00\tfrom 8 ounce × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '1181-green-bean-casserole.yaml|5\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t798.32\t267.98\tfrom 2 pound × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '1181-green-bean-casserole.yaml|8\t1999629\tMushrooms, white button\tauto\t\tweight\t0.983333\t439.98\t109.44\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0054-green-bean-salad-with-cherry-tomatoes-and-feta.yaml|0\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t598.74\t200.99\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0682-green-beans-amandine.yaml|3\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t798.32\t267.98\tfrom 2 pound × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0649-grilled-fish-tacos.yaml|16\t2346388\tLettuce, iceberg, raw\tauto\t\tweight\t1.000000\t118.64\t17.15\tfrom 4 1/2 ounce × 0.93 edible · approximate (USDA AH-102 item 1425: lettuce, crisphead including iceberg, retail pack → trimmed and cored 93 % (88–96))',
  '0603-grilled-pork-tenderloin-with-grilled-tomatoginger-salsa.yaml|5\t2709719\tTomatoes, raw\tauto\t\tweight\t0.910000\t598.74\t119.75\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0396-grilled-tomato-and-cheese-pizza.yaml|7\t2709719\tTomatoes, raw\tauto\t\tweight\t0.910000\t598.74\t119.75\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0660-grilled-tomatoes.yaml|0\t170457\tTomatoes, red, ripe, raw, year round average\tauto\t\tweight\t0.847143\t798.32\t143.70\tfrom 2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml|8\t1999627\tMushroom, oyster\tauto\t\tweight\t1.000000\t219.99\t73.30\tfrom 8 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0006-hearty-beef-and-vegetable-stew.yaml|16\t323505\tKale, raw\tauto\t\tweight\t0.970000\t145.15\t50.80\tfrom 8 ounce × 0.64 edible · approximate (USDA AH-102 item 1305: kale, raw, untrimmed → leaves without stems 64 % (no range printed))',
  '1072-horiatiki-salata-hearty-greek-salad.yaml|0\t1999634\tTomato, roma\tauto\t\tweight\t0.920000\t698.53\t132.40\tfrom 1 3/4 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0402-italian-wedding-soup.yaml|23\t323505\tKale, raw\tauto\t\tweight\t0.970000\t217.72\t76.20\tfrom 12 ounce × 0.64 edible · approximate (USDA AH-102 item 1305: kale, raw, untrimmed → leaves without stems 64 % (no range printed))',
  '0309-juicy-grilled-turkey-burgers.yaml|3\t1999629\tMushrooms, white button\tauto\t\tweight\t0.983333\t164.99\t41.04\tfrom 6 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0044-kale-caesar-salad.yaml|0\t323505\tKale, raw\tauto\t\tweight\t0.545000\t217.72\t76.20\tfrom 12 ounce × 0.64 edible · approximate (USDA AH-102 item 1305: kale, raw, untrimmed → leaves without stems 64 % (no range printed))',
  '1175-kousa-mihshi-lebanese-stuffed-squash.yaml|11\t1999634\tTomato, roma\tauto\t\tweight\t0.920000\t798.32\t151.32\tfrom 2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0330-meatless-meat-sauce-with-chickpeas-and-mushrooms.yaml|0\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t274.99\t60.50\tfrom 10 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0500-mexican-rice.yaml|0\t170457\tTomatoes, red, ripe, raw, year round average\tauto\t\tweight\t0.847143\t299.37\t53.89\tfrom 12 ounce × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0459-modern-beef-burgundy.yaml|4\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t439.98\t96.80\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '1172-multicooker-hawaiian-oxtail-soup.yaml|10\t169256\tMustard greens, raw\tauto\t\tweight\t0.953333\t421.84\t113.90\tfrom 1 pound × 0.93 edible · approximate (USDA AH-102 item 1532: mustard greens, raw, untrimmed → leaves, trimmed 93 % (90–95))',
  '0017-mushroom-bisque.yaml|0\t1999629\tMushrooms, white button\tauto\t\tweight\t0.983333\t439.98\t109.44\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0017-mushroom-bisque.yaml|1\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t219.99\t48.40\tfrom 8 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '1074-paella-de-verduras-cauliflower-and-bean-paella.yaml|3\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t149.69\t50.25\tfrom 6 ounce × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0047-panzanella-italian-bread-salad.yaml|3\t1999634\tTomato, roma\tauto\t\tweight\t0.920000\t598.74\t113.49\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0345-pasta-alla-norcina.yaml|7\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t219.99\t48.40\tfrom 8 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0326-pasta-and-fresh-tomato-sauce-with-garlic-and-basil.yaml|2\t170457\tTomatoes, red, ripe, raw, year round average\tauto\t\tweight\t0.847143\t798.32\t143.70\tfrom 2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0327-pasta-caprese.yaml|5\t170457\tTomatoes, red, ripe, raw, year round average\tauto\t\tweight\t0.847143\t598.74\t107.77\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0325-pasta-with-fresh-tomatoes-and-herbs.yaml|0\t170457\tTomatoes, red, ripe, raw, year round average\tauto\t\tweight\t0.847143\t598.74\t107.77\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0336-pasta-with-pesto-potatoes-and-green-beans.yaml|4\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t299.37\t100.49\tfrom 12 ounce × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0506-pork-and-cabbage-dumplingswor-tip.yaml|7\t2727583\tCabbage, napa, leaf, destemmed, raw\tauto\t\tweight\t0.950000\t316.38\t50.62\tfrom 12 ounce × 0.93 edible · approximate (USDA AH-102 item 446: cabbage, Chinese, raw, retail pack → trimmed and cut for use 93 % (88–95)) · nutrients of "Cabbage, chinese (pe-tsai), raw"',
  '0540-pork-lo-mein.yaml|15\t2727583\tCabbage, napa, leaf, destemmed, raw\tauto\t\tweight\t0.950000\t421.84\t67.49\tfrom 1 pound × 0.93 edible · approximate (USDA AH-102 item 446: cabbage, Chinese, raw, retail pack → trimmed and cut for use 93 % (88–95)) · nutrients of "Cabbage, chinese (pe-tsai), raw"',
  '0194-pub-style-steak-and-ale-pie.yaml|6\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t439.98\t96.80\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0010-quick-beef-and-vegetable-soup.yaml|3\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t439.98\t96.80\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0448-quick-chicken-fricassee.yaml|4\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t439.98\t96.80\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0180-quick-green-bean-casserole.yaml|8\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t598.74\t200.99\tfrom 1 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0274-red-snapper-ceviche-with-radishes-and-orange.yaml|7\t2709803\tRadish\tauto\t\tweight\t0.990000\t208.65\t33.38\tfrom 8 ounce × 0.92 edible · approximate (USDA AH-102 item 2149: radishes, common, raw, without tops → trimmed 92 % (85–95))',
  '0216-roast-beef-tenderloin-with-caramelized-onion-and-mushroom-stuffing.yaml|0\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t219.99\t48.40\tfrom 8 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0683-roasted-green-beans.yaml|0\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t399.16\t133.99\tfrom 1 pound × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0688-roasted-mushrooms-with-parmesan-and-pine-nuts.yaml|1\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t659.98\t145.19\tfrom 1 1/2 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '1097-roasted-radishes-with-yogurt-tahini-sauce.yaml|12\t2709803\tRadish\tauto\t\tweight\t0.990000\t834.61\t133.54\tfrom 2 pound × 0.92 edible · approximate (USDA AH-102 item 2149: radishes, common, raw, without tops → trimmed 92 % (85–95))',
  '0724-scrambled-eggs-with-asparagus-smoked-salmon-and-chives.yaml|6\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t120.20\t28.28\tfrom 8 ounce × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '0094-shepherds-pie.yaml|11\t1999629\tMushrooms, white button\tauto\t\tweight\t0.983333\t110.00\t27.36\tfrom 4 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '1093-shizi-tou-lions-head-meatballs.yaml|11\t2727583\tCabbage, napa, leaf, destemmed, raw\tauto\t\tweight\t0.950000\t632.76\t101.24\tfrom 1 1/2 pound × 0.93 edible · approximate (USDA AH-102 item 446: cabbage, Chinese, raw, retail pack → trimmed and cut for use 93 % (88–95)) · nutrients of "Cabbage, chinese (pe-tsai), raw"',
  '0285-shrimp-cocktail.yaml|0\t175179\tCrustaceans, shrimp, raw\tauto\t\tweight\t0.953333\t367.41\t312.30\tfrom 1 pound × 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))',
  '0347-shrimp-fra-diavolo.yaml|0\t175179\tCrustaceans, shrimp, raw\tauto\t\tweight\t0.953333\t551.11\t468.45\tfrom 1 1/2 pound × 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))',
  '1089-shrimp-risotto.yaml|0\t175179\tCrustaceans, shrimp, raw\tauto\t\tweight\t0.953333\t367.41\t312.30\tfrom 1 pound × 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))',
  '0092-simple-pot-au-feu.yaml|15\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t240.40\t56.57\tfrom 1 pound × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '0682-skillet-charred-green-beans-with-crispy-bread-crumb-topping.yaml|5\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t399.16\t133.99\tfrom 1 pound × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0029-soupe-au-pistou-provencal-vegetable-soup.yaml|13\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.545000\t199.58\t67.00\tfrom 8 ounce × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0282-spanish-style-toasted-pasta-with-shrimp.yaml|3\t175179\tCrustaceans, shrimp, raw\tauto\t\tweight\t0.953333\t551.11\t468.45\tfrom 1 1/2 pound × 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))',
  '0490-spicy-pork-tacos-al-pastor.yaml|2\t2709719\tTomatoes, raw\tauto\t\tweight\t0.910000\t498.95\t99.79\tfrom 1 1/4 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0339-spring-vegetable-pasta.yaml|1\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t240.40\t56.57\tfrom 1 pound × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '0666-stir-fried-asparagus-with-shiitake-mushrooms.yaml|7\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.936667\t240.40\t56.57\tfrom 1 pound × 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))',
  '0546-stir-fried-portobellos-with-ginger-oyster-sauce.yaml|14\t170010\tPeas, edible-podded, raw\tauto\t\tweight\t1.000000\t79.95\t33.58\tfrom 3 ounce × 0.94 edible · approximate (USDA AH-102 item 1748: peas, edible-podded, raw, untrimmed → trimmed pea pods 94 % (92–95))',
  '0546-stir-fried-portobellos-with-ginger-oyster-sauce.yaml|15\t2727583\tCabbage, napa, leaf, destemmed, raw\tauto\t\tweight\t0.950000\t421.84\t67.49\tfrom 1 pound × 0.93 edible · approximate (USDA AH-102 item 446: cabbage, Chinese, raw, retail pack → trimmed and cut for use 93 % (88–95)) · nutrients of "Cabbage, chinese (pe-tsai), raw"',
  '0544-stir-fried-shrimp-with-snow-peas-and-red-bell-pepper-in-hot-and-sour-sauce.yaml|14\t170010\tPeas, edible-podded, raw\tauto\t\tweight\t1.000000\t213.19\t89.54\tfrom 1/2 pound × 0.94 edible · approximate (USDA AH-102 item 1748: peas, edible-podded, raw, untrimmed → trimmed pea pods 94 % (92–95))',
  '0021-super-greens-soup-with-lemon-tarragon-cream.yaml|15\t323505\tKale, raw\tauto\t\tweight\t0.970000\t163.29\t57.15\tfrom 9 ounce × 0.64 edible · approximate (USDA AH-102 item 1305: kale, raw, untrimmed → leaves without stems 64 % (no range printed))',
  '0021-super-greens-soup-with-lemon-tarragon-cream.yaml|8\t1999629\tMushrooms, white button\tauto\t\tweight\t0.983333\t82.50\t20.52\tfrom 3 ounce × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '0686-swiss-chard-and-kale-gratin.yaml|1\t323505\tKale, raw\tauto\t\tweight\t0.545000\t290.30\t101.60\tfrom 1 pound × 0.64 edible · approximate (USDA AH-102 item 1305: kale, raw, untrimmed → leaves without stems 64 % (no range printed))',
  '0533-teriyaki-stir-fried-beef-with-green-beans-and-shiitakes.yaml|13\t2346400\tBeans, snap, green, raw\tauto\t\tweight\t0.970000\t299.37\t100.49\tfrom 12 ounce × 0.88 edible · approximate (USDA AH-102 item 200: beans, snap, green and wax, raw, whole → trimmed, ready to cook 88 % (62–97))',
  '0399-tomato-and-mozzarella-tart.yaml|3\t2709719\tTomatoes, raw\tauto\t\tweight\t0.910000\t199.58\t39.92\tfrom 1/2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0428-ultimate-shrimp-scampi.yaml|2\t175179\tCrustaceans, shrimp, raw\tauto\t\tweight\t0.953333\t551.11\t468.45\tfrom 1 1/2 pound × 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))',
  '1186-ultimate-veggie-burgers.yaml|8\t1999629\tMushrooms, white button\tauto\t\tweight\t0.666667\t439.98\t109.44\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
  '1103-upside-down-tomato-tart.yaml|7\t2709719\tTomatoes, raw\tauto\t\tweight\t0.910000\t798.32\t159.66\tfrom 2 pound × 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))',
  '0018-wild-rice-and-mushroom-soup.yaml|9\t168434\tMushrooms, brown, italian, or crimini, raw\tauto\t\tweight\t1.000000\t439.98\t96.80\tfrom 1 pound × 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))',
];

const _shrimp =
    '× 0.81 edible · approximate (USDA AH-102 item 2333: shrimp, headless, in shell → shelled, deveined 81 % (77–82))';
const _tomato =
    '× 0.88 edible · approximate (USDA AH-102 item 2541: tomatoes, raw, whole → cored and trimmed 88 % (88–88))';
const _asparagus =
    '× 0.53 edible · approximate (USDA AH-102 item 100: asparagus, raw, whole shoots → tips and tender portions of shoots 53 % (31–88))';
const _mushroom =
    '× 0.97 edible · approximate (USDA AH-102 item 1507: mushrooms, raw, whole, good quality → trimmed 97 % (87–100))';
const _mustard =
    '× 0.93 edible · approximate (USDA AH-102 item 1532: mustard greens, raw, untrimmed → leaves, trimmed 93 % (90–95))';

/// The design's negatives, R2 (c)'s records and the look-alikes, unchanged
/// (file|position, raw start, record, gram source, grams, basis) — the
/// v118 rows, byte-identical in the replay.
const _unmoved = [
  // S5: shell-on shrimp eaten shell and all stays gross (`shellEaten`).
  (
    '0279-crispy-salt-and-pepper-shrimp.yaml|0',
    '1½ pounds shell-on shrimp',
    175179,
    'weight',
    '680.39',
    'from 1 1/2 pound · approximate (gross weight, no USDA refuse portion)',
  ),
  // S5: "peeled, deveined …" with no reserved shells stays gross.
  (
    '0284-brazilian-shrimp-and-fish-stew-moqueca.yaml|5',
    '1 pound large shrimp (26 to 30 per pound), peeled, deveined',
    175179,
    'weight',
    '453.59',
    'from 1 pound',
  ),
  // S5: already shell-on AND reserved — the shipped 0.81, unchanged.
  (
    '0429-garlicky-shrimp-tomato-and-white-bean-stew.yaml|2',
    '1 pound large shell-on shrimp',
    175179,
    'weight',
    '367.41',
    'from 1 pound $_shrimp',
  ),
  // S5 look-alikes: "picked over for shells", taco shells, shell sirloin.
  (
    '0289-best-crab-cakes.yaml|0',
    '1 pound lump crabmeat, picked over for shells',
    2684446,
    'weight',
    '453.59',
    'from 1 pound',
  ),
  (
    '0478-ground-beef-tacos.yaml|15',
    '8 Home-Fried Taco Shells',
    172800,
    'piece',
    '103.20',
    '8 · USDA per-item weight',
  ),
  (
    '0190-pan-seared-inexpensive-steaks.yaml|1',
    '2 1-pound whole boneless shell sirloin steaks',
    2727574,
    'weight',
    '907.18',
    '2 × 454 g (printed weight)',
  ),
  // S6 kale: "stems trimmed" is not 'stemmed' (the kale word list).
  (
    '0406-hearty-tuscan-bean-stew.yaml|11',
    '1 bunch kale or collard greens (about 1 pound), stems trimmed',
    323505,
    'weight',
    '453.59',
    'from 1 pound',
  ),
  // S6 peas: frozen peas (170016) and the in-pod fava record (168574, R2
  // (c): a record question) — the table is keyed by record.
  (
    '0015-creamy-pea-soup.yaml|4',
    '1½ pounds frozen peas',
    170016,
    'weight',
    '680.39',
    'from 1 1/2 pound',
  ),
  (
    '0680-fava-beans-with-artichokes-asparagus-and-peas.yaml|3',
    '1 pound fava beans, shelled (1 cup)',
    168574,
    'weight',
    '453.59',
    'from 1 pound',
  ),
  // S6: shelled pistachios weighed shelled ('shelled' before the comma).
  (
    '1203-pistachio-gelato.yaml|0',
    '2½ cups (11¼ ounces) shelled pistachios',
    2515379,
    'weight',
    '318.93',
    'from 11 1/4 ounce',
  ),
  // R2 (c): shiitake 'stemmed' — no fresh stems-removed row printed.
  (
    '0017-mushroom-bisque.yaml|2',
    '8 ounces shiitake mushrooms, stemmed',
    1999628,
    'weight',
    '226.80',
    'from 8 ounce',
  ),
  (
    '0666-stir-fried-asparagus-with-shiitake-mushrooms.yaml|8',
    '4 ounces shiitake mushrooms, stemmed',
    1999628,
    'weight',
    '113.40',
    'from 4 ounce',
  ),
  // R2 (c): Swiss chard 'stemmed' — the table counts the stalks edible.
  (
    '0021-super-greens-soup-with-lemon-tarragon-cream.yaml|14',
    '12 ounces Swiss chard, stemmed',
    169991,
    'weight',
    '340.19',
    'from 12 ounce',
  ),
  // R2 (c): spinach 'stemmed' — two packs, no retail-bunch stems row.
  (
    '0567-indian-curry.yaml|17',
    '1½ pounds spinach, stemmed',
    1999633,
    'weight',
    '680.39',
    'from 1 1/2 pound',
  ),
  // The head test: the weight sits after the first top-level comma.
  (
    '0048-classic-greek-salad.yaml|10',
    '2 medium, firm, ripe tomatoes (6 ounces each), cored',
    170457,
    'weight',
    '340.19',
    '2 × 170 g (printed weight)',
  ),
  // Tomatoes 'peeled' only: no row is ruled for peeled or seeded.
  (
    '0441-walkaway-ratatouille.yaml|8',
    '2 pounds plum tomatoes, peeled and chopped coarse',
    2709719,
    'weight',
    '907.18',
    'from 2 pound',
  ),
  // A volume / count head on a ruled record: no weight in the head.
  (
    '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml|11',
    '½ head napa cabbage, cored and sliced thin (8 cups)',
    2727583,
    'portion',
    '608.00',
    '8 cup · USDA portion of "Cabbage, chinese (pe-tsai), raw" · nutrients of "Cabbage, chinese (pe-tsai), raw"',
  ),
];

void main() {
  test('matcherVersion 105', () => expect(matcherVersion, 105));
  group(
    'v119 (M106: shell and produce refuse)',
    skip: skipIfNoCorpus,
    () {
      moved();
      unmoved();
      resolver();
      properties();
      ownerGate();
    },
  );
  synthesized();
}

/// [file]'s line [position] ALONE in its recipe (the real steps).
Recipe _one(String file, int position) {
  final corpus = loadCorpusRecipe(file);
  return corpus.copyWith(
    ingredients: [
      IngredientGroup(items: [nutritionLines(corpus)[position]]),
    ],
  );
}

/// [file]'s line [position] ALONE in its recipe (the real steps), stored
/// and computed on the fixtures — the recipe and the line's index (0).
Future<(SaltDatabase, Recipe)> _alone(String file, int position) async {
  final (db, _) = a.pathDb();
  final r = _one(file, position);
  await d.editAndCompute(db, _fx, r);
  return (db, r);
}

/// The row's kcal on its record's DETAIL, as snapshot 33 caches it (the
/// replay's figure): the fixture detail where one is recorded — the
/// asparagus and snap-bean details (Foundation 2710823, 2346400) copied
/// from snapshot 33 into the fixtures by this batch; a weight line fetches
/// no detail, and a search hit's energy is rounded (23.5 for 23.5292 kcal
/// per 100 g) — else the food the compute cached. The napa record reads
/// its nutrient sibling (`nutrientSiblings`), as the engine does.
final _recorded =
    (jsonDecode(File('test/fixtures/fdc/foods.json').readAsStringSync())
            as Map<String, dynamic>)
        .keys
        .toSet();

Future<String?> _kcal(SaltDatabase db, IngredientMatchRow row) async {
  final grams = row.grams;
  if (grams == null) return null;
  final id = nutrientSiblings[row.fdcId] ?? row.fdcId!;
  final detail = _recorded.contains('$id') ? await _fx.food(id) : null;
  final food = detail ?? knownFood(db, id)!;
  return (kcalPer100g(food) * grams / 100).toStringAsFixed(2);
}

/// [want]'s key computed ALONE: every column [_moved] holds.
Future<String> _columns(String want) async {
  final key = want.split('\t').first;
  final [file, position] = key.split('|');
  final (db, r) = await _alone(file, int.parse(position));
  final line = nutritionLines(r).single;
  final row = d.rowOf(db, r, 0);
  return [
    key,
    row.fdcId,
    row.description,
    row.status,
    row.hold ?? '',
    row.gramSource,
    row.confidence.toStringAsFixed(6),
    row.grams?.toStringAsFixed(2),
    await _kcal(db, row),
    gramBasisFor(db, line, row, recipe: r),
  ].join('\t');
}

/// R5: every stored column the rules write, the kcal and the basis; (A2)
/// the matches GET's grams and `gram_basis` for one S5 row
/// (shrimp-cocktail|0) and one S6 row (braised-greens|4).
void moved() {
  test(
    'the moved rows: 92 rows, every column',
    () async {
      expect([for (final want in _moved) await _columns(want)], _moved);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  // RO1 (the owner gate): a WRONG-FOOD row a ruled word must not reach —
  // "2 pounds assertive greens, such as kale, …, stemmed" on asparagus
  // 2710823 (its key 'assertive green'); asparagus reads 'trimmed' alone,
  // so the row keeps its v118 columns. The record is the defect (a rank-as
  // onto kale is queued with the record / spelling batch).
  test('quick-cooked-tough-greens|1: the wrong-food row stays gross', () async {
    const want =
        '0685-quick-cooked-tough-greens.yaml|1\t2710823\tAsparagus, green, raw\tauto\t\tweight\t0.511667\t907.18\t213.45\tfrom 2 pound';
    expect(await _columns(want), want);
  });
  test('A2: the GET reads the two moved rows', () async {
    for (final (key, grams, basis) in [
      ('0285-shrimp-cocktail.yaml|0', '367.41', 'from 1 pound $_shrimp'),
      (
        '0685-braised-greens-with-bacon-and-onion.yaml|4',
        '580.60',
        'from 2 pound × 0.64 edible · approximate (USDA AH-102 item 1305: kale, raw, untrimmed → leaves without stems 64 % (no range printed))',
      ),
    ]) {
      final [file, position] = key.split('|');
      final (db, r) = await _alone(file, int.parse(position));
      final body = await matchesBody(db, _fx, r);
      final m = ((body['items']! as List).single as Map)['match'] as Map;
      expect(
        ((m['grams'] as num?)?.toStringAsFixed(2), m['hold'], m['gram_basis']),
        (grams, null, basis),
        reason: key,
      );
    }
  });
}

/// The negatives keep their v118 rows.
void unmoved() {
  for (final (key, raw, fdcId, source, grams, basis) in _unmoved) {
    test('$key unchanged: $fdcId $grams `$source`', () async {
      final [file, position] = key.split('|');
      final (db, r) = await _alone(file, int.parse(position));
      final line = nutritionLines(r).single;
      expect(line.raw, startsWith(raw));
      final row = d.rowOf(db, r, 0);
      expect(
        (row.fdcId, row.gramSource, row.grams?.toStringAsFixed(2), row.hold),
        (fdcId, source, grams, null),
      );
      expect(gramBasisFor(db, line, row, recipe: r), basis);
    });
  }
}

/// The corpus line at [raw]'s start in [file], any section.
IngredientLine _lineOf(String file, String raw) {
  final r = loadCorpusRecipe(file);
  return [
    for (final g in r.ingredients) ...g.items,
    for (final s in r.subsections)
      for (final g in s.ingredients ?? const <IngredientGroup>[]) ...g.items,
  ].singleWhere((l) => l.raw.startsWith(raw));
}

/// A fixture search's hit as a food (the records no fixture detail holds).
Future<FdcFood> _hit(String query, int fdcId) async =>
    (await _fx.search(query)).firstWhere((c) => c.fdcId == fdcId).toFood();

/// The six moved rows the fixtures cannot compute whole (three lines whose
/// searches no fixture records; three section rows), weighed by the
/// resolver on the replay's record: the replay's grams and basis.
void resolver() {
  test('the six other moved rows: grams and basis on their records', () async {
    final (db, _) = a.pathDb();
    final tomato = (await _fx.food(170457))!;
    final asparagus = await _hit('asparagus', 2710823);
    for (final (file, raw, food, want) in [
      (
        '0499-huevos-rancheros.yaml',
        '1½ pounds ripe plum tomatoes (about 6 medium), cored and halved',
        tomato,
        '598.74 g from 1 1/2 pound $_tomato',
      ),
      (
        '0666-pan-roasted-asparagus.yaml',
        '2 pounds thick asparagus (about 2 bunches), tough ends trimmed',
        asparagus,
        '480.81 g from 2 pound $_asparagus',
      ),
      (
        '0563-saag-paneer-indian-style-spinach-with-fresh-cheese.yaml',
        '12 ounces mustard greens, stemmed and rinsed',
        (await _fx.food(169256))!,
        '316.38 g from 12 ounce $_mustard',
      ),
      // Section rows (oven-roasted-salmon "Fresh Tomato Relish";
      // fluffy-omelets "Asparagus and Smoked Salmon Filling" and "Mushroom
      // Filling", on 1999629).
      (
        '0263-oven-roasted-salmon.yaml',
        '¾ pound ripe tomatoes, cored, seeded',
        tomato,
        '299.37 g from 3/4 pound $_tomato',
      ),
      (
        '0735-fluffy-omelets.yaml',
        '5 ounces asparagus, trimmed',
        asparagus,
        '75.13 g from 5 ounce $_asparagus',
      ),
      (
        '0735-fluffy-omelets.yaml',
        '4 ounces white or cremini mushrooms, trimmed',
        (await _fx.food(1999629))!,
        '110.00 g from 4 ounce $_mushroom',
      ),
    ]) {
      final g = lineGrams(
        db,
        _lineOf(file, raw),
        food,
        recipe: loadCorpusRecipe(file),
      );
      expect(
        '${g?.grams.toStringAsFixed(2)} g ${g?.basis}',
        want,
        reason: '$file $raw',
      );
    }
  });
}

/// Every corpus recipe file, sorted.
List<String> _files() =>
    Directory(corpusRecipesDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yaml'))
        .map((f) => f.uri.pathSegments.last)
        .toList()
      ..sort();

String _sha(Iterable<String> lines) =>
    sha256.convert(utf8.encode(lines.join('\n'))).toString();

/// R6 / A5 — the selector of each changed site, over every corpus recipe's
/// own lines (the property's limit: the titled sections' lines are not
/// looped — the three section rows are pinned in [resolver]). `shell`: the
/// lines `boughtInShell` answers. Each other class is every corpus line
/// whose item names the food, weighed through `lineGrams` (the recipe's
/// real steps) on the class's RECORD whatever record the matcher gives the
/// line: '.yield' = the basis carries an AH-102 flag, '.gross' = it does
/// not. The tomato and mushroom classes are weighed on 170457 and 168434
/// (1999634 / 2709719 and 1999629 / 1999627 read the same rows: the moved
/// pins). On the v119 replay the '.yield' sets are exactly the flagged main
/// rows on the ruled records (quick-cooked-tough-greens|1, on 2710823 with
/// an item naming no asparagus, is not looped here: its negative is in
/// [moved]). R2 (c)'s records (shiitake, chard, spinach, fava) size none:
/// no '.yield' key.
void properties() {
  test('the selectors on every corpus line', () async {
    final (db, _) = a.pathDb();
    final foods = <int, FdcFood>{
      for (final id in [
        175179,
        170010,
        2346388,
        170457,
        168434,
        2709803,
        2727583,
        169256,
        1999628,
        169991,
      ])
        id: (await _fx.food(id))!,
      323505: await _hit('kale', 323505),
      2709797: await _hit('peas', 2709797),
      2710823: await _hit('asparagus', 2710823),
      2346400: await _hit('green beans', 2346400),
      1999633: await _hit('spinach', 1999633),
      168574: await _hit('green cardamom pods', 168574),
    };
    final out = <String, List<String>>{};
    for (final file in _files()) {
      final r = loadCorpusRecipe(file);
      for (final (k, line) in nutritionLines(r).indexed) {
        final tag = '$file|$k';
        if (boughtInShell(line.raw)) (out['shell'] ??= []).add(tag);
        final w = normalizeItem(
          lineItemOf(line),
        ).split(RegExp('[^a-z]+')).toSet();
        bool has(String x) => w.contains(x);
        final classes = [
          if (has('shrimp')) ('s5', 175179),
          if (has('kale')) ('kale', 323505),
          if (has('snow') || (has('snap') && has('peas'))) ('podded', 170010),
          if (has('iceberg')) ('iceberg', 2346388),
          if (has('peas') && !has('snow') && !has('snap')) ('peas', 2709797),
          if (has('asparagus')) ('asparagus', 2710823),
          if ((has('green') || has('wax')) && has('beans') || has('haricots'))
            ('snapbeans', 2346400),
          if (has('tomato') || has('tomatoes')) ('tomato', 170457),
          if ((has('mushroom') || has('mushrooms') || has('cremini')) &&
              !has('shiitake') &&
              !has('portobello') &&
              !has('portobellos'))
            ('mushroom', 168434),
          if (has('radish') || has('radishes')) ('radish', 2709803),
          if (has('napa')) ('napa', 2727583),
          if (has('mustard') && has('greens') || has('gai') && has('choy'))
            ('mustard', 169256),
          if (has('shiitake') || has('shiitakes')) ('shiitake', 1999628),
          if (has('chard')) ('chard', 169991),
          if (has('spinach')) ('spinach', 1999633),
          if (has('fava')) ('fava', 168574),
        ];
        for (final (name, id) in classes) {
          final g = lineGrams(db, line, foods[id], recipe: r);
          final b = g == null
              ? '-'
              : '${g.grams.toStringAsFixed(2)} g ${g.basis}';
          final kind = b.contains('USDA AH-102 item') ? 'yield' : 'gross';
          (out['$name.$kind'] ??= []).add('$tag $b');
        }
      }
    }
    final got = {
      for (final MapEntry(:key, :value) in out.entries)
        key: (value.length, _sha(value)),
    };
    // Measured on the v119 tree (each '.yield' list read against the
    // replay's rows, above).
    expect(got, {
      'asparagus.yield': (
        11,
        '1f44fe0d17666013201d6d1eb460d2622bcad1af0c466d4174ea8d4e807df237',
      ),
      'chard.gross': (
        7,
        '3bf4671d28835b2e807c8d79cc4a87f5f5616836fdec48d381defd8d16456cbf',
      ),
      'fava.gross': (
        1,
        'dd59ba6d3363be632a1eadec45a89b423b656b5202b5485fe659f9665e113d7a',
      ),
      'iceberg.gross': (
        4,
        'aae439346fa534bab20df871fdc366ebed4bddfb61086d6bdec67bdba92436b4',
      ),
      'iceberg.yield': (
        1,
        '1e2a228e34c46ece6d3847b583c86e70b9825e364481934a33b075b7e3381e21',
      ),
      'kale.gross': (
        1,
        '525aa4fc8d3e427b282737f4ce8a5aee458f22fff518387ed326f8d5906f8472',
      ),
      'kale.yield': (
        6,
        '736524115bfc4742ba6cacf2d1de6b8b7e83148969c1711e1bc671ac335d5db9',
      ),
      'mushroom.gross': (
        35,
        '5946398b7a8f5cdf249f0436a4e316c87a37f6027e0535bead3d868e66272ef3',
      ),
      'mushroom.yield': (
        23,
        '8f1e2b397f2da2d7a19ff13caa8b877551cc037a323ea34d29ce9aa7dce5f8af',
      ),
      'mustard.yield': (
        2,
        '239129773eeb1d4d7a572799f86ba651483655d6f782c9a05beadb2cf67021be',
      ),
      'napa.gross': (
        3,
        '88353f43ec2e6ccabecdfa722aac508081b9a65206a2e7b67bcd381c77fbb52d',
      ),
      'napa.yield': (
        4,
        '93fd05a194907d53f1433e7c4656452e23c2a89635ecf549e58c303a9360e384',
      ),
      'peas.gross': (
        21,
        '20aca641affbbb62caf4e09ea23278b4e389878191aa17c8d813700d8eca59aa',
      ),
      'peas.yield': (
        1,
        'e51d865d575fa697295af7941d9c99a25089a230a047d909e8cd42f5fe047d04',
      ),
      'podded.yield': (
        4,
        '2823595aa705b46283618afcb6c2a5e8a60da7e5828c8d07bfe23aecad73e5c7',
      ),
      'radish.gross': (
        9,
        '5aea3a3b800c6ea29d5df3f9ab013f0afd6cb3bad13c8ce3f1e5b6a2a0c2deb3',
      ),
      'radish.yield': (
        2,
        '041923ced509cceb43b87212fc3ea6e24c5f1d7696c80e16a7854e03e6585fdf',
      ),
      's5.gross': (
        36,
        'f7249c1c247108e121266e6e562cede80e967082309a325c690a5be7669c17f5',
      ),
      's5.yield': (
        9,
        '33aa8975a9d3702d7d4f944c00c7736f0e983965a3094bf00947a0f46d954e52',
      ),
      'shell': (
        25,
        '90c88601ec7f54be9e247f74a4c1058afc83735274f1e5aa1da5e6badf83aa41',
      ),
      'shiitake.gross': (
        21,
        '8aa4f98be4dc3539235bd760714b1db92d190cd5c16f93dfdc795126f637e30c',
      ),
      'snapbeans.yield': (
        13,
        '143b45df7701531afa61acaf254bff8f4176f2b35e9f4bf332bb45dc9314da22',
      ),
      'spinach.gross': (
        22,
        '038b933484959e71258dad5a3e2faf150b3e6049956ec5c63f5d793fb6842199',
      ),
      'tomato.gross': (
        231,
        '08ba51145692a666b3ce88f4d90611158d42a0ca90d7623e2ca68fca746cf367',
      ),
      'tomato.yield': (
        21,
        'c2d97f0aa755034b155bfeef6c318527a510a4f7eeb4713c96a81f78c7e64e7a',
      ),
    });
  });
}

/// The owner gate's RO4 person path: the key 'jumbo shrimp' holds two
/// reserved-shell rows (shrimp-cocktail|0, ultimate-shrimp-scampi|2) and
/// two plain ones (paella-on-the-grill|2,
/// grilled-shrimp-and-vegetable-kebabs|2), all on 175179; each line alone in
/// its recipe. A pick +
/// apply_to_all on paella-on-the-grill|2: of 2684443 (no shell row), the
/// reached reserved-shell rows are held `in_shell` (the LINE hold reads
/// `boughtInShell`); of 2706350, they move to 174216. The next compute
/// writes each row as the apply did, and the matches GET then offers no
/// row of the key (the reach reads `boughtInShell` too).
void ownerGate() {
  for (final (pick, want) in [
    (
      2684443,
      [
        '2684443 overridden null 340.19 weight 1.000000',
        '2684443 auto in_shell 453.59 weight 1.000000',
        '2684443 auto in_shell 680.39 weight 1.000000',
        '2684443 auto null 680.39 weight 1.000000',
      ],
    ),
    // The cooked record of `_shellRecords`' mussel pair (FNDDS 2706350
    // "Mussels", to SR 174216 "Mollusks, mussel, blue, raw"): the
    // reached reserved-shell rows move to its raw record 174216 at its
    // shell share (the shell move reads `boughtInShell`); the plain row
    // stays on the pick, gross.
    (
      2706350,
      [
        '2706350 overridden null 340.19 weight 1.000000',
        '174216 auto null 131.54 weight 1.000000',
        '174216 auto null 197.31 weight 1.000000',
        '2706350 auto null 680.39 weight 1.000000',
      ],
    ),
  ]) {
    test('RO4: a pick of $pick + apply_to_all on the jumbo shrimp key', () async {
      final (db, _) = a.pathDb();
      final rs = [
        for (final (file, position) in [
          ('0106-paella-on-the-grill.yaml', 2),
          ('0285-shrimp-cocktail.yaml', 0),
          ('0428-ultimate-shrimp-scampi.yaml', 2),
          ('0654-grilled-shrimp-and-vegetable-kebabs.yaml', 2),
        ])
          _one(file, position),
      ];
      for (final r in rs) {
        await d.editAndCompute(db, _fx, r);
      }
      String row(Recipe r) {
        final m = d.rowOf(db, r, 0);
        return '${m.fdcId} ${m.status} ${m.hold} ${m.grams?.toStringAsFixed(2)} '
            '${m.gramSource} ${m.confidence.toStringAsFixed(6)}';
      }

      Future<(Object?, Object?)> others(Recipe r) async {
        final item =
            ((await matchesBody(db, _fx, r))['items']! as List).single as Map;
        return (item['others'], item['others_lines']);
      }

      final applied = await applyMatchOverride(db, _fx, rs.first, 0, {
        'raw': nutritionLines(rs.first).single.raw,
        'fdc_id': pick,
        'apply_to_all': true,
      });
      expect(applied?.lines, 3);
      expect([for (final r in rs) row(r)], want);
      expect(
        [for (final r in rs) await others(r)],
        List.filled(4, (0, 0)),
      );
      for (final r in rs.skip(1)) {
        await matchAndCompute(db, _fx, r);
      }
      expect([for (final r in rs) row(r)], want);
    });
  }
  // RO6 (the owner gate, 2026-11-19): a person's OWN pick on a
  // reserved-shell line (0285|0) reads as the shipped shell-on line's
  // (0429|2, the control: the same at v118) does — kept as picked, no
  // hold: a record with no shell row at its gross weight, flagged
  // approximate; 175179 at its 0.81. The stored row, the matches GET and
  // the next compute agree.
  for (final (kind, file, position) in [
    ('a reserved-shell', '0285-shrimp-cocktail.yaml', 0),
    (
      'the shipped shell-on',
      '0429-garlicky-shrimp-tomato-and-white-bean-stew.yaml',
      2,
    ),
  ]) {
    test("RO6: a person's own pick on $kind line", () async {
      const gross =
          'from 1 pound · approximate (gross weight, no USDA refuse portion)';
      for (final (pick, grams, basis) in [
        (2684443, '453.59', gross),
        (2706350, '453.59', gross),
        (175179, '367.41', 'from 1 pound $_shrimp'),
      ]) {
        final (db, r) = await _alone(file, position);
        final line = nutritionLines(r).single;
        await applyMatchOverride(db, _fx, r, 0, {
          'raw': line.raw,
          'fdc_id': pick,
        });
        Future<List<Object?>> read() async {
          final m = d.rowOf(db, r, 0);
          final body = await matchesBody(db, _fx, r);
          final g = ((body['items']! as List).single as Map)['match'] as Map;
          final stored =
              '${m.fdcId} ${m.status} ${m.hold} ${m.grams?.toStringAsFixed(2)} '
              '${m.gramSource} ${m.confidence.toStringAsFixed(6)}';
          return [
            stored,
            gramBasisFor(db, line, m, recipe: r),
            (g['grams'] as num?)?.toStringAsFixed(2),
            g['hold'],
            g['gram_basis'],
          ];
        }

        final want = [
          '$pick overridden null $grams weight 1.000000',
          basis,
          grams,
          null,
          basis,
        ];
        expect(await read(), want, reason: '$file $pick');
        await matchAndCompute(db, _fx, r);
        expect(await read(), want, reason: '$file $pick, the next compute');
      }
    });
  }
}

/// STATED synthesized (negative path and gates no corpus line reaches
/// alone), each naming its corpus source.
void synthesized() {
  // S5's clause: the singular "shell reserved" (no corpus line; source
  // 0285|0 "…, and shells reserved" singularised) is bought in the shell;
  // "shells removed" without "reserved" (source 0107|0 "shells removed and
  // reserved" with "and reserved" dropped) is not; nor is the shipped
  // "peeled and deveined" (0284|5).
  test('S5: the reserved-shell clause, singular and without "reserved"', () {
    for (final (raw, want) in [
      ('1 pound jumbo shrimp, peeled, deveined, and shell reserved', true),
      ('1½ pounds small shrimp (51 to 60 per pound), shells removed', false),
      ('1 pound large shrimp, peeled, deveined, and tails removed', false),
      // The clause is read whatever the shellfish (owner gate g1: every
      // corpus reserved-shell line names shrimp; no corpus line — source
      // 0285|0 with "shrimp" read "prawns").
      (
        '1 pound jumbo prawns (16 to 20 per pound; see note), peeled, '
            'deveined (see this page), and shells reserved',
        true,
      ),
    ]) {
      expect((boughtInShell(raw), buysRefuse(raw)), (want, want), reason: raw);
    }
  });

  // The arm's PLACEMENT (closer 1, verifier D1): `buysRefuse` reads
  // `boughtInShell` only AFTER its boneless / broth / stock / ground /
  // lobster-meat exclusions, as its shipped shell-on arm always did, so a
  // reserved-shell line naming "stock" is bought in the shell yet buys no
  // refuse (no corpus line: source 0285|0 "1 pound jumbo shrimp (16 to 20
  // per pound; see note), peeled, deveined (see this page), and shells
  // reserved" with " for stock" appended).
  test('S5: the exclusions precede the shell arm', () {
    const raw =
        '1 pound jumbo shrimp (16 to 20 per pound; see note), peeled, '
        'deveined (see this page), and shells reserved for stock';
    expect((boughtInShell(raw), buysRefuse(raw)), (true, false));
  });

  // 170010's 'trimmed' and 'snapped' alone (each corpus line on 170010
  // names "strings removed" too: 0667|2 "8 ounces sugar snap peas, strings
  // removed, trimmed", 0544|14 "½ pound snow peas or sugar snap peas, tips
  // snapped off and strings removed" — sources, each with its other word
  // dropped); a count head (source 0044|0 "12 ounces curly kale, stemmed …"
  // counted by the bunch) reads no yield.
  test(
    'S6: 170010 "trimmed" and "snapped" alone; a counted kale line',
    () async {
      final podded = (await _fx.food(170010))!;
      final kale = await _hit('kale', 323505);
      expect(
        [
          for (final raw in [
            '8 ounces sugar snap peas, trimmed',
            '½ pound snow peas or sugar snap peas, tips snapped off',
          ])
            produceYieldOf(podded, raw)?.share,
        ],
        [0.94, 0.94],
      );
      expect(produceYieldOf(kale, '1 bunch curly kale, stemmed'), isNull);
      expect(
        produceYieldOf(kale, '12 ounces curly kale, stemmed')?.share,
        0.64,
      );
    },
  );
}
