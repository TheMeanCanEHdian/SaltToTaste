// Corpus text is kept verbatim, one literal per entry.
// ignore_for_file: lines_longer_than_80_chars

/// The corpus text the corpus-free nutrition pins transcribe as string
/// literals (nutrition_v14a, v14b, v15 and v16: ingredient lines and step
/// texts), each with the corpus file it comes from. nutrition_v15_test's P7 guard
/// proves each still exists there, so a pin never passes on text the
/// corpus no longer has (Run 047 critic). Collected from the four files'
/// literals that match a corpus `raw` or `text` exactly; a literal that
/// matches none is a stated synthesized input or a fragment.
const List<(String, String)> pinnedCorpusText = [
  ('0000-italian-style-turkey-meatballs.yaml', 'Salt and pepper'),
  ('0000-italian-style-turkey-meatballs.yaml', '½ teaspoon dried oregano'),
  (
    '0002-classic-chicken-noodle-soup.yaml',
    'Table salt and ground black pepper',
  ),
  (
    '0002-hearty-chicken-noodle-soup.yaml',
    '4–6 Swiss chard leaves, ribs removed, torn into 1-inch pieces (about 2 cups; optional)',
  ),
  (
    '0003-old-fashioned-slow-cooker-chicken-noodle-soup.yaml',
    '3 medium garlic cloves, minced or pressed through a garlic press (about 1 tablespoon)',
  ),
  ('0004-pressure-cooker-chicken-noodle-soup.yaml', '8 cups water'),
  ('0008-our-favorite-chili.yaml', 'Table salt'),
  ('0009-best-ground-beef-chili.yaml', '2 teaspoons sugar'),
  (
    '0011-guay-tiew-tom-yum-goong-thai-hot-and-sour-noodle-soup-with-shrimp.yaml',
    '10 dried arbol chiles, stemmed, halved lengthwise, and seeds reserved',
  ),
  ('0015-carrot-ginger-soup.yaml', '1 teaspoon sugar'),
  ('0015-carrot-ginger-soup.yaml', '½ teaspoon baking soda'),
  ('0017-mushroom-bisque.yaml', 'Kosher salt and pepper'),
  (
    '0023-hearty-ham-and-split-pea-soup-with-potatoes.yaml',
    'Ground black pepper',
  ),
  ('0024-hearty-lentil-soup.yaml', '1 teaspoon table salt'),
  ('0026-red-lentil-soup-with-warm-spices.yaml', '½ teaspoon ground cumin'),
  ('0027-mulligatawny-soup.yaml', '¼ teaspoon cayenne pepper'),
  ('0028-hearty-minestrone.yaml', '(about ¾ cup)'),
  ('0032-creamy-gazpacho-andaluz.yaml', 'Kosher salt'),
  (
    '0043-pan-seared-scallops-with-wilted-spinach-watercress-and-orange-salad.yaml',
    '¼ cup vegetable oil',
  ),
  ('0044-mediterranean-chopped-salad.yaml', '3 tablespoons white wine vinegar'),
  ('0047-panzanella-italian-bread-salad.yaml', '½ cup extra-virgin olive oil'),
  (
    '0051-chopped-carrot-salad-with-fennel-orange-and-hazelnuts.yaml',
    '½ teaspoon pepper',
  ),
  ('0052-sesame-lemon-cucumber-salad.yaml', '1 tablespoon table salt'),
  (
    '0052-sesame-lemon-cucumber-salad.yaml',
    'Toss the cucumbers with the salt in a colander set over a large bowl. Weight the cucumbers with a gallon-sized zipper-lock bag filled with water; drain for 1 to 3 hours. Rinse and pat dry.',
  ),
  (
    '0052-sesame-lemon-cucumber-salad.yaml',
    'Whisk the remaining ingredients together in a medium bowl. Add the cucumbers; toss to coat. Serve chilled or at room temperature.',
  ),
  ('0053-crispy-thai-eggplant-salad.yaml', '2 tablespoons lime juice'),
  ('0056-austrian-style-potato-salad.yaml', '1 tablespoon sugar'),
  ('0070-skillet-chicken-fajitas.yaml', '1 teaspoon salt'),
  ('0070-skillet-chicken-fajitas.yaml', '1½ teaspoons smoked paprika'),
  ('0070-skillet-chicken-fajitas.yaml', '4 garlic cloves, peeled and smashed'),
  (
    '0070-skillet-chicken-fajitas.yaml',
    'Whisk 3 tablespoons oil, lime juice, garlic, paprika, sugar, salt, cumin, pepper, and cayenne together in bowl. Add chicken and toss to coat. Cover and let stand at room temperature for at least 30 minutes or up to 1 hour.',
  ),
  (
    '0077-skillet-chicken-and-rice-with-peas-and-scallions.yaml',
    '4 (6- to 8-ounce) boneless, skinless chicken breasts, trimmed',
  ),
  ('0091-home-corned-beef-with-vegetables.yaml', '2 tablespoons peppercorns'),
  ('0091-home-corned-beef-with-vegetables.yaml', '6 bay leaves'),
  ('0091-home-corned-beef-with-vegetables.yaml', '6 garlic cloves, peeled'),
  (
    '0091-home-corned-beef-with-vegetables.yaml',
    'Trim fat on surface of brisket to ⅛ inch. Dissolve salt, sugar, and curing salt in 4 quarts water in large container. Add brisket, 3 garlic cloves, 4 bay leaves, allspice berries, 1 tablespoon peppercorns, and coriander seeds to brine. Weigh brisket down with plate, cover, and refrigerate for 6 days.',
  ),
  ('0091-home-corned-beef-with-vegetables.yaml', '¾ cup salt'),
  ('0094-shepherds-pie.yaml', '½ cup milk'),
  ('0095-chicken-and-dumplings.yaml', '1 tablespoon baking powder'),
  (
    '0104-brown-rice-bowls-with-vegetables-and-salmon.yaml',
    '⅓ cup distilled white vinegar',
  ),
  (
    '0105-paella.yaml',
    '1 pound extra-large shrimp (21 to 25 per pound), peeled and deveined (see this page)',
  ),
  (
    '0109-palak-dal-spinach-dal-with-cumin-and-mustard-seeds.yaml',
    '4 whole dried arbol chiles',
  ),
  ('0112-perfect-poached-chicken-breasts.yaml', '2 tablespoons sugar'),
  (
    '0112-perfect-poached-chicken-breasts.yaml',
    '6 garlic cloves, smashed and peeled',
  ),
  (
    '0112-perfect-poached-chicken-breasts.yaml',
    'Cover chicken breasts with plastic wrap and pound thick ends gently with meat pounder until ¾ inch thick. Whisk 4 quarts water, soy sauce, salt, sugar, and garlic in Dutch oven until salt and sugar are dissolved. Arrange breasts, skinned side up, in steamer basket, making sure not to overlap them. Submerge steamer basket in brine and let sit at room temperature for 30 minutes.',
  ),
  ('0112-perfect-poached-chicken-breasts.yaml', '¼ cup salt'),
  ('0112-perfect-poached-chicken-breasts.yaml', '½ cup soy sauce'),
  ('0129-indoor-pulled-chicken.yaml', '1 cup cider vinegar'),
  ('0129-indoor-pulled-chicken.yaml', '¾ teaspoon salt'),
  ('0129-mahogany-chicken-thighs.yaml', '1 tablespoon distilled white vinegar'),
  (
    '0132-pan-roasted-chicken-breasts-with-sage-vermouth-sauce.yaml',
    '4 medium fresh sage leaves, each leaf torn in half',
  ),
  (
    '0141-pollo-en-mole-poblano-chicken-in-puebla-style-mole.yaml',
    '½ dried chipotle chile, stemmed, seeded, and torn into ½-inch pieces (scant tablespoon)',
  ),
  (
    '0150-oven-fried-chicken.yaml',
    '4 whole chicken legs, separated into drumsticks and thighs and skin removed',
  ),
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    '1 teaspoon baking soda',
  ),
  (
    '0165-crisp-skin-high-roast-butterflied-turkey-with-sausage-dressing.yaml',
    '4 large eggs',
  ),
  ('0176-grillroasted-boneless-turkey-breast.yaml', '2 teaspoons salt'),
  (
    '0190-pan-seared-inexpensive-steaks.yaml',
    '2 1-pound whole boneless shell sirloin steaks (top butt) or whole flap meat steaks, each about 1¼ inches thick',
  ),
  (
    '0199-pan-seared-thick-cut-boneless-pork-chops.yaml',
    '2 jarred hot cherry peppers, stems removed',
  ),
  (
    '0227-sous-vide-rosemarymustard-seed-crusted-roast-beef.yaml',
    '2 tablespoons flake sea salt',
  ),
  (
    '0246-indoor-pulled-pork-with-sweet-and-tangy-barbecue-sauce.yaml',
    '1 5-pound boneless pork butt roast, cut in half horizontally',
  ),
  (
    '0249-roast-fresh-ham.yaml',
    '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably shank end, rinsed',
  ),
  ('0285-shrimp-cocktail.yaml', '1 sprig fresh tarragon'),
  (
    '0286-shrimp-salad.yaml',
    '1 teaspoon whole black peppercorns plus ground black pepper',
  ),
  (
    '0286-shrimp-salad.yaml',
    '3 sprigs fresh tarragon plus 1 teaspoon minced fresh tarragon leaves',
  ),
  (
    '0286-shrimp-salad.yaml',
    '5 sprigs fresh parsley plus 1 teaspoon minced fresh parsley leaves',
  ),
  (
    '0286-shrimp-salad.yaml',
    'Combine the shrimp, ¼ cup of the lemon juice, the reserved lemon halves, parsley sprigs, tarragon sprigs, whole peppercorns, sugar, and 1 teaspoon salt with 2 cups cold water in a medium saucepan. Place the saucepan over medium heat and cook the shrimp, stirring several times, until pink, firm to the touch, and the centers are no longer translucent, 8 to 10 minutes (the water should be just bubbling around the edge of the pan and register 165 degrees on an instant-read thermometer). Remove the pan from the heat, cover, and let the shrimp sit in the broth for 2 minutes.',
  ),
  (
    '0286-shrimp-salad.yaml',
    'Meanwhile, fill a medium bowl with ice water. Drain the shrimp into a colander and discard the lemon halves, herbs, and spices. Immediately transfer the shrimp to the ice water to stop the cooking and chill thoroughly, about 3 minutes. Remove the shrimp from the ice water and pat dry with paper towels.',
  ),
  (
    '0286-shrimp-salad.yaml',
    'Whisk together the mayonnaise, celery, shallot, remaining 1 tablespoon lemon juice, the minced parsley, and minced tarragon in a medium bowl. Cut the shrimp in half lengthwise and then each half into thirds; add the shrimp to the mayonnaise mixture and toss to combine. Season with salt and pepper to taste and serve.',
  ),
  (
    '0286-shrimp-salad.yaml',
    '¼ cup plus 1 tablespoon juice from 2 to 3 lemons, spent halves reserved',
  ),
  (
    '0306-meatloaf-with-brown-sugarketchup-glaze.yaml',
    '⅔ cup crushed saltines (about 16) or quick oatmeal or 1⅓ cups fresh bread crumbs',
  ),
  (
    '0331-spaghetti-puttanesca.yaml',
    'Combine the garlic with 1 tablespoon water in a small bowl; set aside. Bring 4 quarts water to a boil in a large pot. Add 1 tablespoon salt and the pasta to the boiling water and cook, stirring often, until al dente. Reserve ½ cup of the cooking water then drain the pasta and return it to the pot. Add ¼ cup of the reserved tomato juice and toss to combine.',
  ),
  (
    '0353-simple-italian-style-meat-sauce.yaml',
    '1 tablespoon minced fresh oregano leaves or 1 teaspoon dried oregano',
  ),
  ('0301-stovetop-macaroni-and-cheese.yaml', '2 teaspoons table salt'),
  (
    '0301-stovetop-macaroni-and-cheese.yaml',
    'Mix the eggs, 1 cup of the evaporated milk, ½ teaspoon of the salt, the pepper, mustard mixture, and hot sauce in a small bowl; set aside.',
  ),
  (
    '0301-stovetop-macaroni-and-cheese.yaml',
    'Meanwhile, bring 2 quarts water to a boil in a large heavy-bottomed saucepan or Dutch oven. Add the remaining 1½ teaspoons salt and the macaroni; cook until almost tender but still a little firm to the bite. Drain and return to the pan over low heat. Add the butter; toss to melt.',
  ),
  ('0315-oven-fried-onion-rings.yaml', '30 saltine crackers'),
  (
    '0358-classic-spaghetti-and-meatballs-for-a-crowd.yaml',
    '2 tablespoons table salt',
  ),
  (
    '0376-biang-biang-mian-flat-hand-pulled-noodles-with-chili-oil-vinaigrette.yaml',
    '10–20 bird chiles, ground fine',
  ),
  ('0396-grilled-tomato-and-cheese-pizza.yaml', '1¼ teaspoons salt'),
  ('0398-ultimate-grilled-pizza.yaml', '1½ teaspoons salt'),
  ('0400-really-good-garlic-bread.yaml', '8 tablespoons unsalted butter'),
  (
    '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
    '1 tablespoon minced fresh oregano',
  ),
  ('0407-eggplant-parmesan.yaml', '1 tablespoon kosher salt (see note)'),
  (
    '0407-eggplant-parmesan.yaml',
    '2 pounds globe eggplant (2 medium eggplants), cut crosswise into ¼-inch-thick rounds',
  ),
  (
    '0407-eggplant-parmesan.yaml',
    'Toss half of the eggplant slices and 1½ teaspoons of the kosher salt in a large bowl until combined; transfer the salted eggplant to a large colander set over a bowl. Repeat with the remaining eggplant and kosher salt, placing the second batch on top of the first. Let stand until the eggplant releases about 2 tablespoons liquid, 30 to 45 minutes. Spread the eggplant slices on a triple thickness of paper towels; cover with another triple thickness of paper towels. Press firmly on each slice to remove as much liquid as possible, then wipe off the excess salt.',
  ),
  ('0422-chicken-canzanese.yaml', '12 whole fresh sage leaves'),
  ('0428-ultimate-shrimp-scampi.yaml', '3 tablespoons salt'),
  ('0434-salade-lyonnaise.yaml', '1 recipe Perfect Poached Eggs'),
  ('0434-salade-lyonnaise.yaml', 'Table salt for poaching eggs'),
  (
    '0457-beef-burgundy.yaml',
    '1 (750-milliliter) bottle red Burgundy or Pinot Noir',
  ),
  (
    '0459-modern-beef-burgundy.yaml',
    '1 (750-ml) bottle red Burgundy or Pinot Noir',
  ),
  ('0478-ground-beef-tacos.yaml', '8 (6-inch) corn tortillas'),
  ('0478-ground-beef-tacos.yaml', '8 Home-Fried Taco Shells (recipe follows)'),
  (
    '0478-ground-beef-tacos.yaml',
    '¾ cup corn oil, vegetable oil, or canola oil',
  ),
  (
    '0481-carne-deshebrada-shredded-beef-tacos.yaml',
    'Adjust oven rack to lower-middle position and heat oven to 325 degrees. Combine beer, vinegar, anchos, tomato paste, garlic, bay leaves, cumin, oregano, 2 teaspoons salt, ½ teaspoon pepper, cloves, and cinnamon in Dutch oven. Arrange onion rounds in single layer on bottom of pot. Place beef on top of onion rounds in single layer. Cover and cook until meat is well browned and tender, 2½ to 3 hours.',
  ),
  (
    '0481-carne-deshebrada-shredded-beef-tacos.yaml',
    'Using two forks, shred beef into bite-size pieces. Bring sauce to simmer over medium heat. Add shredded beef and stir to coat. Season with salt to taste. (Beef can be refrigerated for up to 2 days; gently reheat before serving.)',
  ),
  (
    '0481-carne-deshebrada-shredded-beef-tacos.yaml',
    'While beef cooks, whisk vinegar, water, sugar, and salt in large bowl until sugar is dissolved. Add cabbage, onion, carrot, jalapeño, and oregano and toss to combine. Cover and refrigerate for at least 1 hour or up to 24 hours. Drain slaw and stir in cilantro right before serving.',
  ),
  ('0481-carne-deshebrada-shredded-beef-tacos.yaml', '½ cup cider vinegar'),
  ('0498-best-vegetarian-chili.yaml', '2 dried New Mexican chiles'),
  ('0498-best-vegetarian-chili.yaml', '2 dried ancho chiles'),
  (
    '0525-orange-flavored-chicken.yaml',
    '8 small whole dried red chiles (optional)',
  ),
  (
    '0529-stir-fried-chicken-and-zucchini-with-ginger-sauce.yaml',
    '2 tablespoons peanut or vegetable oil',
  ),
  (
    '0540-sichuan-stir-fried-pork-in-garlic-sauce.yaml',
    'Cut pork into 2-inch lengths, then cut each length into ¼-inch matchsticks. Combine pork with ½ cup cold water and baking soda in bowl. Let sit at room temperature for 15 minutes.',
  ),
  (
    '0540-sichuan-stir-fried-pork-in-garlic-sauce.yaml',
    'Rinse pork in cold water. Drain well and pat dry with paper towels. Whisk rice wine and cornstarch together in bowl. Add pork and toss to coat.',
  ),
  (
    '0548-thai-green-curry-with-chicken-broccoli-and-mushrooms.yaml',
    '1 recipe Green Curry Paste (recipe follows) or 2 tablespoons store-bought green curry paste',
  ),
  (
    '0551-panang-beef-curry.yaml',
    '1 Thai red chile, halved lengthwise (optional)',
  ),
  (
    '0553-thai-style-stir-fried-noodles-with-chicken-and-broccolini.yaml',
    'Combine chicken with 2 tablespoons water and baking soda in bowl. Let sit at room temperature for 15 minutes. Rinse chicken in cold water and drain well.',
  ),
  (
    '0554-shrimp-pad-thai.yaml',
    'Combine vinegar and chile in bowl and let stand at room temperature for at least 15 minutes.',
  ),
  (
    '0554-shrimp-pad-thai.yaml',
    'Combine ¼ cup water, ½ teaspoon salt, and ¼ teaspoon sugar in small bowl. Microwave until steaming, about 30 seconds. Add radishes and let stand for 15 minutes. Drain and pat dry with paper towels.',
  ),
  (
    '0558-vietnamese-style-caramel-chicken-with-broccoli.yaml',
    '1 tablespoon baking soda',
  ),
  (
    '0558-vietnamese-style-caramel-chicken-with-broccoli.yaml',
    'Combine baking soda and 1¼ cups cold water in large bowl. Add chicken and toss to coat. Let stand at room temperature for 15 minutes. Rinse chicken in cold water and drain well.',
  ),
  (
    '0560-banh-xeo-sizzling-vietnamese-crepes.yaml',
    'Heat 1 teaspoon oil in 12-inch nonstick skillet over medium-high heat until shimmering. Add pork and onion and cook, stirring occasionally, until pork is no longer pink and onion is softened, 5 to 7 minutes. Add shrimp and remaining ¼ teaspoon salt and continue to cook, stirring occasionally, until shrimp just begin to turn pink, about 2 minutes longer. Transfer mixture to second bowl. Wipe skillet clean with paper towels. Add coconut milk and 2 teaspoons oil to crepe batter and stir to combine.',
  ),
  (
    '0560-banh-xeo-sizzling-vietnamese-crepes.yaml',
    'Heat 2 teaspoons oil in now-empty skillet over medium-high heat until just smoking. Add one-third of pork mixture and heat through until sizzling, about 30 seconds. Spread pork mixture over half of skillet. Pour ½ cup batter evenly over entire skillet. (Batter poured over filling will drain to skillet surface. If needed, tilt skillet gently to fill gaps.) Spread 1 cup bean sprouts over filling. Cook until crepe loosens completely from bottom of skillet with gentle shake, 4 to 5 minutes. Reduce heat to medium-low and continue to cook, shaking skillet occasionally, until edges of crepe are lacy and crisp and underside is golden brown, 2 to 4 minutes longer.',
  ),
  (
    '0560-banh-xeo-sizzling-vietnamese-crepes.yaml',
    '⅓ cup canned coconut milk',
  ),
  ('0567-indian-curry.yaml', '8 whole black peppercorns'),
  ('0572-ultracreamy-hummus.yaml', '2 (15-ounce) cans chickpeas, rinsed'),
  (
    '0572-ultracreamy-hummus.yaml',
    'Combine chickpeas, baking soda, and 6 cups water in medium saucepan and bring to boil over high heat. Reduce heat and simmer, stirring occasionally, until chickpea skins begin to float to surface and chickpeas are creamy and very soft, 20 to 25 minutes.',
  ),
  (
    '0572-ultracreamy-hummus.yaml',
    'Drain chickpeas in colander and return to saucepan. Fill saucepan with cold water and gently swish chickpeas with your fingers to release skins. Pour off most of water into colander to collect skins, leaving chickpeas behind in saucepan. Repeat filling, swishing, and draining 3 or 4 times until most skins have been removed (this should yield about ¾ cup skins); discard skins. Transfer chickpeas to colander to drain.',
  ),
  (
    '0572-ultracreamy-hummus.yaml',
    'While chickpeas cook, mince garlic using garlic press or rasp-style grater. Measure out 1 tablespoon garlic and set aside; discard remaining garlic. Whisk lemon juice, salt, and reserved garlic together in small bowl and let sit for 10 minutes. Strain garlic-lemon mixture through fine-mesh strainer set over bowl, pressing on solids to extract as much liquid as possible; discard solids.',
  ),
  (
    '0656-grilled-cauliflower.yaml',
    'Whisk 2 cups water, salt, and sugar in medium bowl until salt and sugar dissolve. Holding wedges by core, gently dunk in salt-sugar mixture until evenly moistened (do not dry—residual water will help cauliflower steam). Transfer wedges, rounded side down, to large plate and cover with inverted large bowl. Microwave until cauliflower is translucent and tender and paring knife inserted in thickest stem of florets (not into core) meets no resistance, 14 to 16 minutes.',
  ),
  (
    '0673-modern-cauliflower-gratin.yaml',
    'Combine sliced stems and cores, 2 cups florets, 3 cups water, and 6 tablespoons butter in Dutch oven and bring to boil over high heat. Place remaining florets in steamer basket (do not rinse bowl). Once mixture is boiling, place steamer basket in pot, cover, and reduce heat to medium. Steam florets in basket until translucent and stem ends can be easily pierced with paring knife, 10 to 12 minutes. Remove steamer basket and drain florets. Re-cover pot, reduce heat to low, and continue to cook stem mixture until very soft, about 10 minutes longer. Transfer drained florets to now-empty bowl.',
  ),
  (
    '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
    '1 recipe Crispy Onions, plus 3 tablespoons reserved oil (recipe follows)',
  ),
  (
    '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
    '1½ cups vegetable oil',
  ),
  (
    '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
    '2 pounds onions, halved and sliced crosswise into ¼-inch-thick pieces',
  ),
  (
    '0718-barley-salad-with-pomegranate-pistachios-and-feta.yaml',
    '½ cup pomegranate seeds',
  ),
  (
    '0731-curry-deviled-eggs-with-easy-peel-hard-cooked-eggs.yaml',
    '1 recipe Easy-Peel Hard-Cooked Eggs (recipe follows)',
  ),
  (
    '0731-curry-deviled-eggs-with-easy-peel-hard-cooked-eggs.yaml',
    '6 large eggs',
  ),
  ('0805-fougasse.yaml', '2 teaspoons coarse sea salt, divided'),
  ('0841-almond-biscotti.yaml', '1¼ cups whole almonds, lightly toasted'),
  (
    '0884-classic-yellow-layer-cake-with-vanilla-buttercream.yaml',
    '4 sticks unsalted butter, cut into chunks and softened',
  ),
  (
    '0887-old-fashioned-chocolate-layer-cake-with-chocolate-frosting.yaml',
    '8 tablespoons (1 stick) unsalted butter',
  ),
  ('0957-easy-apple-strudel.yaml', '¼ cup fresh bread crumbs'),
  ('0981-sweet-cherry-pie.yaml', '2 red plums, halved and pitted'),
  (
    '1081-crispy-fish-sandwiches-with-tartar-sauce.yaml',
    '4 leaves Bibb lettuce',
  ),
  ('1084-rhode-islandstyle-fried-calamari.yaml', '1½ cups all-purpose flour'),
  (
    '1084-rhode-islandstyle-fried-calamari.yaml',
    'Whisk milk and salt together in medium bowl. Combine flour, baking powder, and pepper in second medium bowl. Add squid to milk mixture and toss to coat. Using your hands or slotted spoon, remove half of squid, allowing excess milk mixture to drip back into bowl, and add to bowl with flour mixture. Using your hands, toss to coat evenly. Gently shake off excess flour and place coated squid in single layer on unlined rack. Repeat with remaining squid. Add 1 cup banana peppers to flour mixture and toss with your hands to coat evenly. Gently shake off excess flour mixture and sprinkle peppers evenly among squid. Let sit for 10 minutes.',
  ),
  (
    '1155-champagne-cocktail.yaml',
    '5½ fluid ounces (½ cup plus 3 tablespoons) champagne, chilled',
  ),
  (
    '1177-caramelized-onion-pear-and-bacon-tart.yaml',
    '1 Bosc pear, quartered, cored, and sliced ¼ inch thick, divided',
  ),
  (
    '1192-gado-gado.yaml',
    '4 Easy-Peel Hard-Cooked Eggs (this page), halved lengthwise',
  ),
  ('1201-rainbow-cake.yaml', '10 cups Vanilla Frosting (recipe follows)'),
  (
    '1208-albondigas-en-chipotle.yaml',
    '1 tablespoon minced fresh oregano or 1 teaspoon dried',
  ),
  // nutrition_v16 (and the two trims Run 048 restored in v15 / c1).
  (
    '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
    'Salt and pepper',
  ),
  (
    '0405-acquacotta-tuscan-white-bean-and-escarole-soup.yaml',
    '½ cup extra-virgin olive oil',
  ),
  (
    '0711-mujaddara-rice-and-lentils-with-crispy-onions.yaml',
    '2 teaspoons salt',
  ),
  (
    '0471-classic-guacamole.yaml',
    '¼ teaspoon grated lime zest plus 1½–2 tablespoons juice',
  ),
  (
    '0108-cioppino.yaml',
    '1 pound littleneck clams, scrubbed',
  ),
  (
    '0416-lighter-chicken-parmesan.yaml',
    '1 recipe Simple Tomato Sauce (recipe follows), warmed (see note)',
  ),
  (
    '0809-multigrain-bread.yaml',
    '1 envelope (2¼ teaspoons) instant or rapid-rise yeast',
  ),
];
