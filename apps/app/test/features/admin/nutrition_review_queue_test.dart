import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/admin/nutrition_review_cubit.dart';
import 'package:salt_app/features/admin/nutrition_review_queue.dart';
import 'package:salt_app/features/nutrition/apply_to_all_strip.dart';

/// Serves both endpoints the queue needs: the cross-recipe review list, and one
/// recipe's per-line matches (fetched when a row is selected, so the fix panel
/// gets candidates).
class _Adapter implements HttpClientAdapter {
  _Adapter({this.failOverride = false, this.reviewBody, this.others = 0});

  /// The `others`/`others_lines` the selected recipe's rows carry: above 0,
  /// a decision raises the apply-to-all offer, and an `apply_to_all` PUT
  /// answers with an `applied` receipt sized by it.
  final int others;

  /// Where the Grand Marnier line stands in the rows answered from now on.
  /// Set to model a save meanwhile — synthesized, the stated exception: []
  /// removed it; two positions, neither 5, made twins of it.
  List<int> positions = const [5];

  /// Other lines of the recipe in the rows answered from now on — a save
  /// meanwhile moved them (the same stated exception).
  List<Map<String, dynamic>> extraRows = const [];

  /// When true, the next apply-to-all PUT is refused 409 `line_moved` (a
  /// save meanwhile), as the server answers a moved line.
  bool moveOnApply = false;

  /// A prepared review body, for the row/header cases — the default below is
  /// the two-line queue the fix-flow tests work against.
  final Map<String, dynamic>? reviewBody;

  /// When true, every override PUT fails with a 422 envelope — the network
  /// blip / budget-drained case the queue once silently advanced past
  /// (review B5).
  final bool failOverride;

  /// How many times the cross-recipe review list was (re)fetched —
  /// completeFix() reloads it, so this count observes queue advancement.
  int reviewFetches = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (failOverride &&
        options.method == 'PUT' &&
        path.contains('/nutrition/matches/')) {
      return ResponseBody.fromString(
        jsonEncode({
          'error': {
            'code': 'validation',
            'message':
                'The FoodData Central request budget for this hour '
                'is used up.',
          },
        }),
        422,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    Object? body;
    if (path.contains('/admin/nutrition_review')) {
      reviewFetches += 1;
      body =
          reviewBody ??
          {
            'total': 2,
            'groups': 2,
            'buckets': [
              {'id': 'no_match', 'label': 'No match', 'count': 1, 'groups': 1},
              {'id': 'no_grams', 'label': 'No grams', 'count': 0, 'groups': 0},
              {
                'id': 'check',
                'label': 'Low confidence',
                'count': 1,
                'groups': 1,
              },
              {'id': 'skipped', 'label': 'Skipped', 'count': 0, 'groups': 0},
            ],
            'items': [
              {
                'recipe': {
                  'id': 'tatin',
                  'slug': 'tatin',
                  'title': 'Tarte Tatin',
                },
                'position': 5,
                'raw': '2 tablespoons Grand Marnier',
                'bucket': 'check',
                'match': {
                  'fdc_id': 100,
                  'description': 'Candies, NESTLE, 100 GRAND Bar',
                  'data_type': 'SR Legacy',
                  'confidence': 0.41,
                  'grams': 28,
                  'gram_source': 'density',
                  'status': 'auto',
                },
              },
              {
                'recipe': {
                  'id': 'soup',
                  'slug': 'soup',
                  'title': 'Chicken Soup',
                },
                'position': 7,
                'raw': '2 bay leaves',
                'bucket': 'no_match',
                'match': null,
              },
            ],
            'page': 1,
            'limit': 50,
          };
    } else if (path.contains('/nutrition/matches')) {
      var applyToAll = false;
      if (options.method == 'PUT') {
        final bytes = <int>[];
        await for (final chunk in requestStream!) {
          bytes.addAll(chunk);
        }
        final sent = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        applyToAll = sent['apply_to_all'] == true;
        if (applyToAll && moveOnApply) {
          moveOnApply = false;
          return ResponseBody.fromString(
            jsonEncode({
              'error': {
                'code': 'line_moved',
                'message': 'The line has changed since; refresh and retry.',
              },
            }),
            409,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
      }
      // The selected recipe's full match list (with a real alternative so the
      // fix panel can offer a re-pick).
      body = {
        if (applyToAll)
          'applied': {
            'recipes': others,
            'lines': others,
            'failed': 0,
            'completed': 0,
            'completed_recipes': <String>[],
            'moved': 0,
            'decided': 0,
            'gone': 0,
            'failed_lines': 0,
          },
        'items': [
          for (final at in positions)
            {
              'others': others,
              'others_lines': others,
              'position': at,
              'raw': '2 tablespoons Grand Marnier',
              'match': {
                'fdc_id': 100,
                'description': 'Candies, NESTLE, 100 GRAND Bar',
                'data_type': 'SR Legacy',
                'confidence': 0.41,
                'grams': 28,
                'gram_source': 'density',
                'status': 'auto',
              },
              'candidates': [
                {
                  'fdc_id': 200,
                  'description': 'Alcoholic beverage, liqueur, coffee',
                  'data_type': 'SR Legacy',
                  'confidence': 0.58,
                },
              ],
            },
          ...extraRows,
        ],
      };
    } else {
      body = {'status': 'none'};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Future<_Adapter> pumpQueue(
    WidgetTester tester, {
    bool failOverride = false,
    Map<String, dynamic>? reviewBody,
    int others = 0,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _Adapter(
      failOverride: failOverride,
      reviewBody: reviewBody,
      others: others,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final recipeRepo = RecipeRepository(dio: dio);
    final nutritionRepo = NutritionRepository(dio);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: recipeRepo),
          RepositoryProvider.value(value: nutritionRepo),
        ],
        child: MaterialApp(
          theme: buildMaterialTheme(buildForuiTheme()),
          builder: (context, child) =>
              FTheme(data: buildForuiTheme(), child: child!),
          home: BlocProvider(
            create: (_) => NutritionReviewCubit(recipeRepo)..load(),
            child: const Scaffold(body: NutritionReviewQueue()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return adapter;
  }

  /// A group item, as the server emits it in `group=item`: today's line item
  /// flattened (the example line at top level) plus the group fields. Every
  /// recipe, line, food and count here comes from the approved mockup.
  Map<String, dynamic> groupItem({
    required String slug,
    required String title,
    required int position,
    required String raw,
    required String bucket,
    required String itemKey,
    String? item,
    required int lines,
    required int recipes,
    bool decided = false,
    double? gramsMin,
    double? gramsMax,
    int gramsMissing = 0,
    String? food,
    double confidence = 0.495,
  }) => {
    'recipe': {'id': slug, 'slug': slug, 'title': title},
    'position': position,
    'raw': raw,
    'bucket': bucket,
    'match': food == null
        ? null
        : {
            'fdc_id': 1,
            'description': food,
            'data_type': 'SR Legacy',
            'confidence': confidence,
            'grams': gramsMin,
            'gram_source': 'piece',
            'status': 'auto',
          },
    'item_key': itemKey,
    'item': item,
    'lines': lines,
    'recipes': recipes,
    'decided': decided,
    'grams': {'min': gramsMin, 'max': gramsMax, 'missing': gramsMissing},
  };

  testWidgets('renders the worst-first queue and selects the first line', (
    tester,
  ) async {
    await pumpQueue(tester);
    // Both flagged rows are present, across two recipes.
    expect(find.text('2 tablespoons Grand Marnier'), findsWidgets);
    expect(find.text('2 bay leaves'), findsOneWidget);
    // Bucket pills from the row buckets.
    expect(find.text('check match'), findsOneWidget);
    expect(find.text('no match'), findsOneWidget);
    // Filter chips carry the whole-library counts.
    expect(find.text('Need attention'), findsOneWidget);
  });

  testWidgets('selecting a line loads its recipe matches into the fix panel', (
    tester,
  ) async {
    await pumpQueue(tester);
    // The first (worst) line is auto-selected, so its fix panel is already up.
    expect(find.text('Change the match & set the amount'), findsOneWidget);
    // The current match and the real alternative both appear in the panel.
    expect(find.text('Candies, NESTLE, 100 GRAND Bar'), findsWidgets);
    expect(find.text('Alcoholic beverage, liqueur, coffee'), findsOneWidget);
    // A "check" line offers Confirm-as-is alongside Skip.
    expect(find.text('Confirm as-is'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    // The persistent detail pane hides the fix panel's Cancel button.
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('a failed override shows its error and does NOT advance the '
      'queue (review B5)', (tester) async {
    final adapter = await pumpQueue(tester, failOverride: true);
    final fetchesBefore = adapter.reviewFetches;

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // The real, actionable message is on screen — not silence.
    expect(
      find.textContaining('FoodData Central request budget'),
      findsOneWidget,
    );
    // The selection stayed on the line that was never fixed, and the queue
    // was not reloaded (completeFix() must not fire on failure).
    expect(find.text('2 tablespoons Grand Marnier'), findsWidgets);
    expect(adapter.reviewFetches, fetchesBefore);
  });

  testWidgets('a successful override completes the fix and reloads the queue', (
    tester,
  ) async {
    final adapter = await pumpQueue(tester);
    final fetchesBefore = adapter.reviewFetches;

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(adapter.reviewFetches, fetchesBefore + 1);
  });

  // Run 053 O17: a save removes the acted-on line while the apply runs, so
  // the answer has no row reading it — the pane has no line to show, but
  // the receipt still stands there with its counts and why, and its Dismiss
  // advances the queue as any receipt's does.
  // Run 055 S13: the pane's "Not now" is the OFFER's (dismissOffer) — wired
  // to dismissReceipt it would do nothing here (no receipt is open).
  testWidgets('S13: "Not now" in the queue pane drops the offer and advances', (
    tester,
  ) async {
    final adapter = await pumpQueue(tester, others: 3);
    await tester.tap(find.text('Confirm as-is'));
    await tester.pumpAndSettle();
    expect(find.text('Apply to 3 lines'), findsOneWidget);
    final fetchesBefore = adapter.reviewFetches;
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Apply to 3 lines'), findsNothing);
    expect(adapter.reviewFetches, fetchesBefore + 1);
  });

  testWidgets('O17: the receipt of an apply whose line a save removed shows '
      'in the pane, with the line-gone message, and Dismiss advances', (
    tester,
  ) async {
    final adapter = await pumpQueue(tester, others: 3);
    await tester.tap(find.text('Confirm as-is'));
    await tester.pumpAndSettle();
    expect(find.text('Apply to 3 lines'), findsOneWidget);
    final fetchesBefore = adapter.reviewFetches;
    adapter.positions = const [];
    await tester.tap(find.text('Apply to 3 lines'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Applied to 3 recipes', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(ApplyToAllStrip.lineChangedNote, findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('edited or removed since the queue was built'),
      findsOneWidget,
    );
    expect(adapter.reviewFetches, fetchesBefore, reason: 'not yet advanced');
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(adapter.reviewFetches, fetchesBefore + 1);
  });

  // O17's other way to lose the line: the answer has it twice, neither at
  // the position acted on — which twin it was is unknowable, so the receipt
  // stands unanchored, and the pane (on the nearest twin) still shows it.
  testWidgets('O17: a receipt whose line became twins neither at its '
      'position still shows in the pane, unanchored', (tester) async {
    final adapter = await pumpQueue(tester, others: 3);
    await tester.tap(find.text('Confirm as-is'));
    await tester.pumpAndSettle();
    adapter.positions = const [3, 4];
    await tester.tap(find.text('Apply to 3 lines'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Applied to 3 recipes', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(ApplyToAllStrip.lineChangedNote, findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Change the match & set the amount'), findsOneWidget);
  });

  // Run 054 S9/O11: the save that removed the line moved Tarte Tatin's
  // cream line (a No grams row: food, no grams) into its old position 5.
  // The gone line waits on nothing — Dismiss advances; the row now at 5 is
  // another line and never vetoes it (Run 051 A2's rule, in the advance).
  testWidgets('S9: Dismiss on a gone line advances although a No grams line '
      'now sits at its old position', (tester) async {
    final adapter = await pumpQueue(tester, others: 3);
    await tester.tap(find.text('Confirm as-is'));
    await tester.pumpAndSettle();
    final fetchesBefore = adapter.reviewFetches;
    adapter.positions = const [];
    adapter.extraRows = [
      {
        'others': 0,
        'others_lines': 0,
        'position': 5,
        'raw': '¼ cup heavy cream',
        'match': {
          'fdc_id': 170859,
          'description': 'Cream, fluid, heavy whipping',
          'data_type': 'SR Legacy',
          'confidence': 0.9,
          'grams': null,
          'gram_source': null,
          'status': 'auto',
        },
        'candidates': <Object>[],
      },
    ];
    await tester.tap(find.text('Apply to 3 lines'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('edited or removed since the queue was built'),
      findsOneWidget,
    );
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(adapter.reviewFetches, fetchesBefore + 1, reason: 'advanced');
  });

  // Run 054 O12: the Confirm's answer has the line moved to 7 (the offer
  // stands there); a second save adds its twin at the queued 5, so the
  // apply's receipt anchors at 7 while the pane shows twin 5. The pane's
  // cubit holds this one line's decisions: the receipt shows, and its
  // Dismiss advances.
  testWidgets('O12: a receipt anchored on the other twin shows in the pane '
      'and its Dismiss advances', (tester) async {
    final adapter = await pumpQueue(tester, others: 3);
    adapter.positions = const [7];
    await tester.tap(find.text('Confirm as-is'));
    await tester.pumpAndSettle();
    expect(find.text('Apply to 3 lines'), findsOneWidget);
    final fetchesBefore = adapter.reviewFetches;
    adapter.positions = const [5, 7];
    await tester.tap(find.text('Apply to 3 lines'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Applied to 3 recipes', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(ApplyToAllStrip.lineChangedNote, findRichText: true),
      findsNothing,
      reason: 'anchored, at 7',
    );
    expect(adapter.reviewFetches, fetchesBefore);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(adapter.reviewFetches, fetchesBefore + 1);
  });

  // O12's class on the offer: a refused apply (line_moved) reloads the
  // rows, and a twin added at the queued 5 meanwhile leaves the offer at 7
  // while the pane shows twin 5 — the offer still shows, so the pane can
  // retry or decline it (hidden, it held the pane with nothing to act on).
  testWidgets('O12: an offer re-located onto the other twin still shows in '
      'the pane', (tester) async {
    final adapter = await pumpQueue(tester, others: 3);
    adapter.positions = const [7];
    await tester.tap(find.text('Confirm as-is'));
    await tester.pumpAndSettle();
    adapter
      ..positions = const [5, 7]
      ..moveOnApply = true;
    await tester.tap(find.text('Apply to 3 lines'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This line moved since'), findsOneWidget);
    expect(find.text('Apply to 3 lines'), findsOneWidget);
  });

  // Run 054 S14: a group's receipt under the line-gone message still
  // reconciles against the group's promise by recipe id. Two real Grand
  // Marnier recipes stand in the promise; the adapter's receipt completes
  // none of them.
  testWidgets('S14: the gone-line receipt of a group reconciles against its '
      'promise', (tester) async {
    final line = {
      'recipe': {'id': 'tatin', 'slug': 'tatin', 'title': 'Tarte Tatin'},
      'position': 5,
      'raw': '2 tablespoons Grand Marnier',
      'bucket': 'check',
      'match': {
        'fdc_id': 100,
        'description': 'Candies, NESTLE, 100 GRAND Bar',
        'data_type': 'SR Legacy',
        'confidence': 0.41,
        'grams': 28,
        'gram_source': 'density',
        'status': 'auto',
      },
      'item_key': 'grand marnier',
      'item': 'Grand Marnier',
      'lines': 3,
      'recipes': 3,
      'decided': false,
      'grams': {'min': 9, 'max': 28, 'missing': 0},
      'finishes': 2,
      'finishes_recipes': [
        {
          'id':
              'atk-tv-2023-0905-chocolate-volcano-cakes-with-espresso-ice-'
              'cream',
          'title': 'Chocolate Volcano Cakes with Espresso Ice Cream',
        },
        {
          'id': 'atk-tv-2023-0936-grand-marnier-souffle',
          'title': 'Grand Marnier Soufflé',
        },
      ],
      'last_open': 0,
    };
    final adapter = await pumpQueue(
      tester,
      others: 3,
      reviewBody: {
        'total': 3,
        'groups': 1,
        'buckets': [
          {'id': 'no_match', 'label': 'No match', 'count': 0, 'groups': 0},
          {'id': 'no_grams', 'label': 'No grams', 'count': 0, 'groups': 0},
          {'id': 'check', 'label': 'Low confidence', 'count': 3, 'groups': 1},
          {'id': 'skipped', 'label': 'Skipped', 'count': 0, 'groups': 0},
        ],
        'items': [line],
        'page': 1,
        'limit': 50,
      },
    );
    await tester.tap(find.text('Confirm as-is'));
    await tester.pumpAndSettle();
    adapter.positions = const [];
    await tester.tap(find.textContaining('Apply to '));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('edited or removed since the queue was built'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Chocolate Volcano Cakes with Espresso Ice Cream and Grand Marnier '
        'Soufflé were not completed by this apply',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  /// The Low-confidence bucket, grouped: the jalapeño group the mockup's
  /// walkthrough clears, plus one single-line group above it.
  Map<String, dynamic> groupedBody() => {
    'total': 6,
    'groups': 2,
    'buckets': [
      {'id': 'no_match', 'label': 'No match', 'count': 0, 'groups': 0},
      {'id': 'no_grams', 'label': 'No grams', 'count': 0, 'groups': 0},
      {'id': 'check', 'label': 'Low confidence', 'count': 6, 'groups': 2},
      {'id': 'skipped', 'label': 'Skipped', 'count': 0, 'groups': 0},
    ],
    'items': [
      groupItem(
        slug: 'crispy-salt-and-pepper-shrimp',
        title: 'Crispy Salt and Pepper Shrimp',
        position: 4,
        raw: '2 teaspoons Sichuan peppercorns',
        bucket: 'check',
        itemKey: 'sichuan peppercorn',
        item: 'Sichuan peppercorns',
        lines: 1,
        recipes: 1,
        confidence: 0.03,
        food: 'Salad dressing, peppercorn dressing, commercial, regular',
      ),
      groupItem(
        slug: 'cheesy-nachos',
        title: 'Cheesy Nachos with Guacamole and Salsa',
        position: 2,
        raw: '2 large jalapeño chiles, sliced thin (about ¼ cup)',
        bucket: 'check',
        itemKey: 'jalapeno chile',
        item: 'jalapeño chiles',
        lines: 5,
        recipes: 5,
        gramsMin: 14,
        gramsMax: 63,
        food: 'Peppers, jalapeno, seeded, raw',
      ),
    ],
    'page': 1,
    'limit': 50,
  };

  testWidgets('a multi-line group names the ingredient, its reach and its '
      'amounts; a group of one is today\'s row', (tester) async {
    await pumpQueue(tester, reviewBody: groupedBody());

    // The group row: label, reach pill, "e.g." on the example, amount slot.
    expect(find.text('jalapeño chiles'), findsOneWidget);
    expect(find.text('5 lines · 5 recipes'), findsOneWidget);
    expect(
      find.text('e.g. 2 large jalapeño chiles, sliced thin (about ¼ cup)'),
      findsOneWidget,
    );
    expect(find.text('amounts 14–63 g, one per line'), findsOneWidget);
    expect(find.text('Peppers, jalapeno, seeded, raw'), findsWidgets);
    expect(find.text('decided'), findsNothing);

    // The single-line group is byte-for-byte the line row: recipe · line N,
    // the raw text unprefixed, and no reach pill or amount slot.
    expect(find.text('Crispy Salt and Pepper Shrimp · line 4'), findsOneWidget);
    expect(find.text('2 teaspoons Sichuan peppercorns'), findsWidgets);
    expect(find.text('1 lines · 1 recipes'), findsNothing);
    expect(find.textContaining('e.g. 2 teaspoons'), findsNothing);
  });

  testWidgets('the header counts both units and the segment switches them', (
    tester,
  ) async {
    final adapter = await pumpQueue(tester, reviewBody: groupedBody());
    expect(
      find.text(
        'Showing all flagged · 2 ingredients, 6 lines · '
        'most recipes finished first',
      ),
      findsOneWidget,
    );
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Lines'), findsOneWidget);

    final before = adapter.reviewFetches;
    await tester.tap(find.text('Lines'));
    await tester.pumpAndSettle();
    // Switching the unit refetches page 1 — the unit of paging changed.
    expect(adapter.reviewFetches, before + 1);
    // The lines view ends on the same order words (C1 open question 5).
    expect(
      find.text('Showing all flagged · 6 lines · most recipes finished first'),
      findsOneWidget,
    );
  });

  testWidgets('a decided group says so, and a weak group with no amounts '
      'warns that the confirm asks for the amount', (tester) async {
    // herbes de Provence: two lines, neither with an amount, on a food that
    // is plainly wrong — the pane the admin is heading for has no Confirm.
    await pumpQueue(
      tester,
      reviewBody: {
        ...groupedBody(),
        'items': [
          groupItem(
            slug: 'chicken-bouillabaisse',
            title: 'Chicken Bouillabaisse',
            position: 16,
            raw: '1 teaspoon herbes de Provence (optional)',
            bucket: 'check',
            itemKey: 'herbe de provence',
            item: 'herbes de Provence (optional)',
            lines: 2,
            recipes: 2,
            decided: true,
            gramsMissing: 2,
            confidence: 0.03,
            food: 'Dulce de Leche',
          ),
        ],
      },
    );
    // itemLabel() drops the parenthetical: the label is the ingredient.
    expect(find.text('herbes de Provence'), findsOneWidget);
    expect(find.text('2 lines · 2 recipes'), findsOneWidget);
    expect(find.text('decided'), findsOneWidget);
    expect(
      find.text('no amount on either line — confirm asks for the amount'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Skipped hides the segment and keeps the line-shaped empty text',
    (tester) async {
      await pumpQueue(
        tester,
        reviewBody: {
          ...groupedBody(),
          'buckets': [
            {'id': 'no_match', 'label': 'No match', 'count': 0, 'groups': 0},
            {'id': 'no_grams', 'label': 'No grams', 'count': 0, 'groups': 0},
            {'id': 'check', 'label': 'Low confidence', 'count': 6, 'groups': 2},
            {'id': 'skipped', 'label': 'Skipped', 'count': 3, 'groups': 3},
          ],
          'items': <Map<String, dynamic>>[],
        },
      );
      // A skip is per line and never travels, so there is no ingredient view.
      await tester.tap(find.text('Skipped'));
      await tester.pumpAndSettle();
      expect(find.text('Ingredients'), findsNothing);
      expect(find.text('Lines'), findsNothing);
      expect(find.text('No lines in this bucket.'), findsOneWidget);
      expect(find.text('No ingredients in this bucket.'), findsNothing);
    },
  );

  testWidgets('an empty grouped bucket says ingredients, not lines', (
    tester,
  ) async {
    await pumpQueue(
      tester,
      reviewBody: {...groupedBody(), 'items': <Map<String, dynamic>>[]},
    );
    expect(find.text('No ingredients in this bucket.'), findsOneWidget);
  });

  /// The remaining amount-slot variants, straight off the aggregate — the
  /// widget cases above cover the two that carry a warning and a range.
  NutritionReviewLine amountGroup({
    required int lines,
    required int missing,
    double? min,
    double? max,
    String bucket = 'no_grams',
    double? exampleGrams,
  }) => NutritionReviewLine(
    recipe: const NutritionReviewRecipe(id: 'x', slug: 'x', title: 'X'),
    position: 0,
    raw: 'x',
    bucket: bucket,
    // Confirm as-is is gated on the EXAMPLE line's own amount, so the row
    // carries the example's match, not the aggregate.
    match: exampleGrams == null
        ? null
        : NutritionReviewMatch(
            fdcId: 173430,
            description: 'Butter, without salt',
            dataType: 'SR Legacy',
            confidence: 0.4,
            status: 'auto',
            grams: exampleGrams,
          ),
    lines: lines,
    recipes: lines,
    gramsMin: min,
    gramsMax: max,
    gramsMissing: missing,
  );

  test('the amount aggregate reads in the group\'s own units', () {
    // makrut lime leaf: both members are 264 g.
    expect(
      groupAmountLine(
        amountGroup(lines: 2, missing: 0, min: 264, max: 264),
      )?.text,
      '264 g on both lines',
    );
    expect(
      groupAmountLine(
        amountGroup(lines: 7, missing: 0, min: 2.5, max: 2.5),
      )?.text,
      '2.5 g on all 7 lines',
    );
    // thyme: no amount anywhere, and no Confirm to lose (it is not a check).
    final none = groupAmountLine(amountGroup(lines: 4, missing: 4))!;
    expect(none.text, 'no amount on any of the 4 lines');
    expect(none.warn, isFalse);
    // Some have one, some don't.
    expect(
      groupAmountLine(
        amountGroup(lines: 7, missing: 2, min: 14, max: 63),
      )?.text,
      'amounts 14–63 g · 2 of 7 lines have no amount',
    );
    // A group of one has nothing to aggregate.
    expect(groupAmountLine(amountGroup(lines: 1, missing: 1)), isNull);
  });

  test('v22: the new medium holds are line holds in the queue, each named '
      "(0148's dredge flour, 0799's starter flour, 0129's soy sauce)", () {
    for (final (hold, raw, fdcId) in const [
      ('coating', '4 cups (20 ounces) unbleached all-purpose flour', 789890),
      ('starter_discard', '4½ cups (24¾ ounces) whole-wheat flour', 790085),
      ('partial_pour_away', '1 cup soy sauce', 2707442),
      // v25 (RULE B): 0690's sauce oil retyped as an aioli beside its frying
      // oil — synthesized, a stated exception (no corpus line is held so).
      ('ambiguous_medium', '½ cup extra-virgin olive oil', 2710180),
    ]) {
      final note = lineHoldNote(
        NutritionReviewLine(
          recipe: const NutritionReviewRecipe(id: 'x', slug: 'x', title: 'X'),
          position: 0,
          raw: raw,
          bucket: 'check',
          match: NutritionReviewMatch(
            fdcId: fdcId,
            confidence: 0.95,
            status: 'auto',
            hold: hold,
          ),
        ),
      );
      expect(
        note,
        startsWith(
          'line hold (${hold.replaceAll('_', ' ')}): decided one '
          'line at a time',
        ),
        reason: hold,
      );
    }
  });

  test('a second-food group is labelled by its key, not the first food', () {
    NutritionReviewLine group(String key, String item) => NutritionReviewLine(
      recipe: const NutritionReviewRecipe(id: 'x', slug: 'x', title: 'X'),
      position: 2,
      // Italian-Style Grilled Chicken (0423).
      raw: '1 teaspoon grated lemon zest plus 2 tablespoons juice',
      bucket: 'check',
      itemKey: key,
      item: item,
      lines: 49,
      recipes: 48,
    );
    expect(
      groupLabel(group('lemon zest plus juice', 'grated lemon zest')),
      'lemon zest plus juice',
    );
    // Any other key keeps the example's tidied item.
    expect(
      groupLabel(group('lemon zest', 'grated lemon zest')),
      isNot(contains('plus')),
    );
  });

  test('the Confirm warning follows the EXAMPLE line, not the aggregate', () {
    // The unsalted-butter group: the tarte's amount-less line is the example
    // (it is the lower-confidence member), the Bundt cake's carries its
    // 170 g. The pane opens on the example, so Confirm as-is is gone even
    // though the group has amounts — the aggregate alone never knew that.
    final example = amountGroup(
      lines: 2,
      missing: 1,
      min: 170.16649439999998,
      max: 170.16649439999998,
      bucket: 'check',
    );
    final warned = groupAmountLine(example)!;
    expect(
      warned.text,
      'amounts 170–170 g · 1 of 2 lines have no amount — '
      'confirm asks for the amount',
    );
    expect(warned.warn, isTrue);

    // The same group with the 170 g line as its example: the button is
    // there, so there is nothing to warn about.
    final fine = groupAmountLine(
      amountGroup(
        lines: 2,
        missing: 1,
        min: 170.16649439999998,
        max: 170.16649439999998,
        bucket: 'check',
        exampleGrams: 170.16649439999998,
      ),
    )!;
    expect(fine.text, 'amounts 170–170 g · 1 of 2 lines have no amount');
    expect(fine.warn, isFalse);

    // Outside `check` an amount-less example has no Confirm to lose.
    final counted = groupAmountLine(
      amountGroup(lines: 2, missing: 1, min: 170.2, max: 170.2),
    )!;
    expect(counted.warn, isFalse);
  });
}
