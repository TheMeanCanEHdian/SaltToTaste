// Matcher v44 step 8 — sections as children in the app (the approved copy
// delta docs/mockups/v44-sections-copy.html over the v41 copy sheet;
// design_v2 §2 v44 step 8 and S8–S15; p3_api_app.md §5, §8 "APP").
//
// Real data only: every body is a shipped contract golden — real corpus
// lines through the real server routes (Chraime 1208 routed on its own
// "Tabil"; Pumpkin Pie 0987 on Basic Double-Crust Pie Dough 0972's "Basic
// Single-Crust Pie Dough"; Glazed Spiral-Sliced Ham 0251's "1 recipe glaze
// (recipes follow)" listing its two glazes; Lemon Meringue Pie 0989 on a
// prose section; the queue's Satay Glaze line of Grilled Glazed Pork
// Tenderloin Roast 0601) — served BY PATH through a Dio adapter, so the
// repositories (their `?section=` building included), the cubits and the
// widgets all run. A sheet is opened with the recipe's corpus title, as the
// detail page passes it.
// SYNTHESIZED — disclosed edits of real golden rows (the v41 precedent):
// (1) no golden candidate is in state no_totals, no_ingredients or nested
//     (S14 (a) lists child sections only; both glazes are computed), so the
//     right-column pin puts each state on the ham's real Maple-Orange Glaze
//     candidate, with pickable false and no kcal where the server would
//     store no totals;
// (2) no golden flags another host's includes entry, so the flagged
//     includesLine pin puts the wire's "approximation" on Pumpkin Pie's;
// (3) no golden holds a retitled section pick (S15 (a)), so the retitle
//     pin holds Chraime's and Pumpkin Pie's real routed rows choose_recipe
//     missing (child state held, reason missing; slug, title, section and
//     host_title kept, as API.md says the server keeps them); the queue
//     pane's pin puts the same shape on Free-Form Apple Tart's real
//     held-missing "Rustic Tart Dough (this page)" row (its section and
//     title "Rustic Tart Dough", its slug the tart's, host_title null);
// (4) no golden carries a marinade (discarded_recipe) line with section
//     candidates, so the share-gate pin puts that hold (child reason
//     marinade) on the ham's real "(recipes follow)" line — rule PO lists
//     a marinade's own sections the same way (S8 (a));
// (5) no golden carries the Satay Glaze section's own matches, so the
//     queue pane is served the pie-dough section's real matches body
//     (nutrition_section_matches) with its line 1's raw set to the queue
//     line's text — the text the pane finds its row by;
// (6) no golden queue holds a host's own line at a section line's position,
//     so the queue-key pin compares the real Satay Glaze item with itself
//     less its section;
// (7) no golden offers apply-to-all on a section line, so the apply pin
//     answers the section line's PUT with the real section matches body
//     carrying others / others_lines 3 (nutrition_composite_test's apply
//     pin, the boot(others:) precedent);
// (8) no golden carries a compute in flight on a section, so the
//     re-attach pin puts computing_job_id 7 on the real section label and
//     answers the job GET with a done body (nutrition_tab_scope_test's
//     shape);
// (9) no label golden exists for the ham, so its sheet's label GET
//     answers {"status": "none"}.
// (10) no golden queue holds a section line in No grams, so the queue
//     pane's consequence pin puts the real Satay Glaze item in bucket
//     no_grams and drops the grams of its pane row (SYNTHESIZED (5)'s);
// (11) no golden holds a reference line inside a section, so the queue
//     pane's own-group pin puts the Satay Glaze item in bucket
//     choose_recipe and its pane row on Free-Form Apple Tart's real
//     held-missing match (nutrition_matches_choose_recipe line 5);
// (12) no golden credits a section group, so FinishesSplit is pumped
//     with the real Satay Glaze item at lines 2, finishes 1, over rows of
//     SYNTHESIZED (5)'s body.
// Negative path: the line_moved 409 envelope is synthesized
// (nutrition_cubit_apply_test's envelope).
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
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/nutrition_label.dart';
import 'package:salt_app/features/nutrition/recipe_fix_panel.dart';
import 'package:salt_app/features/nutrition/review_sheet.dart';

import 'support/contract_goldens.dart';

/// Answers each GET by the PATH the repository built (query included) and
/// records it; a path with no body is a 404, so a wrong URL shows. Every
/// PUT is recorded with its path and answered with [put] at [putStatus].
class _Routes implements HttpClientAdapter {
  _Routes(this.bodies, {this.put, this.putStatus = 200});

  final Map<String, Object?> bodies;
  final Object? put;
  final int putStatus;
  final List<String> gets = [];
  final List<({String path, Object? body})> puts = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final Object? body;
    var status = 200;
    if (options.method == 'PUT') {
      puts.add((path: path, body: options.data));
      body = put;
      status = putStatus;
    } else {
      gets.add(path);
      if (bodies.containsKey(path)) {
        body = bodies[path];
      } else {
        status = 404;
        body = {
          'error': {'code': 'not_found', 'message': 'No route for $path'},
        };
      }
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _app(_Routes routes, Widget home) {
  final dio = Dio(BaseOptions(baseUrl: 'http://contract'))
    ..httpClientAdapter = routes;
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider.value(value: NutritionRepository(dio)),
      RepositoryProvider.value(value: RecipeRepository(dio: dio)),
    ],
    child: MaterialApp(
      theme: buildMaterialTheme(buildForuiTheme()),
      builder: (context, child) =>
          FTheme(data: buildForuiTheme(), child: child!),
      home: home,
    ),
  );
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A deep copy of golden [name] (the file is left as shipped).
Map<String, dynamic> _copy(String name) =>
    jsonDecode(jsonEncode(golden(name))) as Map<String, dynamic>;

/// [body]'s item at [position].
Map<String, dynamic> _item(Map<String, dynamic> body, int position) =>
    (body['items']! as List).cast<Map<String, dynamic>>().singleWhere(
      (i) => i['position'] == position,
    );

String _matches(String slug) => '/api/v1/recipes/$slug/nutrition/matches';
String _label(String slug) => '/api/v1/recipes/$slug/nutrition';

/// The recipe page's label for [slug], its GETs answered by [bodies] (PUTs
/// by its matches); [open] taps the badge open, as a person does.
Future<_Routes> _page(
  WidgetTester t, {
  required String slug,
  required Map<String, Object?> bodies,
  required ReviewParent parent,
  bool isAdmin = true,
  bool open = true,
}) async {
  _size(t);
  final routes = _Routes(bodies, put: bodies[_matches(slug)]);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    _app(
      routes,
      BlocProvider(
        create: (context) =>
            NutritionCubit(context.read<NutritionRepository>(), slug)..load(),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 640,
              child: NutritionPanel(isAdmin: isAdmin, parent: parent),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  if (open) {
    await t.tap(find.textContaining('ingredients matched'));
    await t.pumpAndSettle();
  }
  return routes;
}

/// The ham's sheet ([matches] for its matches GET; no label golden exists
/// for it, so its label is "none"), opened straight from the recipe's cubit.
Future<_Routes> _hamSheet(WidgetTester t, Map<String, dynamic> matches) async {
  _size(t);
  final routes = _Routes({
    _matches(_ham): matches,
    _label(_ham): {'status': 'none'},
  }, put: matches);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    _app(
      routes,
      BlocProvider(
        create: (context) =>
            NutritionCubit(context.read<NutritionRepository>(), _ham),
        child: Scaffold(
          body: Builder(
            builder: (context) => FButton(
              onPress: () => showReviewSheet(
                context,
                isAdmin: true,
                parent: (title: 'Glazed Spiral-Sliced Ham', hasSections: true),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return routes;
}

/// Scrolls [finder] into the sheet's view, then taps it.
Future<void> _tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Finder _inPanel(Finder finder) =>
    find.descendant(of: find.byType(RecipeFixPanel), matching: finder);

/// The tick on the candidate row titled [title].
Finder _tick(String title) => find.descendant(
  of: find.ancestor(
    of: _inPanel(find.text(title)),
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_CandidateRow',
    ),
  ),
  matching: find.byIcon(FLucideIcons.check),
);

FButton _button(String label) =>
    find
            .ancestor(of: find.text(label), matching: find.byType(FButton))
            .evaluate()
            .first
            .widget
        as FButton;

const _ham = 'glazed-spiral-sliced-ham';
const _hamRaw = '1 recipe glaze (recipes follow)';
const _maple = 'Maple-Orange Glaze';
const _cherry = 'Cherry-Port Glaze';
const _dough = 'basic-double-crust-pie-dough';
const _sectionQuery = '?section=Basic%20Single-Crust%20Pie%20Dough';
const ReviewParent _chraime = (title: 'Chraime', hasSections: true);
const ReviewParent _pumpkin = (title: 'Pumpkin Pie', hasSections: false);
const ReviewParent _lemon = (title: 'Lemon Meringue Pie', hasSections: true);

/// Chraime's page: its matches and its label (own section, Tabil).
Map<String, Object?> _chraimeBodies([Map<String, dynamic>? matches]) => {
  _matches('chraime'): matches ?? golden('nutrition_matches_section_own'),
  _label('chraime'): golden('nutrition_section_own'),
};

/// Pumpkin Pie's page (another host's section), and that section's own
/// matches and per-batch label behind "Open the recipe's matches".
Map<String, Object?> _pumpkinBodies([Map<String, dynamic>? matches]) => {
  _matches('pumpkin-pie'): matches ?? golden('nutrition_matches_section_other'),
  _label('pumpkin-pie'): golden('nutrition_section_other'),
  '${_matches(_dough)}$_sectionQuery': golden('nutrition_section_matches'),
  '${_label(_dough)}$_sectionQuery': golden('nutrition_section_label'),
};

/// [name]'s golden with its reference row at [position] held choose_recipe
/// missing — the shape a retitled section's pick takes (SYNTHESIZED (3)).
Map<String, dynamic> _retitled(String name, int position) {
  final body = _copy(name);
  final match = _item(body, position)['match']! as Map<String, dynamic>;
  match['hold'] = 'choose_recipe';
  (match['child']! as Map<String, dynamic>)
    ..['state'] = 'held'
    ..['reason'] = 'missing';
  return body;
}

void main() {
  group('the fix sheet: section candidates (glazed-spiral-sliced-ham|2)', () {
    testWidgets('tick ONE glaze of two sharing a slug; the PUT names the '
        'section', (t) async {
      final routes = await _hamSheet(
        t,
        golden('nutrition_matches_section_pick'),
      );
      await _tap(t, find.text('Choose a recipe'));
      expect(_inPanel(find.text("This recipe's sections")), findsOneWidget);
      // Both own glazes are ready: the library row's shipped calories.
      expect(
        _inPanel(find.text('1,223 kcal · +102 / serving')),
        findsOneWidget,
      );
      expect(
        _inPanel(find.text('1,479 kcal · +123 / serving')),
        findsOneWidget,
      );
      expect(_tick(_maple), findsNothing);
      expect(_tick(_cherry), findsNothing);

      await _tap(t, _inPanel(find.text(_cherry)));
      expect(_tick(_cherry), findsOneWidget);
      expect(_tick(_maple), findsNothing, reason: 'one slug, two keys');
      await _tap(t, _inPanel(find.text('Use this recipe · 1 recipe')));
      expect(routes.puts, hasLength(1));
      expect(routes.puts.single.path, '${_matches(_ham)}/2');
      expect(routes.puts.single.body, {
        'raw': _hamRaw,
        'child': _ham,
        'section': _cherry,
      });
    });

    testWidgets('the right column by state; a section with no totals stages '
        'nothing', (t) async {
      for (final (state, pickable, text) in [
        ('no_totals', false, 'no totals yet'),
        ('no_ingredients', false, 'no ingredients listed'),
        ('nested', true, 'made from another recipe'),
      ]) {
        // SYNTHESIZED (1): the state on the real Maple-Orange candidate.
        final body = _copy('nutrition_matches_section_pick');
        final maple =
            ((_item(body, 2)['match']! as Map)['child']! as Map)['candidates']
                as List;
        final candidate = maple.first as Map<String, dynamic>;
        expect(candidate['title'], _maple);
        candidate
          ..['state'] = state
          ..['pickable'] = pickable;
        if (!pickable) {
          candidate
            ..['kcal'] = null
            ..['kcal_per_serving'] = null;
        }
        await _hamSheet(t, body);
        await _tap(t, find.text('Choose a recipe'));
        expect(_inPanel(find.text(text)), findsOneWidget, reason: state);
        expect(
          _inPanel(find.text('1,223 kcal · +102 / serving')),
          findsNothing,
          reason: state,
        );
        // The ready glaze keeps its calories.
        expect(
          _inPanel(find.text('1,479 kcal · +123 / serving')),
          findsOneWidget,
          reason: state,
        );
        expect(_inPanel(find.text('phase 2 · no totals yet')), findsNothing);
        if (state == 'no_totals') {
          // closer1 D1's deferred pin: nothing staged, the button waits.
          await _tap(t, _inPanel(find.text(_maple)));
          expect(_tick(_maple), findsNothing);
          expect(_button('Use this recipe').onPress, isNull);
          expect(
            _inPanel(find.text('Enabled once a recipe is picked.')),
            findsOneWidget,
          );
        }
      }
    });

    testWidgets('a marinade pick waits on a typed share (S10 (a)); the PUT '
        'carries it', (t) async {
      // SYNTHESIZED (4): the poured-away marinade hold on the real line.
      final body = _copy('nutrition_matches_section_pick');
      final match = _item(body, 2)['match']! as Map<String, dynamic>;
      match['hold'] = 'discarded_recipe';
      (match['child']! as Map<String, dynamic>)['reason'] = 'marinade';
      final routes = await _hamSheet(t, body);
      await _tap(t, find.text('Choose a recipe'));
      final share = _inPanel(find.byType(EditableText)).last;
      expect(t.widget<EditableText>(share).controller.text, isEmpty);
      await _tap(t, _inPanel(find.text(_cherry)));
      expect(_tick(_cherry), findsOneWidget);
      expect(_button('Use this recipe').onPress, isNull);
      expect(
        _inPanel(
          find.text('Set the share that is eaten — the rest is poured away.'),
        ),
        findsOneWidget,
      );
      await t.enterText(share, '¼');
      await t.pumpAndSettle();
      expect(_button('Use this recipe · ¼ recipe').onPress, isNotNull);
      expect(
        _inPanel(
          find.text('Set the share that is eaten — the rest is poured away.'),
        ),
        findsNothing,
      );
      await _tap(t, _inPanel(find.text('Use this recipe · ¼ recipe')));
      expect(
        [for (final p in routes.puts) p.body],
        [
          {'raw': _hamRaw, 'child': _ham, 'section': _cherry, 'share': 0.25},
        ],
      );
    });
  });

  group('the routed row and the label', () {
    testWidgets("another host's section: the suffix and the label's host", (
      t,
    ) async {
      await _page(
        t,
        slug: 'pumpkin-pie',
        bodies: _pumpkinBodies(),
        parent: _pumpkin,
      );
      expect(
        find.text(
          'Includes 1 recipe: Basic Single-Crust Pie Dough (a section of '
          'Basic Double-Crust Pie Dough)',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'made from the recipe Basic Single-Crust Pie Dough · a section of '
          'Basic Double-Crust Pie Dough',
        ),
        findsOneWidget,
      );
      // The basis line is the server's, the section's title in it.
      expect(
        find.text(
          'amount: from the recipe Basic Single-Crust Pie Dough: 302 g, '
          '1,545 kcal · +193 kcal per serving',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an own section: its bare title, no suffix', (t) async {
      await _page(
        t,
        slug: 'chraime',
        bodies: _chraimeBodies(),
        parent: _chraime,
      );
      expect(find.text('Includes 1 recipe: Tabil'), findsOneWidget);
      expect(find.text('made from the recipe Tabil'), findsOneWidget);
      expect(find.textContaining('a section of'), findsNothing);
    });

    testWidgets('an own section routed (chraime|7): its row is ticked '
        'current; Save share PUTs the section, not the host', (t) async {
      final routes = await _page(
        t,
        slug: 'chraime',
        bodies: _chraimeBodies(),
        parent: _chraime,
      );
      await _tap(t, find.text('Change'));
      // Selected by (slug, section): the routed Tabil row is the current one.
      expect(_tick('Tabil'), findsOneWidget);
      await t.enterText(_inPanel(find.byType(EditableText)).last, '¼');
      await t.pumpAndSettle();
      await _tap(t, _inPanel(find.text('Save share · ¼ recipe')));
      // Without `section` the child would be the host itself (422) — or,
      // on another host's section, that host's whole recipe.
      expect(
        [for (final p in routes.puts) p.body],
        [
          {
            'raw': '1 tablespoon tabil (recipe follows)',
            'child': 'chraime',
            'section': 'Tabil',
            'share': 0.25,
          },
        ],
      );
    });

    test('includesLine: own bare, another host, flagged (one joiner)', () {
      RecipeNutrition label(String name) =>
          RecipeNutrition.fromJson(golden(name));
      expect(
        includesLine(label('nutrition_section_own')),
        'Includes 1 recipe: Tabil',
      );
      expect(
        includesLine(label('nutrition_section_other')),
        'Includes 1 recipe: Basic Single-Crust Pie Dough (a section of '
        'Basic Double-Crust Pie Dough)',
      );
      // SYNTHESIZED (2): the wire's flag on the other host's entry.
      final flagged = _copy('nutrition_section_other');
      ((flagged['includes']! as List).single as Map)['flag'] = 'approximation';
      expect(
        includesLine(RecipeNutrition.fromJson(flagged)),
        'Includes 1 recipe: Basic Single-Crust Pie Dough (a section of '
        'Basic Double-Crust Pie Dough; approximation)',
      );
    });

    testWidgets('a prose section: the partial line and the row note', (
      t,
    ) async {
      await _page(
        t,
        slug: 'lemon-meringue-pie',
        bodies: {
          _matches('lemon-meringue-pie'): golden(
            'nutrition_matches_section_prose',
          ),
          _label('lemon-meringue-pie'): golden('nutrition_section_prose'),
        },
        parent: _lemon,
      );
      expect(
        find.text(
          'Partial: Single-Crust Pie Dough for Custard Pies is not counted '
          '(its section lists no ingredients).',
        ),
        findsOneWidget,
      );
      expect(find.text('not counted'), findsOneWidget);
      expect(
        find.text('Its section lists no ingredients — not counted'),
        findsOneWidget,
      );
    });
  });

  group("Open the recipe's matches on a section", () {
    testWidgets('member: the link, no Change; the GETs carry ?section=', (
      t,
    ) async {
      final routes = await _page(
        t,
        slug: 'pumpkin-pie',
        bodies: _pumpkinBodies(),
        parent: _pumpkin,
        isAdmin: false,
      );
      expect(find.text("Open the recipe's matches"), findsOneWidget);
      expect(find.text('Change'), findsNothing);
      await _tap(t, find.text("Open the recipe's matches"));
      expect(routes.gets, contains('${_matches(_dough)}$_sectionQuery'));
      expect(routes.gets, contains('${_label(_dough)}$_sectionQuery'));
      // The section's own six lines, never the host's.
      for (final raw in [
        '1 tablespoon sugar',
        '½ teaspoon table salt',
        '4–6 tablespoons ice water',
      ]) {
        expect(find.text(raw), findsOneWidget, reason: raw);
      }
      expect(routes.gets.where((g) => g.startsWith(_matches(_dough))), [
        '${_matches(_dough)}$_sectionQuery',
      ]);
    });

    testWidgets('admin: the section sheet sets no serving basis (the PUT '
        'takes no section)', (t) async {
      await _page(
        t,
        slug: 'pumpkin-pie',
        bodies: _pumpkinBodies(),
        parent: _pumpkin,
      );
      expect(find.text('Per-serving basis'), findsOneWidget);
      await _tap(t, find.text("Open the recipe's matches"));
      expect(find.text('4–6 tablespoons ice water'), findsOneWidget);
      // Still only the host's own basis row.
      expect(find.text('Per-serving basis'), findsOneWidget);
    });

    testWidgets('a library child (blueberry-pie|0) opens with no ?section=', (
      t,
    ) async {
      final routes = await _page(
        t,
        slug: 'blueberry-pie',
        bodies: {
          _matches('blueberry-pie'): golden('nutrition_matches_subrecipe'),
          _label('blueberry-pie'): golden('nutrition_subrecipe'),
        },
        parent: (title: 'Blueberry Pie', hasSections: false),
        isAdmin: false,
      );
      await _tap(t, find.text("Open the recipe's matches"));
      expect(
        routes.gets,
        contains(_matches('all-butter-double-crust-pie-dough')),
      );
      expect(routes.gets.where((g) => g.contains('?section=')), isEmpty);
    });
  });

  group('the held-missing note after a retitle (S15 (a))', () {
    testWidgets('an own section names the recipe in hand', (t) async {
      await _page(
        t,
        slug: 'chraime',
        bodies: _chraimeBodies(_retitled('nutrition_matches_section_own', 7)),
        parent: _chraime,
      );
      expect(find.text('choose recipe'), findsOneWidget);
      expect(
        find.text(
          'Made from another recipe: Tabil is no longer a section of Chraime '
          '— choose again',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('no library recipe is titled'), findsNothing);
    });

    testWidgets("another host's section names its host", (t) async {
      await _page(
        t,
        slug: 'pumpkin-pie',
        bodies: _pumpkinBodies(_retitled('nutrition_matches_section_other', 0)),
        parent: _pumpkin,
      );
      expect(
        find.text(
          'Made from another recipe: Basic Single-Crust Pie Dough is no '
          'longer a section of Basic Double-Crust Pie Dough — choose again',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a library child keeps the shipped missing note', (t) async {
      final body = _copy('nutrition_matches_choose_recipe');
      await _page(
        t,
        slug: 'free-form-apple-tart',
        bodies: {
          _matches('free-form-apple-tart'): body,
          _label('free-form-apple-tart'): golden('nutrition_choose_recipe'),
        },
        parent: (title: 'Free-Form Apple Tart', hasSections: false),
      );
      expect(
        find.textContaining(
          'Made from another recipe: no library recipe is titled "Rustic '
          'Tart Dough"',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('no longer a section'), findsNothing);
    });

    testWidgets("the queue pane names the line's recipe", (t) async {
      _size(t);
      // SYNTHESIZED (3): the tart's real held-missing row, as its own
      // section's retitled pick.
      final body = _copy('nutrition_matches_choose_recipe');
      (_item(body, 5)['match']! as Map<String, dynamic>)['child']
        ..['section'] = 'Rustic Tart Dough'
        ..['slug'] = 'free-form-apple-tart'
        ..['title'] = 'Rustic Tart Dough';
      final routes = _Routes({
        '/api/v1/admin/nutrition_review': golden(
          'nutrition_review_choose_recipe',
        ),
        _matches('free-form-apple-tart'): body,
      }, put: body);
      await t.pumpWidget(
        _app(
          routes,
          BlocProvider(
            create: (context) =>
                NutritionReviewCubit(context.read<RecipeRepository>())..load(),
            child: const Scaffold(body: NutritionReviewQueue()),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text(
          'Made from another recipe: Rustic Tart Dough is no longer a section '
          'of Free-Form Apple Tart — choose again',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the guided flow names the recipe in hand', (t) async {
      await _page(
        t,
        slug: 'chraime',
        bodies: _chraimeBodies(_retitled('nutrition_matches_section_own', 7)),
        parent: _chraime,
      );
      await _tap(t, find.textContaining('Guided ('));
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_GuidedFlow',
          ),
          matching: find.text(
            'Made from another recipe: Tabil is no longer a section of '
            'Chraime — choose again',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  test("a section line's queue key is not its host line's", () {
    // SYNTHESIZED (6): the same item with no section.
    final item =
        (golden('nutrition_review_section')['items']! as List).first
            as Map<String, dynamic>;
    final section = NutritionReviewLine.fromJson(item);
    final own = NutritionReviewLine.fromJson({...item, 'section': null});
    expect(section.key, isNot(own.key));
    expect(own.key, 'grilled-glazed-pork-tenderloin-roast#1');
  });

  testWidgets('the queue: a section line reads "{host} · {section}"; its '
      'pane reads and decides with ?section=', (t) async {
    _size(t);
    const host = 'grilled-glazed-pork-tenderloin-roast';
    // SYNTHESIZED (5): the section's matches, the queue line's text on a
    // real row of another section's matches body.
    final section = _copy('nutrition_section_matches');
    _item(section, 1)['raw'] = '1 tablespoon red curry paste';
    final routes = _Routes({
      '/api/v1/admin/nutrition_review': golden('nutrition_review_section'),
      '${_matches(host)}?section=Satay%20Glaze': section,
    }, put: section);
    await t.pumpWidget(
      _app(
        routes,
        BlocProvider(
          create: (context) =>
              NutritionReviewCubit(context.read<RecipeRepository>())..load(),
          child: const Scaffold(body: NutritionReviewQueue()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text('Grilled Glazed Pork Tenderloin Roast · Satay Glaze · line 1'),
      findsOneWidget,
    );
    // The other lines keep their recipe alone.
    expect(find.text('Sourdough Starter · line 1'), findsOneWidget);
    expect(
      find.text(
        'Grilled Glazed Pork Tenderloin Roast · Satay Glaze · ingredient '
        'line 1',
      ),
      findsOneWidget,
    );
    expect(routes.gets, contains('${_matches(host)}?section=Satay%20Glaze'));
    await _tap(t, find.text('Skip').first);
    expect(routes.puts, hasLength(1));
    expect(
      routes.puts.single.path,
      '${_matches(host)}/1?section=Satay%20Glaze',
    );
    expect(routes.puts.single.body, {
      'raw': '1 tablespoon red curry paste',
      'skipped': true,
    });
    // The label refresh after the decision is the section's, never the
    // host's.
    expect(routes.gets, contains('${_label(host)}?section=Satay%20Glaze'));
    expect(routes.gets, isNot(contains(_label(host))));
  });

  // The pane's cubit holds the SECTION's lines (`?section=`), so every
  // text of the pane that names the recipe those lines belong to names the
  // section, never its host (the fixer's B4).
  group('the queue pane on a section line names the section', () {
    const host = 'grilled-glazed-pork-tenderloin-roast';

    /// The real Satay Glaze item in [bucket], its pane row (SYNTHESIZED
    /// (5)'s) edited by [edit], opened in the queue.
    Future<void> pane(
      WidgetTester t,
      String bucket,
      void Function(Map<String, dynamic> row) edit,
    ) async {
      _size(t);
      final queue = _copy('nutrition_review_section');
      ((queue['items']! as List).first as Map<String, dynamic>)['bucket'] =
          bucket;
      final section = _copy('nutrition_section_matches');
      edit(_item(section, 1)..['raw'] = '1 tablespoon red curry paste');
      final routes = _Routes({
        '/api/v1/admin/nutrition_review': queue,
        '${_matches(host)}?section=Satay%20Glaze': section,
      }, put: section);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(
        _app(
          routes,
          BlocProvider(
            create: (context) =>
                NutritionReviewCubit(context.read<RecipeRepository>())..load(),
            child: const Scaffold(body: NutritionReviewQueue()),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('No grams: the confirm finishes the section', (t) async {
      // SYNTHESIZED (10): the section's only open line, in No grams.
      await pane(t, 'no_grams', (row) {
        (row['match']! as Map<String, dynamic>)
          ..['grams'] = null
          ..['gram_source'] = null
          ..['gram_basis'] = null;
      });
      expect(
        find.textContaining(
          "This is the recipe's only open line, so this confirm finishes "
          'Satay Glaze.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('finishes Grilled Glazed Pork Tenderloin Roast'),
        findsNothing,
      );
    });

    testWidgets("a reference line: the own-section group's empty text", (
      t,
    ) async {
      // SYNTHESIZED (11): the tart's real held-missing reference row.
      final tart = _item(_copy('nutrition_matches_choose_recipe'), 5);
      await pane(t, 'choose_recipe', (row) => row['match'] = tart['match']);
      expect(
        find.text('Satay Glaze has no section named "Rustic Tart Dough".'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Grilled Glazed Pork Tenderloin Roast has no'),
        findsNothing,
      );
    });

    testWidgets('a credited section group: the section still waits', (t) async {
      // SYNTHESIZED (12): a section group of two lines finishing one recipe.
      final item =
          (golden('nutrition_review_section')['items']! as List).first
              as Map<String, dynamic>;
      final section = _copy('nutrition_section_matches');
      IngredientMatch row(int position) =>
          IngredientMatch.fromJson(_item(section, position));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(
        _app(
          _Routes({}),
          Scaffold(
            body: FinishesSplit(
              line: NutritionReviewLine.fromJson({
                ...item,
                'lines': 2,
                'finishes': 1,
              }),
              match: row(1),
              waiting: [row(0)],
            ),
          ),
        ),
      );
      expect(
        find.textContaining(
          ' Satay Glaze still waits on 1¼ cups (6¼ ounces) unbleached',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Grilled Glazed Pork Tenderloin Roast still'),
        findsNothing,
      );
    });
  });

  group("a section's cubit keeps ?section= on every follow-up", () {
    NutritionCubit sectionCubit(_Routes routes) => NutritionCubit(
      NutritionRepository(
        Dio(BaseOptions(baseUrl: 'http://contract'))
          ..httpClientAdapter = routes,
      ),
      _dough,
      section: 'Basic Single-Crust Pie Dough',
    );

    test("a line_moved refusal refetches the SECTION's rows", () async {
      final routes = _Routes(
        {
          '${_matches(_dough)}$_sectionQuery': golden(
            'nutrition_section_matches',
          ),
        },
        put: {
          'error': {
            'code': 'line_moved',
            'message': 'That line has moved since it was read.',
            'request_id': 'req-test',
            'position': null,
          },
        },
        putStatus: 409,
      );
      final cubit = sectionCubit(routes);
      await cubit.loadMatches();
      await cubit.override(1, raw: '1 tablespoon sugar', skipped: true);
      await pumpEventQueue();
      expect(routes.puts.single.path, '${_matches(_dough)}/1$_sectionQuery');
      expect(cubit.state.error, contains('moved'));
      expect(routes.gets, [
        '${_matches(_dough)}$_sectionQuery',
        '${_matches(_dough)}$_sectionQuery',
      ]);
      await cubit.close();
    });

    test(
      'the apply-to-all offer on a section line PUTs with ?section=',
      () async {
        // SYNTHESIZED (7): the line's reach.
        final put = _copy('nutrition_section_matches');
        _item(put, 1)
          ..['others'] = 3
          ..['others_lines'] = 3;
        final routes = _Routes({
          '${_matches(_dough)}$_sectionQuery': golden(
            'nutrition_section_matches',
          ),
          '${_label(_dough)}$_sectionQuery': golden('nutrition_section_label'),
        }, put: put);
        final cubit = sectionCubit(routes);
        await cubit.loadMatches();
        await cubit.override(1, raw: '1 tablespoon sugar', confirmed: true);
        await pumpEventQueue();
        expect(cubit.state.offer, isNotNull);
        await cubit.applyToAll();
        await pumpEventQueue();
        expect(routes.puts, hasLength(2));
        expect(routes.puts.last.path, '${_matches(_dough)}/1$_sectionQuery');
        expect((routes.puts.last.body! as Map)['apply_to_all'], isTrue);
        await cubit.close();
      },
    );

    test("a re-attached compute reloads the SECTION's label", () async {
      // SYNTHESIZED (8): a compute in flight on the section, then done.
      final label = _copy('nutrition_section_label')..['computing_job_id'] = 7;
      final routes = _Routes({
        '${_label(_dough)}$_sectionQuery': label,
        '/api/v1/nutrition/jobs/7': {
          'id': 7,
          'status': 'done',
          'total': 1,
          'done': 1,
          'failed': 0,
          'log': <String>[],
        },
      });
      final cubit = sectionCubit(routes);
      await cubit.load();
      // The cubit polls the job every 1.2 s; wait (bounded) for its reload.
      List<String> labels() =>
          routes.gets.where((g) => g.startsWith(_label(_dough))).toList();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (labels().length < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(labels(), [
        '${_label(_dough)}$_sectionQuery',
        '${_label(_dough)}$_sectionQuery',
      ]);
      await cubit.close();
    });
  });
}
