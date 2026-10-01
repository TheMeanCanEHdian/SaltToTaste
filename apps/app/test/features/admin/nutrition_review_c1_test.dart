import 'dart:convert';
import 'dart:io';
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
import 'package:salt_app/features/nutrition/match_fix_panel.dart'
    show confirmsWithoutAmount, heldSkipLabel;
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

/// Sweep-snapshot-11 groups as the grouped queue serves them (the example
/// line flattened, plus the group fields and `finishes`).
Map<String, dynamic> _group({
  String? id,
  required String slug,
  required String title,
  required int position,
  required String raw,
  required String bucket,
  required String itemKey,
  required String item,
  required int lines,
  required int finishes,
  required int fdcId,
  required String description,
  required double confidence,
  double? grams,
  String? gramSource,
  String? hold,
  int missing = 0,
  int lastOpen = 0,
  List<List<String>> finishesRecipes = const [],
}) => {
  'recipe': {'id': id ?? 'atk-$slug', 'slug': slug, 'title': title},
  'position': position,
  'raw': raw,
  'bucket': bucket,
  'match': {
    'fdc_id': fdcId,
    'description': description,
    'data_type': 'SR Legacy',
    'confidence': confidence,
    'grams': grams,
    'gram_source': gramSource,
    'status': 'auto',
    'hold': hold,
  },
  'item_key': itemKey,
  'item': item,
  'lines': lines,
  'recipes': lines,
  'decided': false,
  'grams': {'min': grams, 'max': grams, 'missing': missing},
  'finishes': finishes,
  'finishes_recipes': [
    for (final r in finishesRecipes) {'id': r[0], 'title': r[1]},
  ],
  'last_open': lastOpen,
};

final _almond = _group(
  slug: 'almond-biscotti',
  title: 'Almond Biscotti',
  position: 7,
  raw: '1½ teaspoons almond extract',
  bucket: 'check',
  itemKey: 'almond extract',
  item: 'almond extract',
  lines: 9,
  finishes: 6,
  fdcId: 173471,
  description: 'Vanilla extract',
  confidence: 0.475,
  grams: 6.3,
  gramSource: 'portion',
  lastOpen: 6,
  finishesRecipes: [
    ['atk-tv-2023-0856-angel-food-cake', 'Angel Food Cake'],
    ['atk-tv-2023-0870-best-almond-cake', 'Best Almond Cake'],
    [
      'atk-tv-2023-0883-classic-white-layer-cake-with-butter-frosting-and-'
          'raspberry-almond-filling',
      'Classic White Layer Cake with Butter Frosting and Raspberry-Almond '
          'Filling',
    ],
    [
      'atk-tv-2023-1116-cranberry-curd-tart-with-almond-crust',
      'Cranberry Curd Tart with Almond Crust',
    ],
    [
      'atk-tv-2023-0832-easy-holiday-sugar-cookies',
      'Easy Holiday Sugar Cookies',
    ],
    [
      'atk-tv-2023-0032-spanish-chilled-almond-and-garlic-soup',
      'Spanish Chilled Almond and Garlic Soup',
    ],
  ],
);
final _sugar = _group(
  id: 'atk-tv-2023-0134-perfect-roast-chicken',
  slug: 'perfect-roast-chicken',
  title: 'Perfect Roast Chicken',
  position: 1,
  raw: '½ cup sugar',
  bucket: 'check',
  itemKey: 'sugar',
  item: 'sugar',
  lines: 1,
  finishes: 1,
  fdcId: 746784,
  description: 'Sugars, granulated',
  confidence: 0.95,
  grams: 94,
  gramSource: 'portion',
  hold: 'discarded_medium',
  lastOpen: 1,
  finishesRecipes: [
    ['atk-tv-2023-0134-perfect-roast-chicken', 'Perfect Roast Chicken'],
  ],
);
// Another brine sugar, whose recipe waits on more: it finishes nothing.
final _sugarOpen = _group(
  slug: 'high-roast-butterflied-chicken-with-potatoes',
  title: 'High-Roast Butterflied Chicken with Potatoes',
  position: 1,
  raw: '½ cup sugar',
  bucket: 'check',
  itemKey: 'sugar',
  item: 'sugar',
  lines: 1,
  finishes: 0,
  fdcId: 746784,
  description: 'Sugars, granulated',
  confidence: 0.95,
  grams: 94,
  gramSource: 'portion',
  hold: 'discarded_medium',
);
// Pecans: every line without grams; the last open line of six recipes,
// only the example's (Best Baked Apples) finished by one decision.
final _pecan = _group(
  id: 'atk-tv-2023-0953-best-baked-apples',
  slug: 'best-baked-apples',
  title: 'Best Baked Apples',
  position: 3,
  raw: '⅓ cup coarsely chopped pecans, toasted',
  bucket: 'no_grams',
  itemKey: 'pecan',
  item: 'coarsely chopped pecans',
  lines: 8,
  finishes: 1,
  fdcId: 2346395,
  description: 'Nuts, pecans, halves, raw',
  confidence: 0.92,
  missing: 8,
  lastOpen: 6,
  finishesRecipes: [
    ['atk-tv-2023-0953-best-baked-apples', 'Best Baked Apples'],
  ],
);
Map<String, dynamic> _ginger({
  String slug = 'chana-masala',
  String title = 'Chana Masala',
  int position = 2,
  String raw = '1 (1½-inch) piece ginger, peeled and chopped coarse',
  int lines = 14,
}) => _group(
  slug: slug,
  title: title,
  position: position,
  raw: raw,
  bucket: 'no_grams',
  itemKey: 'ginger',
  item: '(1 1/2-inch) ginger',
  lines: lines,
  finishes: 0,
  fdcId: 169231,
  description: 'Ginger root, raw',
  confidence: 0.887,
  missing: lines,
  lastOpen: 2,
);
final _garam = _group(
  slug: 'chana-masala',
  title: 'Chana Masala',
  position: 12,
  raw: '1½ teaspoons garam masala',
  bucket: 'check',
  itemKey: 'garam masala',
  item: 'garam masala',
  lines: 6,
  finishes: 0,
  fdcId: 171181,
  description: 'SMART SOUP, Indian Bean Masala',
  confidence: 0.015,
  missing: 6,
);

// Baguette on snapshot 11: the example (Cheesy Garlic Bread) is its
// recipe's only open line, so its confirm finishes that recipe itself and
// the apply finishes the two onion soups.
final _baguette = _group(
  id: 'atk-tv-2023-0401-cheesy-garlic-bread',
  slug: 'cheesy-garlic-bread',
  title: 'Cheesy Garlic Bread',
  position: 5,
  raw: '1 (18- to 20-inch) baguette, sliced in half horizontally',
  bucket: 'check',
  itemKey: 'baguette',
  item: '(18- to 20-inch) baguette',
  lines: 7,
  finishes: 3,
  fdcId: 2707610,
  description: 'Bread, French or Vienna',
  confidence: 0,
  grams: 64,
  gramSource: 'piece',
  missing: 1,
  lastOpen: 4,
  finishesRecipes: [
    ['atk-tv-2023-0401-cheesy-garlic-bread', 'Cheesy Garlic Bread'],
    ['atk-tv-2023-0432-classic-french-onion-soup', 'Classic French Onion Soup'],
    [
      'atk-tv-2023-0433-streamlined-french-onion-soup',
      'Streamlined French Onion Soup',
    ],
  ],
);

// Chana Masala's lines as its matches body serves them (snapshot 11): the
// ginger with no grams and its record's cached portions, none a piece —
// the 13 other ginger lines sit on the same food at 0.887, so `others` is
// 0 — and the garam masala on a wrong food at 1.5%, before and after a
// plain confirm USDA could not convert.
const Map<String, dynamic> _gingerLine = {
  'position': 2,
  'raw': '1 (1½-inch) piece ginger, peeled and chopped coarse',
  'item': '(1 1/2-inch) ginger',
  'line_amount': '1 piece',
  'kcal_per_100g': 80.0,
  'others': 0,
  'others_lines': 0,
  'portions': [
    {'amount': 5.0, 'description': 'slices (1" dia)', 'grams': 11.0},
    {'amount': 0.25, 'description': 'cup slices (1" dia)', 'grams': 24.0},
    {'amount': 1.0, 'description': 'tsp', 'grams': 2.0},
  ],
  'match': {
    'fdc_id': 169231,
    'description': 'Ginger root, raw',
    'data_type': 'SR Legacy',
    'confidence': 0.887,
    'grams': null,
    'gram_source': null,
    'status': 'auto',
  },
  'candidates': <Object>[],
};
const Map<String, dynamic> _garamLine = {
  'position': 12,
  'raw': '1½ teaspoons garam masala',
  'item': 'garam masala',
  'match': {
    'fdc_id': 171181,
    'description': 'SMART SOUP, Indian Bean Masala',
    'data_type': 'SR Legacy',
    'confidence': 0.014999999999999958,
    'grams': null,
    'gram_source': null,
    'status': 'auto',
  },
  'candidates': <Object>[],
};
const Map<String, dynamic> _garamConfirmedLine = {
  'position': 12,
  'raw': '1½ teaspoons garam masala',
  'item': 'garam masala',
  'match': {
    'fdc_id': 171181,
    'description': 'SMART SOUP, Indian Bean Masala',
    'data_type': 'SR Legacy',
    'confidence': 1.0,
    'grams': null,
    'gram_source': null,
    'status': 'confirmed',
  },
  'candidates': <Object>[],
};

// Beef Satay pos 8 on snapshot 11: its only open line, a key of one.
const Map<String, dynamic> _sataySauceLine = {
  'position': 8,
  'raw': '1 recipe Spicy Peanut Dipping Sauce (recipe follows)',
  'item': 'Spicy Peanut Dipping Sauce',
  'match': {
    'fdc_id': 2707546,
    'description': 'Peanut sauce',
    'data_type': 'Survey (FNDDS)',
    'confidence': 0.26500000000000007,
    'grams': null,
    'gram_source': null,
    'status': 'auto',
  },
  'candidates': <Object>[],
};
final _satay = _group(
  id: 'atk-tv-2023-0515-beef-satay',
  slug: 'beef-satay',
  title: 'Beef Satay',
  position: 8,
  raw: '1 recipe Spicy Peanut Dipping Sauce (recipe follows)',
  bucket: 'check',
  itemKey: 'spicy peanut dipping sauce',
  item: 'Spicy Peanut Dipping Sauce',
  lines: 1,
  finishes: 1,
  fdcId: 2707546,
  description: 'Peanut sauce',
  confidence: 0.26500000000000007,
  missing: 1,
  lastOpen: 1,
  finishesRecipes: [
    ['atk-tv-2023-0515-beef-satay', 'Beef Satay'],
  ],
);

// Snapshot 12's held lines (ruling 5): Classic Macaroni and Cheese's
// pasta-water salt, its "plus 1 teaspoon" eaten, and Roasted Oysters on the
// Half Shell's oysters, in the shell with no grams.
const Map<String, dynamic> _macSaltMatch = {
  'fdc_id': 173468,
  'description': 'Salt, table',
  'data_type': 'SR Legacy',
  'confidence': 1.0,
  'grams': 6.0132824,
  'gram_source': 'discarded',
  'status': 'auto',
  'hold': 'discarded_medium',
};
const Map<String, dynamic> _oysterMatch = {
  'fdc_id': 1999627,
  'description': 'Mushroom, oyster',
  'data_type': 'Foundation',
  'confidence': 0.95,
  'grams': null,
  'gram_source': null,
  'status': 'auto',
  'hold': 'in_shell',
};
Map<String, dynamic> _held(
  String id,
  String title,
  int position,
  String raw,
  Map<String, dynamic> match,
) => {
  'recipe': {
    'id': id,
    'slug': id.substring('atk-tv-2023-0000-'.length),
    'title': title,
  },
  'position': position,
  'raw': raw,
  'bucket': 'check',
  'match': match,
  'item_key': '',
  'lines': 1,
  'recipes': 1,
  'decided': false,
  'grams': {'min': match['grams'], 'max': match['grams'], 'missing': 0},
};
final _macSalt = _held(
  'atk-tv-2023-0300-classic-macaroni-and-cheese',
  'Classic Macaroni and Cheese',
  2,
  '1 tablespoon plus 1 teaspoon table salt',
  _macSaltMatch,
);
final _oysters = _held(
  'atk-tv-2023-1184-roasted-oysters-on-the-half-shell-with-mustard-butter',
  'Roasted Oysters on the Half Shell with Mustard Butter',
  3,
  '24 oysters, 2½ to 3 inches long, well scrubbed',
  _oysterMatch,
);

Map<String, dynamic> _body(List<Map<String, dynamic>> items) => {
  'total': 30,
  'groups': items.length,
  // Snapshot 11's payoff.
  'finishable': 326,
  'open_recipes': 625,
  'buckets': [
    {'id': 'no_match', 'label': 'No match', 'count': 0, 'groups': 0},
    {'id': 'no_grams', 'label': 'No grams', 'count': 14, 'groups': 1},
    {'id': 'check', 'label': 'Low confidence', 'count': 16, 'groups': 3},
    {'id': 'skipped', 'label': 'Skipped', 'count': 0, 'groups': 0},
  ],
  'items': items,
  'page': 1,
  'limit': 50,
};

/// Serves the queue from [bodies] in turn (the last repeats) and records
/// every query it was asked; any other path answers an empty match list.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.bodies, {this.failing = const {}, this.garamMovedUp = false});

  /// Chana Masala as a save since the last compute left it (Run 051 A2): a
  /// line above the garam masala deleted, so the queue's stored position 12
  /// holds no line and the garam masala sits at 11. Synthesized — a stated
  /// exception: a deletion of a real line, no new text.
  final bool garamMovedUp;

  final List<Map<String, dynamic>> bodies;
  final List<Map<String, dynamic>> queries = [];

  /// Every fix written: the PUT's path and its JSON body.
  final List<(String, Object?)> puts = [];

  /// Queue requests (by their 0-based order) answered with a 500.
  final Set<int> failing;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object body = {'items': <Object>[]};
    if (options.method == 'PUT') {
      puts.add((options.path, options.data));
    }
    if (options.path.contains('/classic-macaroni-and-cheese/nutrition/')) {
      body = {
        'items': [
          {
            'position': 2,
            'raw': '1 tablespoon plus 1 teaspoon table salt',
            'item': 'table salt',
            'match': _macSaltMatch,
            'candidates': <Object>[],
          },
        ],
      };
    } else if (options.path.contains('/roasted-oysters-on-the-half-shell')) {
      body = {
        'items': [
          {
            'position': 3,
            'raw': '24 oysters, 2½ to 3 inches long, well scrubbed',
            'item': 'oysters',
            'match': _oysterMatch,
            'candidates': <Object>[],
          },
        ],
      };
    } else if (options.path.contains('/beef-satay/nutrition/matches')) {
      // Beef Satay's only open line: a sub-recipe reference no amount
      // converts (matcher v13), so its plain confirm lands in No grams.
      body = {
        'items': [
          {
            ..._sataySauceLine,
            'match': {
              ...(_sataySauceLine['match']! as Map<String, dynamic>),
              if (options.method == 'PUT') ...{
                'confidence': 1.0,
                'status': 'confirmed',
              },
            },
          },
        ],
      };
    } else if (garamMovedUp &&
        options.path.contains('/chana-masala/nutrition/matches')) {
      final sent = options.method == 'PUT' ? options.data as Map? : null;
      final garam = sent?['confirmed'] == true
          ? _garamConfirmedLine
          : sent?['skipped'] == true
          ? {
              ..._garamLine,
              'match': {
                ...(_garamLine['match']! as Map<String, dynamic>),
                'status': 'skipped',
              },
            }
          : _garamLine;
      body = {
        'items': [
          _gingerLine,
          {...garam, 'position': 11},
        ],
      };
    } else if (options.path.contains('/chana-masala/nutrition/matches')) {
      // Chana Masala's two open lines on snapshot 11; a confirm of the
      // garam masala lands it confirmed with no grams (USDA could not
      // convert), and any other write is answered with the lines as they
      // were.
      final confirmedGaram =
          options.method == 'PUT' && options.path.endsWith('/matches/12');
      body = {
        'items': [
          _gingerLine,
          confirmedGaram ? _garamConfirmedLine : _garamLine,
        ],
      };
    } else if (options.path.contains(
      '/cheesy-garlic-bread/nutrition/matches',
    )) {
      // Cheesy Garlic Bread on snapshot 11: its water is confirmed as a
      // deliberate no-match, so the baguette is its only open line.
      body = {
        'items': [
          {
            'position': 2,
            'raw': '½ teaspoon water',
            'item': 'water',
            'match': {
              'fdc_id': null,
              'description': 'Water/ice — counts as zero',
              'data_type': null,
              'confidence': 1.0,
              'grams': null,
              'gram_source': null,
              'status': 'confirmed',
            },
            'candidates': <Object>[],
          },
          {
            'position': 5,
            'raw': '1 (18- to 20-inch) baguette, sliced in half horizontally',
            'item': '(18- to 20-inch) baguette',
            'others': 6,
            'others_lines': 6,
            'match': _baguette['match'],
            'candidates': <Object>[],
          },
        ],
        // The apply's receipt as snapshot 11 would give it: the baguette
        // reaches its six other lines and completes the two onion soups
        // (the recipes the queue promised).
        if ((options.data as Map?)?['apply_to_all'] == true)
          'applied': {
            'recipes': 6,
            'lines': 6,
            'failed': 0,
            'completed': 2,
            'completed_recipes': [
              'atk-tv-2023-0432-classic-french-onion-soup',
              'atk-tv-2023-0433-streamlined-french-onion-soup',
            ],
          },
      };
    } else if (options.path.contains('/almond-biscotti/nutrition/matches')) {
      // Almond Biscotti's open lines on snapshot 11: its whole almonds
      // (no grams) and the almond extract.
      body = {
        'items': [
          {
            'position': 0,
            'raw': '1¼ cups whole almonds, lightly toasted',
            'item': 'whole almonds',
            'match': {
              'fdc_id': 2346393,
              'description': 'Nuts, almonds, whole, raw',
              'data_type': 'Foundation',
              'confidence': 0.97,
              'grams': null,
              'gram_source': null,
              'status': 'auto',
            },
            'candidates': <Object>[],
          },
          {
            'position': 7,
            'raw': '1½ teaspoons almond extract',
            'item': 'almond extract',
            'match': _almond['match'],
            'candidates': <Object>[],
          },
        ],
      };
    } else if (options.path.contains(
      '/perfect-roast-chicken/nutrition/matches',
    )) {
      // The held brine sugar's own line, as the matches body serves it.
      body = {
        'items': [
          {
            'position': 1,
            'raw': '½ cup sugar',
            'item': 'sugar',
            'line_amount': '½ cup',
            'portions': <Object>[],
            'match': _sugar['match'],
            'candidates': <Object>[],
          },
        ],
      };
    } else if (options.path.contains('/admin/nutrition_review')) {
      queries.add(options.queryParameters);
      if (failing.contains(queries.length - 1)) {
        return ResponseBody.fromString(
          jsonEncode({
            'error': {'code': 'internal', 'message': 'down', 'requestId': 'r'},
          }),
          500,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      body = bodies[(queries.length - 1).clamp(0, bodies.length - 1)];
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

/// The rows' finishes pills (the pane's split has its own).
final _rowPills = find.byWidgetPredicate(
  (w) => w is FinishesPill && w.text.startsWith('finishes'),
);

void main() {
  Future<_Adapter> pumpQueue(
    WidgetTester tester,
    List<Map<String, dynamic>> bodies, {
    bool garamMovedUp = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = _Adapter(bodies, garamMovedUp: garamMovedUp);
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final recipeRepo = RecipeRepository(dio: dio);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: recipeRepo),
          RepositoryProvider.value(value: NutritionRepository(dio)),
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

  testWidgets('the queue opens on what a decision finishes: the header says '
      'so, the groups carry their pill, none at 0', (tester) async {
    final adapter = await pumpQueue(tester, [
      _body([_almond, _sugar, _garam]),
    ]);
    expect(adapter.queries.single['sort'], 'finishes');
    expect(
      find.text(
        'Showing all flagged · 3 ingredients, 30 lines · '
        'most recipes finished first',
      ),
      findsOneWidget,
    );
    expect(find.text('finishes 6 recipes'), findsOneWidget);
    // A group of one (the held brine sugar) finishes its own recipe.
    expect(find.text('finishes this recipe'), findsOneWidget);
    // garam masala finishes nothing: no "0" pill.
    expect(_rowPills, findsNWidgets(2));
    expect(find.text('Finishes recipes'), findsOneWidget);
    expect(find.text('Worst match'), findsOneWidget);
  });

  testWidgets('"Worst match" refetches in that order and the header ends '
      'with it', (tester) async {
    final adapter = await pumpQueue(tester, [
      _body([_almond, _sugar, _garam]),
      _body([_garam, _almond, _sugar]),
    ]);
    await tester.tap(find.text('Worst match'));
    await tester.pumpAndSettle();
    expect(adapter.queries.last['sort'], 'worst');
    expect(
      find.text(
        'Showing all flagged · 3 ingredients, 30 lines · worst match first',
      ),
      findsOneWidget,
    );
    // The pill shows in both orders.
    expect(find.text('finishes 6 recipes'), findsOneWidget);
  });

  testWidgets('the Lines view keeps the order: finishes by default, the '
      'same header words and segment, and "Worst match" refetches it', (
    tester,
  ) async {
    final adapter = await pumpQueue(tester, [
      _body([_almond, _sugar, _garam]),
    ]);
    await tester.tap(find.text('Lines'));
    await tester.pumpAndSettle();
    expect(adapter.queries.last.containsKey('group'), isFalse);
    expect(adapter.queries.last['sort'], 'finishes');
    expect(
      find.text('Showing all flagged · 30 lines · most recipes finished first'),
      findsOneWidget,
    );
    await tester.tap(find.text('Worst match'));
    await tester.pumpAndSettle();
    expect(adapter.queries.last.containsKey('group'), isFalse);
    expect(adapter.queries.last['sort'], 'worst');
    expect(
      find.text('Showing all flagged · 30 lines · worst match first'),
      findsOneWidget,
    );
  });

  testWidgets("the queue pane gives a held brine sugar ruling 5's ways out", (
    tester,
  ) async {
    await pumpQueue(tester, [
      _body([_almond, _sugar, _garam]),
    ]);
    await tester.tap(find.text('½ cup sugar').first);
    await tester.pumpAndSettle();
    expect(find.text('Enter edible grams'), findsOneWidget);
    expect(find.text('Skip, poured away'), findsOneWidget);
    expect(find.text('Confirm as-is'), findsNothing);
    expect(find.text('Confirm'), findsNothing);
    // A line of one finishes its recipe, but has no path to split.
    expect(find.text('What this decision finishes'), findsNothing);
    await tester.tap(find.text('Enter edible grams'));
    await tester.pumpAndSettle();
    final amount = tester.widget<EditableText>(find.byType(EditableText).last);
    expect(amount.focusNode.hasFocus, isTrue);
  });

  group('completeFix on a No grams group stays on the ingredient', () {
    Future<NutritionReviewCubit> cubitOver(
      List<Map<String, dynamic>> bodies,
    ) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _Adapter(bodies);
      final cubit = NutritionReviewCubit(RecipeRepository(dio: dio));
      addTearDown(cubit.close);
      await cubit.load();
      return cubit;
    }

    test('ginger: its next line opens, wherever the group now sits', () async {
      final cubit = await cubitOver([
        _body([_almond, _ginger()]),
        // After Chana Masala's ginger is confirmed with its amount, the
        // group leads with its next example.
        _body([
          _ginger(
            slug: 'chicken-biryani',
            title: 'Chicken Biryani',
            position: 7,
            raw:
                '1 (2-inch) piece fresh ginger, peeled, cut into '
                '½-inch-thick coins, and smashed',
            lines: 13,
          ),
          _almond,
        ]),
      ]);
      cubit.select('chana-masala#2');
      await cubit.completeFix();
      final state = cubit.state as NutritionReviewLoaded;
      expect(state.selected!.itemKey, 'ginger');
      expect(state.selectedKey, 'chicken-biryani#7');
    });

    test('a Check group advances by position as before', () async {
      final cubit = await cubitOver([
        _body([_almond, _garam]),
        _body([_garam, _almond]),
      ]);
      cubit.select('almond-biscotti#7');
      await cubit.completeFix();
      expect(
        (cubit.state as NutritionReviewLoaded).selectedKey,
        'chana-masala#12',
      );
    });
  });

  testWidgets('a line of one shows "finishes this recipe" only when it '
      'does; a group that finishes one says "1 recipe"', (tester) async {
    await pumpQueue(tester, [
      _body([_almond, _sugar, _sugarOpen, _pecan]),
    ]);
    // The brine sugar of Perfect Roast Chicken finishes its recipe; the
    // High-Roast Butterflied Chicken's does not: no pill at 0.
    expect(find.text('finishes this recipe'), findsOneWidget);
    expect(find.text('finishes 1 recipe'), findsOneWidget);
    expect(find.text('finishes 6 recipes'), findsOneWidget);
    expect(_rowPills, findsNWidgets(3));
  });

  testWidgets('the banner says how many partial recipes are one group '
      'decision away', (tester) async {
    await pumpQueue(tester, [
      _body([_almond, _garam]),
    ]);
    expect(
      find.text(
        '326 of the 625 partial recipes are one group decision away from '
        'complete. A count assumes the decision is applied to its whole '
        'group.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // The Lines view has no group decision to count.
    await tester.tap(find.text('Lines'));
    await tester.pumpAndSettle();
    expect(find.textContaining('one group decision'), findsNothing);
  });

  testWidgets('a No grams group says in how many recipes it holds the last '
      'open line; a line hold says how it is decided', (tester) async {
    await pumpQueue(tester, [
      _body([_pecan, _sugar, _ginger()]),
    ]);
    expect(
      find.textContaining(
        'no amount on any of the 8 lines · last open line in 6 recipes '
        '(this one included) · each needs its own amount',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'last open line in 2 recipes · each needs its own amount',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'line hold (discarded medium): decided one line at a time, never '
        'offers apply-to-all. Any decision finishes it: Skip says it is '
        'poured away, or a typed positive amount counts that much. There is '
        'no 0 g decision: the API rejects grams of 0.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('before the decision the pane splits what it finishes: this '
      'line alone, then the apply', (tester) async {
    await pumpQueue(tester, [
      _body([_almond, _garam]),
    ]);
    expect(find.text('What this decision finishes'), findsOneWidget);
    expect(
      find.textContaining(
        'This line only: 0 recipes. Almond Biscotti still waits on 1¼ cups '
        'whole almonds, lightly toasted.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('Then Apply to the other 8 lines:'), findsOneWidget);
    expect(find.text('6 recipes complete'), findsOneWidget);
    expect(
      find.text(
        'Angel Food Cake, Best Almond Cake, Classic White Layer Cake with '
        'Butter Frosting and Raspberry-Almond Filling, Cranberry Curd Tart '
        'with Almond Crust … +2',
      ),
      findsOneWidget,
    );
    // Confirm and Skip sit above it.
    expect(
      tester.getTopLeft(find.text('Confirm as-is')).dy,
      lessThan(tester.getTopLeft(find.text('What this decision finishes')).dy),
    );
  });

  test('the promise an apply is held to leaves out the line\'s own recipe', () {
    final line = NutritionReviewLine.fromJson(_sugar);
    expect(othersPromised(line), isEmpty);
    expect(
      othersPromised(NutritionReviewLine.fromJson(_almond)).map((r) => r.title),
      hasLength(6),
    );
  });

  group('Run 046 A10: the held lines in the pane (ruling 5)', () {
    testWidgets('the pasta-water salt offers Confirm for its eaten part, '
        'and the confirm writes it', (tester) async {
      final adapter = await pumpQueue(tester, [
        _body([_macSalt]),
      ]);
      expect(find.text('Enter edible grams'), findsOneWidget);
      expect(find.text(heldSkipLabel), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(adapter.puts.single.$1, endsWith('/matches/2'));
      expect(adapter.puts.single.$2, {
        'raw': _macSalt['raw'],
        'confirmed': true,
      });
    });

    testWidgets('the oysters in the shell, no grams: never a plain Confirm', (
      tester,
    ) async {
      await pumpQueue(tester, [
        _body([_oysters]),
      ]);
      expect(find.text('Enter edible grams'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(
        confirmsWithoutAmount(
          IngredientMatch.fromJson(const {
            'position': 3,
            'raw': '24 oysters, 2½ to 3 inches long, well scrubbed',
            'match': _oysterMatch,
          }),
        ),
        isFalse,
      );
    });
  });

  // Run 051 A2: a save since the last compute deleted a line above the
  // garam masala (the adapter's garamMovedUp — a stated exception), so the
  // queue's stored position 12 holds no line and the garam masala sits at
  // 11. The pane finds the line by its text where it is now, sends ITS text
  // (the bold heading), and judges the advance on the row it acted on.
  group('Run 051 A2: a line a save moved', () {
    testWidgets('a Confirm that leaves the moved line in No grams keeps the '
        'pane on it', (tester) async {
      final adapter = await pumpQueue(tester, [
        _body([_garam, _almond]),
        _body([_almond]),
      ], garamMovedUp: true);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        adapter.puts.single.$1,
        endsWith('/chana-masala/nutrition/matches/11'),
      );
      expect(adapter.puts.single.$2, {'raw': _garam['raw'], 'confirmed': true});
      expect(adapter.queries, hasLength(1), reason: 'the queue did not move');
      expect(find.text('Confirm with amount'), findsOneWidget);
    });

    testWidgets('a Skip of the moved line lands on it and advances the pane', (
      tester,
    ) async {
      final adapter = await pumpQueue(tester, [
        _body([_garam, _almond]),
        _body([_almond]),
      ], garamMovedUp: true);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(
        adapter.puts.single.$1,
        endsWith('/chana-masala/nutrition/matches/11'),
      );
      expect(adapter.puts.single.$2, {'raw': _garam['raw'], 'skipped': true});
      expect(adapter.queries, hasLength(2), reason: 'the queue moved on');
    });
  });

  group('Run 046 A10: the split and the group wiring', () {
    testWidgets('a group of six lines that finishes nothing shows no split', (
      tester,
    ) async {
      await pumpQueue(tester, [
        _body([_garam]),
      ]);
      expect(find.text('What this decision finishes'), findsNothing);
    });

    testWidgets('a No grams line of one has no group notes', (tester) async {
      await pumpQueue(tester, [
        _body([_ginger(lines: 1)]),
      ]);
      expect(find.text('Confirm with amount'), findsOneWidget);
      expect(
        find.textContaining('No apply-to-all offer', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('the pane stays on', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('five promised names: four shown and "+1"', (tester) async {
      // Snapshot 11's tarragon group (by the server's nutritionReviewGroups
      // over a copy of snap11): its example finishes Broccoli Salad by
      // itself, and the apply the five others, in title order.
      final tarragon = _group(
        id: 'atk-tv-2023-1073-broccoli-salad-with-creamy-avocado-dressing',
        slug: 'broccoli-salad-with-creamy-avocado-dressing',
        title: 'Broccoli Salad with Creamy Avocado Dressing',
        position: 11,
        raw: '1 tablespoon minced fresh tarragon',
        bucket: 'check',
        itemKey: 'tarragon',
        item: 'fresh tarragon',
        lines: 7,
        finishes: 6,
        fdcId: 170937,
        description: 'Spices, tarragon, dried',
        confidence: 0.8066666666666666,
        grams: 1.8,
        gramSource: 'portion',
        lastOpen: 6,
        finishesRecipes: [
          [
            'atk-tv-2023-1073-broccoli-salad-with-creamy-avocado-dressing',
            'Broccoli Salad with Creamy Avocado Dressing',
          ],
          ['atk-tv-2023-0298-classic-chicken-salad', 'Classic Chicken Salad'],
          [
            'atk-tv-2023-0628-grilled-stuffed-chicken-breasts-with-prosciutto-and-fontina',
            'Grilled Stuffed Chicken Breasts with Prosciutto and Fontina',
          ],
          [
            'atk-tv-2023-1092-poulet-au-vinaigre-chicken-with-vinegar',
            'Poulet au Vinaigre (Chicken with Vinegar)',
          ],
          ['atk-tv-2023-0286-shrimp-salad', 'Shrimp Salad'],
          [
            'atk-tv-2023-0021-super-greens-soup-with-lemon-tarragon-cream',
            'Super Greens Soup with Lemon-Tarragon Cream',
          ],
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinishesSplit(
              line: NutritionReviewLine.fromJson(tarragon),
              match: const IngredientMatch(
                position: 11,
                raw: '1 tablespoon minced fresh tarragon',
                fdcId: 170937,
                description: 'Spices, tarragon, dried',
                confidence: 0.8066666666666666,
                grams: 1.8,
                gramSource: 'portion',
                status: 'auto',
              ),
              waiting: const [],
            ),
          ),
        ),
      );
      expect(
        find.textContaining('This line only: 1 recipe.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('5 recipes complete'), findsOneWidget);
      expect(
        find.text(
          'Classic Chicken Salad, Grilled Stuffed Chicken Breasts with '
          'Prosciutto and Fontina, Poulet au Vinaigre (Chicken with '
          'Vinegar), Shrimp Salad … +1',
        ),
        findsOneWidget,
      );
    });
  });

  group('the pane stays on a Check line a plain Confirm left in No grams', () {
    // Chana Masala pos 12 before and after a confirm USDA could not convert.
    const before = IngredientMatch(
      position: 12,
      raw: '1½ teaspoons garam masala',
      fdcId: 171181,
      description: 'SMART SOUP, Indian Bean Masala',
      dataType: 'SR Legacy',
      confidence: 0.014999999999999958,
      status: 'auto',
    );
    const after = IngredientMatch(
      position: 12,
      raw: '1½ teaspoons garam masala',
      fdcId: 171181,
      description: 'SMART SOUP, Indian Bean Masala',
      dataType: 'SR Legacy',
      confidence: 1,
      status: 'confirmed',
    );
    const inFlight = NutritionState(
      loading: false,
      matches: [before],
      overridingPosition: 12,
    );

    test('no grams after: stay', () {
      const landed = NutritionState(loading: false, matches: [after]);
      expect(queueShouldAdvance(inFlight, landed), isTrue);
      expect(leftWaitingOnAmount(landed, 12), isTrue);
      expect(paneAdvances(inFlight, landed, 12), isFalse);
    });

    test('grams after, or another line: advance', () {
      const counted = NutritionState(
        loading: false,
        matches: [
          IngredientMatch(
            position: 12,
            raw: '1½ teaspoons garam masala',
            fdcId: 171181,
            description: 'SMART SOUP, Indian Bean Masala',
            dataType: 'SR Legacy',
            confidence: 1,
            grams: 3.9,
            gramSource: 'portion',
            status: 'confirmed',
          ),
        ],
      );
      expect(leftWaitingOnAmount(counted, 12), isFalse);
      expect(paneAdvances(inFlight, counted, 12), isTrue);
      const landed = NutritionState(loading: false, matches: [after]);
      expect(leftWaitingOnAmount(landed, 2), isFalse);
    });
  });

  group('the queue cubit keeps its promises', () {
    Future<(NutritionReviewCubit, _Adapter)> cubitOver(
      List<Map<String, dynamic>> bodies, {
      Set<int> failing = const {},
    }) async {
      final adapter = _Adapter(bodies, failing: failing);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final cubit = NutritionReviewCubit(RecipeRepository(dio: dio));
      addTearDown(cubit.close);
      await cubit.load();
      return (cubit, adapter);
    }

    test('a No grams line of ONE does not hold the pane on its key: there is '
        'no next line of it to open', () async {
      final (cubit, _) = await cubitOver([
        _body([_ginger(lines: 1), _almond]),
        _body([
          _almond,
          _ginger(
            slug: 'chicken-biryani',
            title: 'Chicken Biryani',
            position: 7,
            raw:
                '1 (2-inch) piece fresh ginger, peeled, cut into '
                '½-inch-thick coins, and smashed',
            lines: 1,
          ),
        ]),
      ]);
      cubit.select('chana-masala#2');
      await cubit.completeFix();
      expect(
        (cubit.state as NutritionReviewLoaded).selectedKey,
        'almond-biscotti#7',
      );
    });

    test('a failed order switch puts the order back: the next reload asks '
        'for finishes', () async {
      final (cubit, adapter) = await cubitOver(
        [
          _body([_almond, _garam]),
        ],
        failing: {1},
      );
      await cubit.setSort('worst');
      expect(adapter.queries[1]['sort'], 'worst');
      expect((cubit.state as NutritionReviewLoaded).sort, 'finishes');
      await cubit.completeFix();
      expect(adapter.queries.last['sort'], 'finishes');
    });
  });

  group('refix round 2', () {
    testWidgets('the split never counts a recipe twice: the baguette example '
        'finishes Cheesy Garlic Bread by itself, so the apply promises the '
        'two onion soups — the number the offer and receipt hold to', (
      tester,
    ) async {
      await pumpQueue(tester, [
        _body([_baguette, _garam]),
      ]);
      expect(
        find.textContaining('This line only: 1 recipe.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Then Apply to the other 6 lines:'), findsOneWidget);
      expect(find.text('2 recipes complete'), findsOneWidget);
      expect(
        find.text('Classic French Onion Soup, Streamlined French Onion Soup'),
        findsOneWidget,
      );
      expect(
        othersPromised(
          NutritionReviewLine.fromJson(_baguette),
        ).map((r) => r.title),
        ['Classic French Onion Soup', 'Streamlined French Onion Soup'],
      );
    });

    testWidgets('the offer and the receipt hold to the split\'s promise: '
        'the baguette\'s apply finishes the two onion soups, as promised', (
      tester,
    ) async {
      final adapter = await pumpQueue(tester, [
        _body([_baguette, _garam]),
      ]);
      await tester.tap(find.text('Confirm as-is'));
      await tester.pumpAndSettle();
      expect(adapter.puts.single.$2, {
        'raw': _baguette['raw'],
        'confirmed': true,
      });
      // Not 3: Cheesy Garlic Bread is finished by the confirm itself.
      expect(
        find.textContaining(
          'still waiting on this decision. Applying finishes 2 recipes.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Apply to 6 lines'));
      await tester.pumpAndSettle();
      expect(adapter.puts.last.$2, {
        'raw': _baguette['raw'],
        'confirmed': true,
        'apply_to_all': true,
      });
      expect(
        find.textContaining(
          '2 recipes are now complete, as promised.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a group that finishes only its example\'s recipe promises '
        'no apply: the pecans', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinishesSplit(
              line: NutritionReviewLine.fromJson(_pecan),
              match: const IngredientMatch(
                position: 3,
                raw: '⅓ cup coarsely chopped pecans, toasted',
                fdcId: 2346395,
                description: 'Nuts, pecans, halves, raw',
                confidence: 0.92,
                status: 'auto',
              ),
              waiting: const [],
            ),
          ),
        ),
      );
      expect(
        find.textContaining('This line only: 1 recipe.', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Then Apply'), findsNothing);
      expect(find.byType(FinishesPill), findsNothing);
    });

    testWidgets('S1: a Check example with no grams finishes nothing by '
        'itself — a plain Confirm leaves it without grams', (tester) async {
      // Snapshot 11: Parmesan Farrotto's last open line, whole farro at
      // 0.495 with no grams (the server's finishes is 0 at both grains).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinishesSplit(
              line: NutritionReviewLine.fromJson(
                _group(
                  id: 'atk-tv-2023-0412-parmesan-farrotto',
                  slug: 'parmesan-farrotto',
                  title: 'Parmesan Farrotto',
                  position: 0,
                  raw: '1½ cups whole farro',
                  bucket: 'check',
                  itemKey: 'whole farro',
                  item: 'whole farro',
                  lines: 2,
                  finishes: 0,
                  fdcId: 2710828,
                  description: 'Farro, pearled, dry, raw',
                  confidence: 0.495,
                  missing: 2,
                ),
              ),
              match: const IngredientMatch(
                position: 0,
                raw: '1½ cups whole farro',
                fdcId: 2710828,
                description: 'Farro, pearled, dry, raw',
                dataType: 'Foundation',
                confidence: 0.495,
                status: 'auto',
              ),
              waiting: const [],
            ),
          ),
        ),
      );
      expect(
        find.textContaining('This line only: 0 recipes.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('the queue pane wires C: the Skip beside "Confirm with '
        'amount" writes a skip, and the consequences name the recipe, the '
        'missing offer and where the pane goes next', (tester) async {
      final adapter = await pumpQueue(tester, [
        _body([_ginger(), _almond]),
      ]);
      expect(find.text('Confirm with amount'), findsOneWidget);
      expect(
        find.textContaining(
          'Chana Masala still waits on 1 more line after this: 1½ teaspoons '
          'garam masala.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'No apply-to-all offer. The 13 other ginger lines are already on '
          'this food at 89%, so they are not targets, and a typed amount '
          'never travels.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'After the confirm the pane stays on ginger and opens its next '
          'line (13 left), because each line needs its own amount.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // One Skip: the amount block's, the pane's own stepping aside.
      expect(find.text('Skip'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(adapter.puts, hasLength(1));
      expect(
        adapter.puts.single.$1,
        '/api/v1/recipes/chana-masala/nutrition/matches/2',
      );
      expect(adapter.puts.single.$2, {
        'raw': _ginger()['raw'],
        'skipped': true,
      });
    });

    testWidgets('a plain Confirm that leaves the line in No grams keeps the '
        'pane on it: no reload, the amount block takes over', (tester) async {
      final adapter = await pumpQueue(tester, [
        _body([_satay, _almond]),
      ]);
      expect(adapter.queries, hasLength(1));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(adapter.puts.single.$2, {'raw': _satay['raw'], 'confirmed': true});
      expect(adapter.queries, hasLength(1), reason: 'the queue did not move');
      expect(find.text('Confirm with amount'), findsOneWidget);
    });

    testWidgets('the banner hides at 0, and only a No grams group says each '
        'line needs its own amount', (tester) async {
      await pumpQueue(tester, [
        {
          ..._body([_almond, _garam]),
          'finishable': 0,
        },
      ]);
      expect(find.textContaining('one group decision'), findsNothing);
      // Almond extract holds the last open line of six recipes, but its
      // confirm can travel: no "own amount" note.
      expect(find.textContaining('its own amount'), findsNothing);
      expect(lastOpenNote(NutritionReviewLine.fromJson(_almond)), isNull);
    });

    test('Load more keeps the session\'s order and the banner counts '
        '(snapshot 11, worst first)', () async {
      final pages =
          jsonDecode(
                File(
                  'test/fixtures/nutrition_review_worst_pages.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final page1 = pages['page1'] as Map<String, dynamic>;
      final adapter = _Adapter([
        page1,
        page1,
        pages['page2'] as Map<String, dynamic>,
      ]);
      final cubit = NutritionReviewCubit(
        RecipeRepository(
          dio: Dio(BaseOptions(baseUrl: 'http://test'))
            ..httpClientAdapter = adapter,
        ),
      );
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.setSort('worst');
      await cubit.loadMore();
      expect(adapter.queries.last['page'], '2');
      expect(adapter.queries.last['sort'], 'worst');
      final state = cubit.state as NutritionReviewLoaded;
      expect(state.items, hasLength(52));
      expect(state.sort, 'worst');
      expect(state.finishable, 326);
      expect(state.openRecipes, 625);
    });

    testWidgets('the Lines view shows "finishes this recipe" on a last open '
        'line', (tester) async {
      final golden =
          jsonDecode(
                File(
                  '../../packages/salt_shared/test/fixtures/contract/'
                  'nutrition_review.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      await pumpQueue(tester, [
        _body([_almond]),
        golden,
      ]);
      await tester.tap(find.text('Lines'));
      await tester.pumpAndSettle();
      expect(find.text('Confectioners’ sugar, for dusting'), findsWidgets);
      expect(find.text('finishes this recipe'), findsOneWidget);
    });
  });
}
