import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/v1/admin/nutrition_review.dart' as review_route;
import '../routes/api/v1/auth/change_password.dart' as change_password_route;
import '../routes/api/v1/auth/login.dart' as login_route;
import '../routes/api/v1/auth/me.dart' as me_route;
import '../routes/api/v1/import/candidates.dart' as candidates_route;
import '../routes/api/v1/import/index.dart' as import_route;
import '../routes/api/v1/import/jobs/[id].dart' as import_job_route;
import '../routes/api/v1/library/index.dart' as library_route;
import '../routes/api/v1/library/rescan.dart' as rescan_route;
import '../routes/api/v1/nutrition/bulk/counts.dart' as bulk_counts_route;
import '../routes/api/v1/nutrition/jobs/[id].dart' as nutrition_job_route;
import '../routes/api/v1/recipes/[id]/favorite.dart' as favorite_route;
import '../routes/api/v1/recipes/[id]/index.dart' as recipe_route;
import '../routes/api/v1/recipes/[id]/note.dart' as note_route;
import '../routes/api/v1/recipes/[id]/nutrition/compute.dart' as compute_route;
import '../routes/api/v1/recipes/[id]/nutrition/index.dart' as nutrition_route;
import '../routes/api/v1/recipes/[id]/nutrition/matches/[pos].dart'
    as match_pos_route;
import '../routes/api/v1/recipes/[id]/nutrition/matches/index.dart'
    as matches_route;
import '../routes/api/v1/recipes/index.dart' as recipes_route;
import '../routes/api/v1/tags/[name]/style.dart' as tag_style_route;
import '../routes/api/v1/tags/index.dart' as tags_route;
import '../routes/api/v1/users/index.dart' as users_route;
import 'support/contract_goldens.dart';
import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

// Auth inputs cannot come from a recipe corpus, so they are synthesized —
// as everywhere else in this suite. Same for the personal note below: it is
// user-authored text, not recipe/ingredient/nutrition data.
const String _adminPassword = 'contract-admin-password';
const String _newPassword = 'contract-changed-password';
const String _tempUsername = 'newcomer';
const String _note = 'Halved the chili flakes.';
const Map<String, String> _csrf = {'X-Requested-With': 'SaltToTaste'};

/// The one real legacy-v0 recipe committed to this repo (kept from the P8
/// cutover). It needs no corpus, which is what lets the recipe, tag and
/// match goldens be captured in CI.
const String _legacyDir = 'test/fixtures/legacy-v0';
const String _legacyFile =
    'brown-butter-gemelli-with-asparagus,-walnuts,-and-lemony-ricotta.yaml';
const String _legacyImage =
    'brown-butter-gemelli-with-asparagus,-walnuts,-and-lemony-ricotta.jpg';

// The two corpus recipes with recorded real FDC responses (see
// test/fixtures/fdc), plus a third used only as a "new file appeared in the
// library" case for the reconciliation scan.
const String _bundtFile = '0857-rich-chocolate-bundt-cake.yaml';
const String _pancakesFile = '0747-100-percent-whole-wheat-pancakes.yaml';
const String _soupFile = '0020-sweet-potato-soup.yaml';
const String _bundtSlug = 'rich-chocolate-bundt-cake';

// A deliberately broken document — the one class of input the corpus cannot
// supply. It exercises the importer's failure counter and the scan's
// `skipped` entries, both of which the Flutter app parses.
const String _malformedName = 'zzzz-malformed-document.yaml';
const String _malformedYaml = 'title: "unterminated\n';

/// Real corpus lines, parsed amounts and items exactly as the corpus stores
/// them: Italian-Style Grilled Chicken (0423), Duchess Potato Casserole
/// (0447), Super Greens Soup (0021), Stovetop Roast Chicken (0142), Roast
/// Fresh Ham (0249).
const List<Map<String, Object?>> _rulesLines = [
  {
    'raw': '1 teaspoon grated lemon zest plus 2 tablespoons juice',
    'amounts': [
      {
        'measure': 'volume',
        'quantity': '1',
        'unit': 'teaspoon',
        'primary': true,
      },
    ],
    'item': 'grated lemon zest plus 2 tablespoons juice',
  },
  {
    'raw': '1 large egg, separated, plus 2 large yolks',
    'amounts': [
      {'measure': 'count', 'quantity': '1', 'primary': true},
    ],
    'item': 'large egg',
  },
  {
    'raw': 'Pinch cayenne pepper',
    'amounts': [
      {'measure': 'count', 'quantity': '', 'unit': 'pinch', 'primary': true},
    ],
    'item': 'cayenne pepper',
  },
  {
    'raw':
        '3½ pounds bone-in, skin-on chicken pieces (split breasts cut in '
        'half, drumsticks, and/or thighs), trimmed',
    'amounts': [
      {
        'measure': 'weight',
        'quantity': '3 1/2',
        'unit': 'pound',
        'primary': true,
      },
    ],
    'item':
        'bone-in, skin-on chicken pieces (split breasts cut in half, '
        'drumsticks, and/or thighs)',
  },
  {
    'raw':
        '1 (6- to 8-pound) bone-in fresh half ham with skin, preferably '
        'shank end, rinsed',
    'amounts': [
      {'measure': 'count', 'quantity': '1', 'primary': true},
    ],
    'item': '(6- to 8-pound) bone-in fresh half ham with skin',
  },
  // Matcher v10 (checkpoint 6): a whole bird on its ready-to-cook yield
  // (0004), mussels held in the shell (Cioppino, 0108), and napa counted on
  // its sibling's nutrients (0506) — read from the cached answer the
  // vinegar line before it holds (Pai Huang Gua, 0504).
  {
    'raw': '1 (4-pound) whole chicken, giblets discarded',
    'amounts': [
      {'measure': 'count', 'quantity': '1', 'primary': true},
    ],
    'item': '(4-pound) whole chicken',
    'prep': 'giblets discarded',
  },
  {
    'raw': '1 pound mussels, scrubbed and debearded',
    'amounts': [
      {'measure': 'weight', 'quantity': '1', 'unit': 'pound', 'primary': true},
    ],
    'item': 'mussels',
    'prep': 'scrubbed and debearded',
  },
  {
    'raw': '4 teaspoons Chinese black vinegar',
    'amounts': [
      {
        'measure': 'volume',
        'quantity': '4',
        'unit': 'teaspoon',
        'primary': true,
      },
    ],
    'item': 'Chinese black vinegar',
  },
  {
    'raw': '12 ounces napa cabbage (½ medium head), cored and minced',
    'amounts': [
      {'measure': 'weight', 'quantity': '12', 'unit': 'ounce', 'primary': true},
    ],
    'item': 'napa cabbage (1/2 medium head)',
    'prep': 'cored and minced',
  },
  // Matcher v11: napa with its grams entered by hand (Pork Lo Mein, 0540)
  // still names the sibling whose nutrients its totals read.
  {
    'raw':
        '1 pound napa cabbage (1 small head), cored and cut into ½-inch '
        'strips',
    'amounts': [
      {'measure': 'weight', 'quantity': '1', 'unit': 'pound', 'primary': true},
    ],
    'item': 'napa cabbage (1 small head)',
    'prep': 'cored and cut into 1/2-inch strips',
  },
  // Classic Macaroni and Cheese (0300), with its two salt steps
  // ([_rulesSteps]): the pasta water's tablespoon held for review, the
  // roux's "remaining 1 teaspoon" its grams.
  {
    'raw': '1 tablespoon plus 1 teaspoon table salt',
    'amounts': [
      {
        'measure': 'volume',
        'quantity': '1',
        'unit': 'tablespoon',
        'primary': true,
      },
    ],
    'item': 'plus 1 teaspoon table salt',
  },
  // C1 (2026-09-28): pancetta, a flagged approximation counted as bacon
  // (Pasta e Ceci, 0340: its basis ends "· approximation (counted as …)"),
  // and the butter "stick" no grams resolves (Classic Yellow Layer Cake,
  // 0884), whose cached portions carry the tap-to-fill 4 × 113 g.
  {
    'raw': '2 ounces pancetta, cut into ½-inch pieces',
    'amounts': [
      {'measure': 'weight', 'quantity': '2', 'unit': 'ounce', 'primary': true},
    ],
    'item': 'pancetta',
    'prep': 'cut into 1/2-inch pieces',
  },
  {
    'raw': '4 sticks unsalted butter, cut into chunks and softened',
    'amounts': [
      {'measure': 'count', 'quantity': '4', 'unit': 'stick', 'primary': true},
    ],
    'item': 'unsalted butter',
    'prep': 'cut into chunks and softened',
  },
  // Matcher v41 (R2), APPENDED (the PUTs below address positions 9 and
  // 12): Wilted Spinach Salad's (0040) bacon, rendered by its pour-off step
  // ([_rulesSteps]' last) — one row, two records (`parts`), flagged.
  {
    'raw': '10 ounces (about 8 slices) thick-cut bacon, cut into ½-inch pieces',
    'amounts': [
      {'measure': 'weight', 'quantity': '10', 'unit': 'ounce', 'primary': true},
    ],
    'item': '(about 8 slices) thick-cut bacon',
    'prep': 'cut into 1/2-inch pieces',
  },
];

/// 0799 Sourdough Starter's lines and method, as the corpus stores them:
/// the whole-wheat flour is a starter feeding (`starter_discard`).
const List<Map<String, Object?>> _starterLines = [
  {
    'raw': '4½ cups (24¾ ounces) whole-wheat flour',
    'amounts': [
      {
        'measure': 'volume',
        'quantity': '4 1/2',
        'unit': 'cup',
        'primary': true,
      },
      {
        'measure': 'weight',
        'quantity': '24 3/4',
        'unit': 'ounce',
        'primary': false,
      },
    ],
    'item': 'whole-wheat flour',
  },
  {
    'raw':
        '5 cups (25 ounces) all-purpose flour, plus extra for maintaining '
        'starter',
    'amounts': [
      {'measure': 'volume', 'quantity': '5', 'unit': 'cup', 'primary': true},
      {
        'measure': 'weight',
        'quantity': '25',
        'unit': 'ounce',
        'primary': false,
      },
    ],
    'item': 'all-purpose flour',
    'prep': 'plus extra for maintaining starter',
  },
  {
    'raw': 'Water, room temperature',
    'amounts': [],
    'item': 'Water',
    'prep': 'room temperature',
  },
];

const List<Map<String, Object?>> _starterSteps = [
  {
    'number': 1,
    'text':
        'Combine whole-wheat flour and all-purpose flour in large '
        'container. Using wooden spoon, mix 1 cup (5 ounces) flour mixture '
        'and ⅔ cup (5⅓ ounces) room-temperature water in glass bowl until '
        'no dry flour remains (reserve remaining flour mixture). Cover with'
        ' plastic wrap and let sit at room temperature until bubbly and '
        'fragrant, 48 to 72 hours.',
  },
  {
    'number': 2,
    'label': 'FEED STARTER',
    'text':
        'Measure out ¼ cup (2 ounces) starter and transfer to clean bowl or'
        ' jar; discard remaining starter. Stir ½ cup (2½ ounces) flour '
        'mixture and ¼ cup (2 ounces) water into starter until no dry flour'
        ' remains. Cover with plastic wrap and let sit at room temperature '
        'for 24 hours.',
  },
  {
    'number': 3,
    'text':
        'Repeat step 2 every 24 hours until starter is pleasantly aromatic '
        'and doubles in size 8 to 12 hours after being refreshed, about 10 '
        'to 14 days. At this point starter is mature and ready to be baked '
        'with, or it can be moved to storage. (If baking, use starter once '
        'it has doubled in size during 8- to 12-hour window. Use starter '
        'within 1 hour after it starts to deflate once reaching its peak.)',
  },
  {
    'number': 4,
    'text':
        'Measure out ¼ cup (2 ounces) starter and transfer to clean bowl; '
        'discard remaining starter. Stir ½ cup (2½ ounces) all-purpose '
        'flour and ¼ cup (2 ounces) room-temperature water into starter '
        'until no dry flour remains. Transfer to clean container that can '
        'be loosely covered (plastic container or mason jar with its lid '
        'inverted) and let sit at room temperature for 5 hours. Cover and '
        'transfer to refrigerator. If not baking regularly, repeat process '
        'weekly.',
  },
  {
    'number': 5,
    'text':
        'Eighteen to 24 hours before baking, measure out ½ cup (4 ounces) '
        'starter and transfer to clean bowl; discard remaining starter. '
        'Stir 1 cup (5 ounces) all-purpose flour and ½ cup (4 ounces) '
        'room-temperature water into starter until no dry flour remains. '
        'Cover and let sit at room temperature for 5 hours. Measure out '
        'amount of starter called for in bread recipe and transfer to '
        'second bowl. Cover and transfer to refrigerator for at least 12 '
        'hours or up to 18 hours. Remaining starter should be refrigerated '
        'and maintained as directed.',
  },
];

/// Classic Macaroni and Cheese's (0300) salt steps, verbatim (the second
/// cut after its whisking sentence).
const List<Map<String, Object?>> _rulesSteps = [
  {
    'number': 1,
    'text':
        'Adjust an oven rack to the lower-middle position and heat the '
        'broiler. Bring 4 quarts water to a rolling boil in a large pot. Add '
        '1 tablespoon of the salt and the macaroni and stir to separate the '
        'noodles. Cook until tender, drain, and set aside.',
  },
  {
    'number': 2,
    'text':
        'In the now-empty pot, melt the butter over medium-high heat. Add the '
        'flour, mustard, cayenne (if using), and remaining 1 teaspoon salt '
        'and whisk well to combine. Continue whisking until the mixture '
        'becomes fragrant and deepens in color, about 1 minute.',
  },
  // Wilted Spinach Salad's (0040) step 2, verbatim (matcher v41, R2).
  {
    'number': 3,
    'text':
        'Fry the bacon in a medium skillet over medium-high heat, stirring '
        'occasionally, until crisp, about 10 minutes. Using a slotted spoon, '
        'transfer the bacon to a paper towel–lined plate. Pour off all but 3 '
        'tablespoons of the bacon fat left in the pan. Add the onion to the '
        'skillet and cook over medium heat, stirring frequently, until '
        'softened, about 3 minutes. Stir in the garlic and cook until '
        'fragrant, about 15 seconds. Add the vinegar mixture, then remove the '
        'skillet from the heat. Working quickly, scrape the bottom of the '
        'skillet with a wooden spoon to loosen the browned bits. Pour the hot '
        'dressing over the spinach, add the bacon, and toss gently until the '
        'spinach is slightly wilted. Divide the salad among individual plates, '
        'arrange the egg quarters over each, and serve.',
  },
];

// A conflict copy exactly as `exportRecipeYaml` names them.
const String _conflictSuffix = '.conflict-20260101T120000.yaml';

/// Golden contract fixtures: the REAL server routes render the bodies, the
/// bodies are committed under `packages/salt_shared/test/fixtures/contract`,
/// and `apps/app/test/contract_golden_parse_test.dart` re-parses those same
/// files with the REAL Flutter models.
///
/// A server-side key rename now fails HERE (the golden no longer matches)
/// instead of silently changing what the app sees — the review's motivating
/// example being `must_change_password`, which the app defaults to `false`
/// when the key is missing, so a rename would quietly stop forcing password
/// changes.
///
/// The captures are split in two so that everything which can be generated
/// WITHOUT the ATK corpus is generated in CI as well. A gate around the
/// whole file would leave the pin to a developer machine, and the static
/// committed goldens the app parses would keep agreeing with themselves.
///
/// Regenerate deliberately:
///   SALT_CORPUS_DIR=... UPDATE_CONTRACT_GOLDENS=1 \
///     dart test test/contract_golden_test.dart
void main() {
  // Runs everywhere, corpus or not: the committed goldens are the app's
  // only input, so a deleted or corrupted one must fail in CI too. Skipped
  // while regenerating, when the files are being (re)created by this run.
  group(
    'committed contract goldens',
    skip: updateContractGoldens
        ? 'regenerating: the files are written by this run'
        : null,
    () {
      test('every named golden exists and is a JSON object', () {
        for (final name in contractGoldenNames) {
          final file = contractGoldenFile(name);
          expect(
            file.existsSync(),
            isTrue,
            reason:
                '${file.path} is missing; regenerate with '
                'UPDATE_CONTRACT_GOLDENS=1 dart test '
                'test/contract_golden_test.dart',
          );
          expect(
            jsonDecode(file.readAsStringSync()),
            isA<Map<String, Object?>>(),
            reason: '${file.path} must hold one response body',
          );
        }
      });

      test('the goldens carry no machine-specific values', () {
        for (final name in contractGoldenNames) {
          final text = contractGoldenFile(name).readAsStringSync();
          for (final leak in [
            Directory.systemTemp.path,
            '/Users/',
            '/home/',
          ]) {
            expect(
              text,
              isNot(contains(leak)),
              reason: '$name.json leaks a local path ($leak)',
            );
          }
        }
      });
    },
  );

  test('every golden belongs to exactly one capture group', () {
    expect(
      corpusFreeContractGoldenNames.toSet().intersection(
        corpusBackedContractGoldenNames.toSet(),
      ),
      isEmpty,
    );
    expect(
      {...corpusFreeContractGoldenNames, ...corpusBackedContractGoldenNames},
      contractGoldenNames.toSet(),
    );
  });

  // ------------------------------------------------------------------
  // No corpus needed — runs in CI, where the pin has to bite.
  // ------------------------------------------------------------------
  group('corpus-free bodies match the committed goldens', () {
    final harness = _Harness('salt_contract_free_');

    setUpAll(() async {
      await harness.start();
      final adminSession = await harness.seedAdminAndCaptureAuth();

      // A real recipe with no corpus: the committed legacy-v0 fixture,
      // imported through the real POST /api/v1/import (format
      // auto-detected).
      final root = Directory('${harness.config.importDir}/legacy sample')
        ..createSync(recursive: true);
      Directory('${root.path}/_recipes').createSync();
      Directory('${root.path}/_images').createSync();
      File('$_legacyDir/_recipes/$_legacyFile').copySync(
        '${root.path}/_recipes/$_legacyFile',
      );
      // A legacy-v0 import takes `extraction.extracted_at` from the source
      // file's MTIME rather than the wall clock, on purpose (legacy_import
      // .dart: a wall-clock date made every re-run on a later day an "update"
      // that clobbered in-app edits). Git does not preserve mtimes, so the
      // checked-out fixture carries whatever instant the clone happened —
      // which differs between a developer's machine and every CI run, and
      // flows through the recipe document into `base_hash`. Pinning the COPY's
      // mtime makes both deterministic, and turns the drift into an assertion:
      // the golden's extracted_at is exactly this date.
      File(
        '${root.path}/_recipes/$_legacyFile',
      ).setLastModifiedSync(DateTime.utc(2026, 7, 16, 12));
      File('$_legacyDir/_images/$_legacyImage').copySync(
        '${root.path}/_images/$_legacyImage',
      );
      await harness.runImport('legacy sample', adminSession);

      final page = await harness.capture(
        'recipes_page',
        'GET',
        '/api/v1/recipes',
        headers: harness.auth(adminSession),
      );
      final card =
          (page['items']! as List<dynamic>).single as Map<String, dynamic>;
      final slug = card['slug']! as String;

      // Personal data, so `favorite`/`note` are pinned as populated values
      // rather than as nulls the app would parse either way.
      await harness.expectOk(
        'PUT',
        '/api/v1/recipes/$slug/favorite',
        headers: harness.auth(adminSession, csrf: true),
      );
      await harness.expectOk(
        'PUT',
        '/api/v1/recipes/$slug/note',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {'note': _note},
      );
      // A word from the recipe's own real ingredient list, so the ranked FTS
      // path renders this body rather than the plain listing path. Captured
      // AFTER the favorite so the two card goldens differ where it matters:
      // recipes_page carries `favorite: false`, this one `true`.
      await harness.capture(
        'recipes_search',
        'GET',
        '/api/v1/recipes?q=asparagus',
        headers: harness.auth(adminSession),
      );
      await harness.capture(
        'recipe_detail',
        'GET',
        '/api/v1/recipes/$slug',
        headers: harness.auth(adminSession),
      );

      // A recipe whose nutrition was never computed: every line comes back
      // `"match": null`, which is the app's unmatched-line parse branch.
      await harness.capture(
        'nutrition_matches_uncomputed',
        'GET',
        '/api/v1/recipes/$slug/nutrition/matches',
        headers: harness.auth(adminSession),
      );

      // --- tags: before and after a chip style ---------------------------
      final unstyled = await harness.capture(
        'tags_unstyled',
        'GET',
        '/api/v1/tags',
        headers: harness.auth(adminSession),
      );
      final tag =
          ((unstyled['items']! as List<dynamic>).first
                  as Map<String, dynamic>)['name']!
              as String;
      await harness.expectOk(
        'PUT',
        '/api/v1/tags/${Uri.encodeComponent(tag)}/style',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {
          'icon': 'utensils-crossed',
          'color': '#960000',
          'bg_color': '#F6E7E7',
        },
      );
      await harness.capture(
        'tags_styled',
        'GET',
        '/api/v1/tags',
        headers: harness.auth(adminSession),
      );

      await harness.captureMustChangeAccount(adminSession);

      // --- nutrition rules: the matcher-v8 bases and holds, corpus-free ---
      // A recipe made through the real POST of real corpus lines (their
      // parsed amounts and items exactly as the corpus stores them), computed
      // over the recorded FDC answers: the citrus-juice and egg-sum second
      // foods, a pinch sized from the teaspoon, bird pieces on the
      // whole-bird record, and a fresh ham held off the cured record.
      // Rule B1 (v41) counts the cooked bacon on SR 168322, which the FDC
      // fixtures hold only as a hit of the "thin-sliced cooked deli ham"
      // answer (snapshot 17 has no detail of it): Stuffed Chicken Cutlets
      // with Ham and Cheddar's (0118) ham line, computed first, caches that
      // answer as a library does — the appended bacon line reads it there.
      final (hamPosted, hamBody) = await harness.send(
        'POST',
        '/api/v1/recipes',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {
          'recipe': {
            'title': 'Stuffed Chicken Cutlets with Ham and Cheddar',
            'ingredients': [
              {
                'items': [
                  {
                    'raw':
                        '4 slices (about 4 ounces) thin-sliced cooked deli ham',
                    'amounts': [
                      {
                        'measure': 'count',
                        'quantity': '4',
                        'unit': 'slice',
                        'primary': true,
                      },
                      {
                        'measure': 'weight',
                        'quantity': '4',
                        'unit': 'ounce',
                        'approximate': true,
                        'primary': false,
                      },
                    ],
                    'item': 'thin-sliced cooked deli ham',
                  },
                ],
              },
            ],
          },
        },
      );
      expect(hamPosted, HttpStatus.created, reason: hamBody);
      final hamSlug =
          ((jsonDecode(hamBody) as Map<String, dynamic>)['recipe']!
              as Map<String, dynamic>)['slug'];
      final (hamQueued, hamQueuedBody) = await harness.send(
        'POST',
        '/api/v1/recipes/$hamSlug/nutrition/compute',
        headers: harness.auth(adminSession, csrf: true),
      );
      expect(hamQueued, HttpStatus.accepted, reason: hamQueuedBody);
      await harness.awaitJob(
        '/api/v1/nutrition/jobs/'
        '${(jsonDecode(hamQueuedBody) as Map<String, dynamic>)['job_id']}',
        harness.auth(adminSession),
      );
      final (created, createdBody) = await harness.send(
        'POST',
        '/api/v1/recipes',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {
          'recipe': {
            'title': 'Nutrition rules sample',
            'ingredients': [
              {'items': _rulesLines},
            ],
            'steps': _rulesSteps,
          },
        },
      );
      expect(created, HttpStatus.created, reason: createdBody);
      final rulesSlug =
          ((jsonDecode(createdBody) as Map<String, dynamic>)['recipe']!
                  as Map<String, dynamic>)['slug']!
              as String;
      final (computed, computeBody) = await harness.send(
        'POST',
        '/api/v1/recipes/$rulesSlug/nutrition/compute',
        headers: harness.auth(adminSession, csrf: true),
      );
      expect(computed, HttpStatus.accepted, reason: computeBody);
      await harness.awaitJob(
        '/api/v1/nutrition/jobs/'
        '${(jsonDecode(computeBody) as Map<String, dynamic>)['job_id']}',
        harness.auth(adminSession),
      );
      final (edited, editBody) = await harness.send(
        'PUT',
        '/api/v1/recipes/$rulesSlug/nutrition/matches/9',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {'grams': 400},
      );
      expect(edited, HttpStatus.ok, reason: editBody);
      await harness.capture(
        'nutrition_matches_rules',
        'GET',
        '/api/v1/recipes/$rulesSlug/nutrition/matches',
        headers: harness.auth(adminSession),
      );
      // The butter line confirmed WITH its amount (grams-on-confirm, C1) and
      // offered to the ingredient: the receipt carries `applied.completed`.
      await harness.capture(
        'nutrition_confirm_applied',
        'PUT',
        '/api/v1/recipes/$rulesSlug/nutrition/matches/12',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {'confirmed': true, 'grams': 452, 'apply_to_all': true},
      );

      // The receipt's `completed` over the route (C1): a pick that reaches
      // a recipe which was ALREADY complete does not count it. Hearty Lentil
      // Soup's (0024) and Boston Baked Beans' (0679) bacon lines, each its
      // recipe's only line, both counted on the cured-bacon record; a pick
      // of "Bacon bits" on the soup's line reaches the beans' line (another
      // food) — rewritten, recomputed, still complete, so completed is 0.
      Future<String> baconRecipe(
        String title,
        Map<String, Object?> line,
      ) async {
        final (status, body) = await harness.send(
          'POST',
          '/api/v1/recipes',
          headers: harness.auth(adminSession, csrf: true),
          jsonBody: {
            'recipe': {
              'title': title,
              'ingredients': [
                {
                  'items': [line],
                },
              ],
            },
          },
        );
        expect(status, HttpStatus.created, reason: body);
        final slug =
            ((jsonDecode(body) as Map<String, dynamic>)['recipe']!
                    as Map<String, dynamic>)['slug']!
                as String;
        final (queued, queuedBody) = await harness.send(
          'POST',
          '/api/v1/recipes/$slug/nutrition/compute',
          headers: harness.auth(adminSession, csrf: true),
        );
        expect(queued, HttpStatus.accepted, reason: queuedBody);
        await harness.awaitJob(
          '/api/v1/nutrition/jobs/'
          '${(jsonDecode(queuedBody) as Map<String, dynamic>)['job_id']}',
          harness.auth(adminSession),
        );
        return slug;
      }

      Future<String> statusOf(String slug) async {
        final (status, body) = await harness.send(
          'GET',
          '/api/v1/recipes/$slug/nutrition',
          headers: harness.auth(adminSession),
        );
        expect(status, HttpStatus.ok, reason: body);
        return (jsonDecode(body) as Map<String, dynamic>)['status']! as String;
      }

      final soup = await baconRecipe('Hearty Lentil Soup', {
        'raw': '3 ounces (3 slices) bacon, cut into ¼-inch pieces',
        'amounts': [
          {
            'measure': 'weight',
            'quantity': '3',
            'unit': 'ounce',
            'primary': true,
          },
        ],
        'item': '(3 slices) bacon',
        'prep': 'cut into 1/4-inch pieces',
      });
      final beans = await baconRecipe('Boston Baked Beans', {
        'raw': '2 ounces (about 2 slices) bacon, cut into ¼-inch pieces',
        'amounts': [
          {
            'measure': 'weight',
            'quantity': '2',
            'unit': 'ounce',
            'primary': true,
          },
        ],
        'item': '(about 2 slices) bacon',
        'prep': 'cut into 1/4-inch pieces',
      });
      expect(await statusOf(beans), 'complete');
      // The receipt's other reasons over the route, each non-zero (Run 053
      // O12/S8): a recipe of the beans' line that a save made another
      // ingredient (0405's onion; not yet computed, so its row still bears
      // the bacon key) is `gone`; one whose stored doc will not decode (a
      // synthesized negative-path input, restored after) is `failed`, its
      // line in `failed_lines`. (`decided` needs a person's write during
      // the apply's await: pinned in-process, nutrition_v23_writepath_test.)
      final editedAway = await baconRecipe('Boston Baked Beans, edited', {
        'raw': '2 ounces (about 2 slices) bacon, cut into ¼-inch pieces',
        'amounts': [
          {
            'measure': 'weight',
            'quantity': '2',
            'unit': 'ounce',
            'primary': true,
          },
        ],
        'item': '(about 2 slices) bacon',
        'prep': 'cut into 1/4-inch pieces',
      });
      final stored = harness.db.recipeByIdOrSlug(editedAway)!;
      const onion = '1 large onion, chopped coarse';
      final parsed = parseIngredientLine(onion);
      harness.db.upsertRecipe(
        stored.recipe.copyWith(
          ingredients: [
            IngredientGroup(
              items: [
                IngredientLine(
                  raw: onion,
                  item: parsed.item,
                  amounts: parsed.amounts,
                ),
              ],
            ),
          ],
        ),
        sourceSlug: stored.sourceSlug,
        contentHash: 'edited-away',
      );
      final undecodable = await baconRecipe(
        'Boston Baked Beans, undecodable',
        {
          'raw': '2 ounces (about 2 slices) bacon, cut into ¼-inch pieces',
          'amounts': [
            {
              'measure': 'weight',
              'quantity': '2',
              'unit': 'ounce',
              'primary': true,
            },
          ],
          'item': '(about 2 slices) bacon',
          'prep': 'cut into 1/4-inch pieces',
        },
      );
      final raw = sqlite3.open(harness.config.dbPath);
      final doc =
          raw.select('SELECT doc FROM recipes WHERE slug = ?', [
                undecodable,
              ]).single['doc']
              as String;
      raw.execute("UPDATE recipes SET doc = '{' WHERE slug = ?", [undecodable]);
      final (picked, pickedBody) = await harness.send(
        'PUT',
        '/api/v1/recipes/$soup/nutrition/matches/0',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {'fdc_id': 2707466, 'apply_to_all': true},
      );
      expect(picked, HttpStatus.ok, reason: pickedBody);
      expect((jsonDecode(pickedBody) as Map<String, dynamic>)['applied'], {
        'recipes': 1,
        'lines': 1,
        'failed': 1,
        'completed': 0,
        'completed_recipes': <String>[],
        'moved': 0,
        'decided': 0,
        'gone': 1,
        'failed_lines': 1,
        'unavailable': 0,
      });
      raw
        ..execute('UPDATE recipes SET doc = ? WHERE slug = ?', [
          doc,
          undecodable,
        ])
        ..dispose();
      expect(await statusOf(beans), 'complete');

      // A pick alone on a held line that is not divided (Run 054 S5/O6):
      // 0799's whole-wheat flour, a starter feeding, picked on its own
      // food — the row stays held with no grams (status overridden, the
      // hold kept), the No grams row the app must still explain.
      final (starter, starterBody) = await harness.send(
        'POST',
        '/api/v1/recipes',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {
          'recipe': {
            'title': 'Sourdough Starter',
            'ingredients': [
              {'items': _starterLines},
            ],
            'steps': _starterSteps,
          },
        },
      );
      expect(starter, HttpStatus.created, reason: starterBody);
      final starterSlug =
          ((jsonDecode(starterBody) as Map<String, dynamic>)['recipe']!
                  as Map<String, dynamic>)['slug']!
              as String;
      final (started, startBody) = await harness.send(
        'POST',
        '/api/v1/recipes/$starterSlug/nutrition/compute',
        headers: harness.auth(adminSession, csrf: true),
      );
      expect(started, HttpStatus.accepted, reason: startBody);
      await harness.awaitJob(
        '/api/v1/nutrition/jobs/'
        '${(jsonDecode(startBody) as Map<String, dynamic>)['job_id']}',
        harness.auth(adminSession),
      );
      final (pickedStarter, pickBody) = await harness.send(
        'PUT',
        '/api/v1/recipes/$starterSlug/nutrition/matches/0',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {'raw': _starterLines.first['raw'], 'fdc_id': 790085},
      );
      expect(pickedStarter, HttpStatus.ok, reason: pickBody);
      await harness.capture(
        'nutrition_matches_held_pick',
        'GET',
        '/api/v1/recipes/$starterSlug/nutrition/matches',
        headers: harness.auth(adminSession),
      );

      // --- matcher v41: the composite row, corpus-free ---
      // Six real corpus recipes (test/fixtures/contract-recipes/v41.json:
      // their titles, yields, prep notes, ingredient lines and section
      // titles, copied from the corpus) POSTed through the real route and
      // computed over the recorded FDC answers, children first: Blueberry
      // Pie's dough routes to the first of the three doughs its note names
      // (flagged default; Foolproof All-Butter … for Double-Crust Pie listed
      // as similar, never computed), and Free-Form Apple Tart's "Rustic Tart
      // Dough" is held `choose_recipe` (missing).
      Map<String, Map<String, dynamic>> recipesOf(String fixture) => {
        for (final entry
            in jsonDecode(
                  File(
                    'test/fixtures/contract-recipes/$fixture.json',
                  ).readAsStringSync(),
                )
                as List<dynamic>)
          (entry as Map<String, dynamic>)['corpus_file'] as String:
              entry['recipe'] as Map<String, dynamic>,
      };
      final v41 = recipesOf('v41');
      Future<String> post(
        String file, {
        bool compute = true,
        Map<String, Map<String, dynamic>>? from,
      }) async {
        final (status, body) = await harness.send(
          'POST',
          '/api/v1/recipes',
          headers: harness.auth(adminSession, csrf: true),
          jsonBody: {'recipe': (from ?? v41)[file]},
        );
        expect(status, HttpStatus.created, reason: body);
        final slug =
            ((jsonDecode(body) as Map<String, dynamic>)['recipe']!
                    as Map<String, dynamic>)['slug']!
                as String;
        if (compute) {
          final (queued, queuedBody) = await harness.send(
            'POST',
            '/api/v1/recipes/$slug/nutrition/compute',
            headers: harness.auth(adminSession, csrf: true),
          );
          expect(queued, HttpStatus.accepted, reason: queuedBody);
          await harness.awaitJob(
            '/api/v1/nutrition/jobs/'
            '${(jsonDecode(queuedBody) as Map<String, dynamic>)['job_id']}',
            harness.auth(adminSession),
          );
        }
        return slug;
      }

      await post('0973-all-butter-double-crust-pie-dough.yaml');
      await post('0972-basic-double-crust-pie-dough.yaml');
      await post('0974-foolproof-double-crust-pie-dough.yaml');
      await post(
        '0976-foolproof-all-butter-dough-for-double-crust-pie.yaml',
        compute: false,
      );
      final pie = await post('0979-blueberry-pie.yaml');
      await harness.capture(
        'nutrition_matches_subrecipe',
        'GET',
        '/api/v1/recipes/$pie/nutrition/matches',
        headers: harness.auth(adminSession),
      );
      await harness.capture(
        'nutrition_subrecipe',
        'GET',
        '/api/v1/recipes/$pie/nutrition',
        headers: harness.auth(adminSession),
      );
      final tart = await post('1005-free-form-apple-tart.yaml');
      await harness.capture(
        'nutrition_matches_choose_recipe',
        'GET',
        '/api/v1/recipes/$tart/nutrition/matches',
        headers: harness.auth(adminSession),
      );
      await harness.capture(
        'nutrition_choose_recipe',
        'GET',
        '/api/v1/recipes/$tart/nutrition',
        headers: harness.auth(adminSession),
      );
      // The queue's new chip, grouped as the admin app reads it: the tart's
      // held line, its SLIM `child`, `finishes` 0.
      await harness.capture(
        'nutrition_review_choose_recipe',
        'GET',
        '/api/v1/admin/nutrition_review?group=item&bucket=choose_recipe',
        headers: harness.auth(adminSession),
      );

      // --- matcher v44: sections as children, corpus-free ---
      // Six real corpus recipes (test/fixtures/contract-recipes/v44.json:
      // each corpus document's title, yield, prep notes, ingredient lines,
      // steps and subsections — kind, body, yield, notes, lines and steps —
      // as the corpus has them). Basic Double-Crust Pie Dough is already
      // here (v41.json, its section titles only): the real recipe PUT gives
      // it its corpus sections, so ONE host carries "Basic Single-Crust Pie
      // Dough" (the one-host guard, N8). Each POST's compute computes its
      // child sections first.
      final v44 = recipesOf('v44');
      final (doughStatus, doughBody) = await harness.send(
        'PUT',
        '/api/v1/recipes/basic-double-crust-pie-dough',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {'recipe': v44['0972-basic-double-crust-pie-dough.yaml']},
      );
      expect(doughStatus, HttpStatus.ok, reason: doughBody);
      // Chraime's "1 tablespoon tabil (recipe follows)" routes to its OWN
      // "Tabil" (MAKES ABOUT ½ CUP): share 0.125, no host title.
      final chraime = await post('1208-chraime.yaml', from: v44);
      await harness.capture(
        'nutrition_matches_section_own',
        'GET',
        '/api/v1/recipes/$chraime/nutrition/matches',
        headers: harness.auth(adminSession),
      );
      await harness.capture(
        'nutrition_section_own',
        'GET',
        '/api/v1/recipes/$chraime/nutrition',
        headers: harness.auth(adminSession),
      );
      // Pumpkin Pie's dough routes to ANOTHER recipe's section: the child
      // carries `host_title`.
      final pumpkin = await post('0987-pumpkin-pie.yaml', from: v44);
      await harness.capture(
        'nutrition_matches_section_other',
        'GET',
        '/api/v1/recipes/$pumpkin/nutrition/matches',
        headers: harness.auth(adminSession),
      );
      await harness.capture(
        'nutrition_section_other',
        'GET',
        '/api/v1/recipes/$pumpkin/nutrition',
        headers: harness.auth(adminSession),
      );
      // That section's own lines and totals: `?section=` on the shipped
      // routes (any authenticated user).
      const singleCrust = 'Basic%20Single-Crust%20Pie%20Dough';
      await harness.capture(
        'nutrition_section_matches',
        'GET',
        '/api/v1/recipes/basic-double-crust-pie-dough/nutrition/matches'
            '?section=$singleCrust',
        headers: harness.auth(adminSession),
      );
      await harness.capture(
        'nutrition_section_label',
        'GET',
        '/api/v1/recipes/basic-double-crust-pie-dough/nutrition'
            '?section=$singleCrust',
        headers: harness.auth(adminSession),
      );
      // Lemon Meringue Pie's dough names a section with no ingredient
      // lines: not routed, reason `no_ingredients`, its partial line.
      final lemon = await post('0989-lemon-meringue-pie.yaml', from: v44);
      await harness.capture(
        'nutrition_matches_section_prose',
        'GET',
        '/api/v1/recipes/$lemon/nutrition/matches',
        headers: harness.auth(adminSession),
      );
      await harness.capture(
        'nutrition_section_prose',
        'GET',
        '/api/v1/recipes/$lemon/nutrition',
        headers: harness.auth(adminSession),
      );
      // "1 recipe glaze (recipes follow)": held for a person, its own two
      // glazes listed (rule PO), computed and pickable.
      final ham = await post('0251-glazed-spiral-sliced-ham.yaml', from: v44);
      final pick = await harness.capture(
        'nutrition_matches_section_pick',
        'GET',
        '/api/v1/recipes/$ham/nutrition/matches',
        headers: harness.auth(adminSession),
      );
      final glaze =
          (pick['items']! as List<dynamic>)[2]! as Map<String, dynamic>;
      // The pick: the host's slug and the section's title; line-local.
      final (glazePut, glazePutBody) = await harness.send(
        'PUT',
        '/api/v1/recipes/$ham/nutrition/matches/2',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {
          'raw': glaze['raw'],
          'child': ham,
          'section': 'Cherry-Port Glaze',
        },
      );
      expect(glazePut, HttpStatus.ok, reason: glazePutBody);
      final routed =
          ((jsonDecode(glazePutBody) as Map<String, dynamic>)['items']!
                  as List<dynamic>)[2]!
              as Map<String, dynamic>;
      expect(
        (routed['match']! as Map<String, dynamic>)['child'],
        allOf(
          containsPair('state', 'routed'),
          containsPair('section', 'Cherry-Port Glaze'),
          containsPair('host_title', null),
        ),
      );
      expect(routed['others'], 0);
      // A section line in the queue: Satay Glaze's red curry paste (a
      // low-confidence record with no grams), its row naming the HOST and
      // the section; Grilled Glazed Pork Tenderloin Roast's own glaze line
      // picked onto it, so the group's `last_open` counts that parent.
      final roast = await post(
        '0601-grilled-glazed-pork-tenderloin-roast.yaml',
        from: v44,
      );
      final (satay, satayBody) = await harness.send(
        'PUT',
        '/api/v1/recipes/$roast/nutrition/matches/3',
        headers: harness.auth(adminSession, csrf: true),
        jsonBody: {
          'raw': '1 recipe glaze (recipes follow)',
          'child': roast,
          'section': 'Satay Glaze',
        },
      );
      expect(satay, HttpStatus.ok, reason: satayBody);
      await harness.capture(
        'nutrition_review_section',
        'GET',
        '/api/v1/admin/nutrition_review?group=item&bucket=check',
        headers: harness.auth(adminSession),
      );
    });

    tearDownAll(harness.stop);

    _goldenComparisons(harness, corpusFreeContractGoldenNames);

    test('the must-change-password flag survives the wire as true', () {
      // The review's motivating regression: the app defaults this to
      // false, so a server-side rename would silently stop forcing the
      // change. Asserted on the captured body, not just the file.
      for (final name in ['auth_me_must_change', 'auth_login_must_change']) {
        final user =
            (harness.captured[name]! as Map<String, Object?>)['user']!
                as Map<String, Object?>;
        expect(
          user['must_change_password'],
          isTrue,
          reason: '$name must carry must_change_password: true',
        );
      }
      final admin =
          (harness.captured['auth_me_admin']! as Map<String, Object?>)['user']!
              as Map<String, Object?>;
      expect(admin['must_change_password'], isFalse);
    });
  });

  // ------------------------------------------------------------------
  // Needs the real corpus: a v1 source root with hero images and a
  // source.yaml, a reconciliation scan over it, and a nutrition compute
  // whose FDC responses were recorded against those exact lines.
  // ------------------------------------------------------------------
  group(
    'corpus-backed bodies match the committed goldens',
    skip: skipIfNoCorpus,
    () {
      final harness = _Harness('salt_contract_corpus_');

      setUpAll(() async {
        await harness.start();
        await harness.seedAdmin();
        final adminSession = await harness.login('admin', _adminPassword);

        // --- import: a real v1 source root inside the allowlist ------------
        final sourceRoot = Directory('${harness.config.importDir}/atk sample')
          ..createSync(recursive: true);
        Directory('${sourceRoot.path}/recipes').createSync();
        Directory('${sourceRoot.path}/images').createSync();
        File(
          '$corpusRoot/source.yaml',
        ).copySync('${sourceRoot.path}/source.yaml');
        for (final name in [_bundtFile, _pancakesFile]) {
          File(
            '$corpusRecipesDir/$name',
          ).copySync('${sourceRoot.path}/recipes/$name');
          final hero = '${name.substring(0, name.length - 5)}-hero.jpg';
          File('$corpusImagesDir/$hero').copySync(
            '${sourceRoot.path}/images/$hero',
          );
        }
        File(
          '${sourceRoot.path}/recipes/$_malformedName',
        ).writeAsStringSync(_malformedYaml);

        await harness.capture(
          'import_candidates',
          'GET',
          '/api/v1/import/candidates',
          headers: harness.auth(adminSession),
        );
        final importJobId = await harness.runImport('atk sample', adminSession);
        // The finished job row — the body the app's ImportJob model polls.
        await harness.capture(
          'import_job',
          'GET',
          '/api/v1/import/jobs/$importJobId',
          headers: harness.auth(adminSession),
        );

        // --- nutrition: a real compute over recorded real FDC responses ----
        // Over a library whose food details are already cached (every
        // compute cached them until details turned lazy): a search hit's
        // nutrients are FDC's detail rounded, so a stand-in
        // would move the pinned amounts by rounding alone. The lazy path is
        // pinned in nutrition_sweep_audit_test.dart.
        (jsonDecode(File('test/fixtures/fdc/foods.json').readAsStringSync())
                as Map<String, dynamic>)
            .forEach(
              (id, food) =>
                  harness.db.fdcFoodCachePut(int.parse(id), jsonEncode(food)),
            );
        final (computeStatus, computeBody) = await harness.send(
          'POST',
          '/api/v1/recipes/$_bundtSlug/nutrition/compute',
          headers: harness.auth(adminSession, csrf: true),
        );
        expect(computeStatus, HttpStatus.accepted, reason: computeBody);
        final computeJobId =
            (jsonDecode(computeBody) as Map<String, dynamic>)['job_id'];
        await harness.awaitJob(
          '/api/v1/nutrition/jobs/$computeJobId',
          harness.auth(adminSession),
        );
        // Every bundt line resolves since amount-less lines count as a
        // matched 0 g (matcher v6), so the bodies below would hold no
        // flagged line for the app to parse. A reviewer's real move gives
        // one: picking a food for "Confectioners' sugar, for dusting" leaves
        // an overridden line with no amount — flagged in `no_grams`, and the
        // recipe partial.
        await harness.expectOk(
          'PUT',
          '/api/v1/recipes/$_bundtSlug/nutrition/matches/12',
          headers: harness.auth(adminSession, csrf: true),
          jsonBody: {'fdc_id': 169656},
        );
        await harness.capture(
          'nutrition',
          'GET',
          '/api/v1/recipes/$_bundtSlug/nutrition',
          headers: harness.auth(adminSession),
        );
        await harness.capture(
          'nutrition_matches',
          'GET',
          '/api/v1/recipes/$_bundtSlug/nutrition/matches',
          headers: harness.auth(adminSession),
        );
        // The cross-recipe triage queue built from that same compute — the
        // app's largest admin parse (buckets, rows, per-row recipe identity).
        await harness.capture(
          'nutrition_review',
          'GET',
          '/api/v1/admin/nutrition_review',
          headers: harness.auth(adminSession),
        );
        // The same queue GROUPED by ingredient: one row per ingredient key,
        // each carrying its example line flattened exactly like a line item
        // plus the group's reach, decided flag and amount spread.
        await harness.capture(
          'nutrition_review_grouped',
          'GET',
          '/api/v1/admin/nutrition_review?group=item',
          headers: harness.auth(adminSession),
        );

        // --- library: every branch of a reconciliation scan -----------------
        // All real data: the pancakes' ORIGINAL corpus text stands in for a
        // hand edit (same recipe, non-canonical formatting -> the file wins),
        // and a third corpus recipe appears as a brand-new file.
        final librarySource = Directory(
          harness.config.libraryDir,
        ).listSync().whereType<Directory>().single;
        final libraryRecipes = '${librarySource.path}/recipes';
        final bundtId = loadCorpusRecipe(_bundtFile).id;
        final pancakesId = loadCorpusRecipe(_pancakesFile).id;
        final soupId = loadCorpusRecipe(_soupFile).id;
        // A conflict copy left behind by an earlier save, then the export
        // itself removed: the scan must list one and re-materialize the other.
        File('$libraryRecipes/$bundtId.yaml').renameSync(
          '$libraryRecipes/$bundtId$_conflictSuffix',
        );
        File('$corpusRecipesDir/$_pancakesFile').copySync(
          '$libraryRecipes/$pancakesId.yaml',
        );
        File('$corpusRecipesDir/$_soupFile').copySync(
          '$libraryRecipes/$soupId.yaml',
        );
        File('$libraryRecipes/$_malformedName').writeAsStringSync(
          _malformedYaml,
        );
        await harness.expectOk(
          'POST',
          '/api/v1/library/rescan',
          headers: harness.auth(adminSession, csrf: true),
        );
        await harness.capture(
          'library_last_scan',
          'GET',
          '/api/v1/library',
          headers: harness.auth(adminSession),
        );

        // --- bulk-scope counts, with every scope non-zero ------------------
        // Last, so nothing above sees the edit. The library now holds the
        // computed Bundt plus two never-computed recipes (pancakes, and the
        // soup the scan just added). Dropping the Bundt's last ingredient
        // line through the real PUT changes its ingredients hash, which is
        // the one thing that makes a computed recipe `stale` — so the golden
        // carries a real stale count rather than a zero the app-side parse
        // could not tell from a dropped key.
        final (detailStatus, detailBody) = await harness.send(
          'GET',
          '/api/v1/recipes/$_bundtSlug',
          headers: harness.auth(adminSession),
        );
        expect(detailStatus, HttpStatus.ok, reason: detailBody);
        final bundt =
            (jsonDecode(detailBody) as Map<String, dynamic>)['recipe']!
                as Map<String, dynamic>;
        final groups = (bundt['ingredients']! as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final lastItems = (groups.last['items']! as List<dynamic>)
            .cast<Map<String, dynamic>>();
        groups.last['items'] = lastItems.sublist(0, lastItems.length - 1);
        await harness.expectOk(
          'PUT',
          '/api/v1/recipes/$_bundtSlug',
          headers: harness.auth(adminSession, csrf: true),
          jsonBody: {
            'recipe': {'ingredients': groups},
          },
        );
        await harness.capture(
          'nutrition_bulk_counts',
          'GET',
          '/api/v1/nutrition/bulk/counts',
          headers: harness.auth(adminSession),
        );
      });

      tearDownAll(harness.stop);

      _goldenComparisons(harness, corpusBackedContractGoldenNames);
    },
  );
}

/// The per-golden comparisons: every declared [names] entry was captured
/// from a live route this run, carries nothing machine-specific, and matches
/// the committed file byte for byte.
void _goldenComparisons(_Harness harness, List<String> names) {
  test('every golden was captured from a live route', () {
    expect(harness.captured.keys.toSet(), names.toSet());
  });

  test("no captured body leaks this run's temp directory", () {
    for (final entry in harness.captured.entries) {
      expect(
        encodeContractGolden(entry.value),
        isNot(contains(harness.tempDir.path)),
        reason:
            '${entry.key} embeds the temp data dir — add its key to '
            'contractVolatileFields',
      );
    }
  });

  for (final name in names) {
    test('$name.json', () {
      final rendered = encodeContractGolden(harness.captured[name]);
      final file = contractGoldenFile(name);
      if (updateContractGoldens) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(rendered);
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'missing golden ${file.path}',
      );
      // Rendered body is the ACTUAL; the committed golden is the EXPECTED,
      // so a regression diff reads the way it happened.
      expect(
        rendered,
        file.readAsStringSync(),
        reason:
            'The $name response shape changed. If that was deliberate, '
            'regenerate with UPDATE_CONTRACT_GOLDENS=1 and check '
            'apps/app parses the new shape.',
      );
    });
  }
}

/// A live server over the real dart_frog route files and the REAL production
/// middleware chain (`buildAppMiddleware`, the same function
/// `routes/_middleware.dart` calls), plus the capture bookkeeping.
class _Harness {
  _Harness(this._tempPrefix);

  final String _tempPrefix;

  late final Directory tempDir;
  late final ServerConfig config;
  late final SaltDatabase db;
  late final AuthRuntime runtime;
  late final FixtureProvider fdc;
  late final HttpServer _server;
  late final Uri _baseUri;

  /// Golden name -> the redacted body captured from the live route.
  final Map<String, Object?> captured = <String, Object?>{};

  Future<void> start() async {
    tempDir = Directory.systemTemp.createTempSync(_tempPrefix);
    config = ServerConfig.fromEnvironment(
      environment: {
        'DATA_DIR': tempDir.path,
        'IMPORT_DIR': '${tempDir.path}/import',
        'LOG_LEVEL': 'ERROR',
      },
    );
    configureLogging(config);
    Directory(config.libraryDir).createSync(recursive: true);
    Directory(config.importDir).createSync(recursive: true);
    db = SaltDatabase.open(config.dbPath);
    runtime = AuthRuntime();
    // 168367 ("Pork, cured, ham, rump, bone-in…", the fresh-ham row of the
    // rules golden) is in no sweep snapshot: the golden pins it as a
    // superseded record — its detail 404s, the search hit stands in, and the
    // basis says no edible yield was read.
    fdc = FixtureProvider(superseded: {168367});

    final pipeline = buildAppMiddleware(
      _dispatch,
      config: config,
      database: db,
      authRuntime: runtime,
      nutritionProvider: fdc,
      // maxRequests: 0 disables the search limiter, so the `?q=` capture
      // cannot turn into a 429 that would pin the wrong body.
      searchRateLimiter: RequestRateLimiter(maxRequests: 0),
      searchService: () => InlineSearchService(db),
      logStore: LogStore(directory: config.logDir),
    );
    _server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
    _baseUri = Uri.parse('http://127.0.0.1:${_server.port}');
  }

  Future<void> stop() async {
    await _server.close(force: true);
    db.dispose();
    tempDir.deleteSync(recursive: true);
  }

  Map<String, String> auth(String token, {bool csrf = false}) => {
    'Authorization': 'Bearer $token',
    if (csrf) ..._csrf,
  };

  Future<(int, String)> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? jsonBody,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, _baseUri.resolve(path));
      headers.forEach(request.headers.set);
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      }
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      return (response.statusCode, body);
    } finally {
      client.close();
    }
  }

  /// Sends a request whose body is not a golden and asserts it succeeded.
  Future<void> expectOk(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? jsonBody,
  }) async {
    final (status, body) = await send(
      method,
      path,
      headers: headers,
      jsonBody: jsonBody,
    );
    expect(status, HttpStatus.ok, reason: '$method $path -> $body');
  }

  /// Sends the request, asserts it succeeded, and records the response body
  /// under [golden] with volatile values redacted.
  Future<Map<String, dynamic>> capture(
    String golden,
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? jsonBody,
  }) async {
    final (status, body) = await send(
      method,
      path,
      headers: headers,
      jsonBody: jsonBody,
    );
    expect(status, HttpStatus.ok, reason: '$method $path -> $body');
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    captured[golden] = redactContractVolatiles(decoded);
    return decoded;
  }

  Future<String> login(String username, String password) async {
    final (status, body) = await send(
      'POST',
      '/api/v1/auth/login',
      jsonBody: {'username': username, 'password': password},
    );
    expect(status, HttpStatus.ok, reason: body);
    return (jsonDecode(body) as Map<String, dynamic>)['token']! as String;
  }

  /// Creates the admin account every capture signs in as.
  Future<void> seedAdmin() async {
    db.createUser(
      username: 'admin',
      passwordHash: await runtime.hasher.hash(_adminPassword),
      role: 'admin',
    );
  }

  /// Seeds the admin, captures the two admin auth bodies, and returns a
  /// session token for it.
  Future<String> seedAdminAndCaptureAuth() async {
    await seedAdmin();
    await capture(
      'auth_login_admin',
      'POST',
      '/api/v1/auth/login',
      jsonBody: {
        'username': 'admin',
        'password': _adminPassword,
        'remember': true,
      },
    );
    final session = await login('admin', _adminPassword);
    await capture(
      'auth_me_admin',
      'GET',
      '/api/v1/auth/me',
      headers: auth(session),
    );
    return session;
  }

  /// Creates a member through the real endpoint and captures the three
  /// bodies of a forced-password-change sign-in.
  Future<void> captureMustChangeAccount(String adminSession) async {
    final (status, body) = await send(
      'POST',
      '/api/v1/users',
      headers: auth(adminSession, csrf: true),
      jsonBody: {'username': _tempUsername, 'role': 'member'},
    );
    expect(status, HttpStatus.ok, reason: body);
    // Not a golden: the body holds a one-time temp password.
    final tempPassword =
        (jsonDecode(body) as Map<String, dynamic>)['temp_password']! as String;
    await capture(
      'auth_login_must_change',
      'POST',
      '/api/v1/auth/login',
      jsonBody: {'username': _tempUsername, 'password': tempPassword},
    );
    final session = await login(_tempUsername, tempPassword);
    await capture(
      'auth_me_must_change',
      'GET',
      '/api/v1/auth/me',
      headers: auth(session),
    );
    await capture(
      'auth_change_password',
      'POST',
      '/api/v1/auth/change_password',
      headers: auth(session, csrf: true),
      jsonBody: {'new_password': _newPassword},
    );
  }

  /// Starts an import of [relativePath] and waits for it to finish,
  /// returning the job id.
  Future<int> runImport(String relativePath, String adminSession) async {
    final (status, body) = await send(
      'POST',
      '/api/v1/import',
      headers: auth(adminSession, csrf: true),
      jsonBody: {'path': relativePath},
    );
    expect(status, HttpStatus.accepted, reason: body);
    final jobId = ((jsonDecode(body) as Map<String, dynamic>)['job_id']! as num)
        .toInt();
    await awaitJob('/api/v1/import/jobs/$jobId', auth(adminSession));
    return jobId;
  }

  /// Polls [path] until its `status` leaves `running`.
  Future<void> awaitJob(String path, Map<String, String> headers) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final (status, body) = await send('GET', path, headers: headers);
      expect(status, HttpStatus.ok, reason: body);
      final job = jsonDecode(body) as Map<String, dynamic>;
      if (job['status'] != 'running') {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('job at $path never left "running"');
  }
}

/// Routes the request to the same `onRequest` the dart_frog build would.
FutureOr<Response> _dispatch(RequestContext context) {
  final path = context.request.uri.path;
  switch (path) {
    case '/api/v1/auth/login':
      return login_route.onRequest(context);
    case '/api/v1/auth/me':
      return me_route.onRequest(context);
    case '/api/v1/auth/change_password':
      return change_password_route.onRequest(context);
    case '/api/v1/users':
      return users_route.onRequest(context);
    case '/api/v1/tags':
      return tags_route.onRequest(context);
    case '/api/v1/recipes':
      return recipes_route.onRequest(context);
    case '/api/v1/admin/nutrition_review':
      return review_route.onRequest(context);
    case '/api/v1/library':
      return library_route.onRequest(context);
    case '/api/v1/library/rescan':
      return rescan_route.onRequest(context);
    case '/api/v1/import':
      return import_route.onRequest(context);
    case '/api/v1/import/candidates':
      return candidates_route.onRequest(context);
    case '/api/v1/nutrition/bulk/counts':
      return bulk_counts_route.onRequest(context);
  }
  // The one two-parameter route: a reviewer's decision on one line.
  final linePick = RegExp(
    r'^/api/v1/recipes/([^/]+)/nutrition/matches/([^/]+)$',
  ).firstMatch(path);
  if (linePick != null) {
    return match_pos_route.onRequest(
      context,
      linePick.group(1)!,
      linePick.group(2)!,
    );
  }
  for (final (pattern, handler)
      in <(RegExp, FutureOr<Response> Function(RequestContext, String))>[
        (
          RegExp(r'^/api/v1/recipes/([^/]+)/nutrition/compute$'),
          compute_route.onRequest,
        ),
        (
          RegExp(r'^/api/v1/recipes/([^/]+)/nutrition/matches$'),
          matches_route.onRequest,
        ),
        (
          RegExp(r'^/api/v1/recipes/([^/]+)/nutrition$'),
          nutrition_route.onRequest,
        ),
        (
          RegExp(r'^/api/v1/recipes/([^/]+)/favorite$'),
          favorite_route.onRequest,
        ),
        (RegExp(r'^/api/v1/recipes/([^/]+)/note$'), note_route.onRequest),
        (RegExp(r'^/api/v1/recipes/([^/]+)$'), recipe_route.onRequest),
        (RegExp(r'^/api/v1/tags/([^/]+)/style$'), tag_style_route.onRequest),
        (RegExp(r'^/api/v1/import/jobs/([^/]+)$'), import_job_route.onRequest),
        (
          RegExp(r'^/api/v1/nutrition/jobs/([^/]+)$'),
          nutrition_job_route.onRequest,
        ),
      ]) {
    final match = pattern.firstMatch(path);
    if (match != null) {
      return handler(context, match.group(1)!);
    }
  }
  return Response(statusCode: HttpStatus.notFound, body: 'no route');
}
