// Matcher v41 — the composite row in the app (the approved mockup
// docs/mockups/v40-composite-rows.html; design_v3 §2.4; api_app §12).
//
// Real data only: every body is a shipped contract golden — real corpus
// lines through the real server routes (Blueberry Pie 0979 routed on
// All-Butter Double-Crust Pie Dough; Free-Form Apple Tart 1005 held
// choose_recipe; the rules sample's rendered bacon) — served through a
// Dio adapter, so the repositories, the cubits and the widgets all run.
// The recipe titles a review sheet is opened with are the corpus titles,
// as the detail page passes them. SYNTHESIZED (a stated exception, the
// hold_actions_parity_test precedent): no golden carries a
// `discarded_recipe` marinade (the corpus holds three), so the held tart's
// own row stands in with that hold put on it. Likewise no golden child
// has a yield read in cups, so the share-unit pin puts the corpus's "1½
// cups" shape on Blueberry Pie's own routed row (verifier round 1, D1).
// And no golden routed row has another line waiting on its item, so the
// apply-offer pin puts others / others_lines 3 on Blueberry Pie's routed
// row, as the server's own v41 API pin reads that row after its seed.
// No golden carries a NOT-ROUTED reference row (v42's row note), so the held
// tart's reference item is replaced by the real wire shape the server's own
// matches builder (matchesBody, FixtureProvider) gives two real lines:
// Restaurant-Style Herb Sauce 0184's "1 recipe Pan-Seared Steaks (this
// page)" (served_with) and Pumpkin Pie 0987's "1 recipe Basic Single-Crust
// Pie Dough (this page), …" with 0972 in the library (section).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart' show HoldDecision;

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/admin/nutrition_review_cubit.dart';
import 'package:salt_app/features/admin/nutrition_review_queue.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/nutrition_label.dart';
import 'package:salt_app/features/nutrition/recipe_fix_panel.dart';
import 'package:salt_app/features/nutrition/review_sheet.dart';

import 'support/contract_goldens.dart';

/// Answers each route with its golden and records every PUT body.
class _Routes implements HttpClientAdapter {
  _Routes({required this.matches, this.label, this.review, this.refuse});

  final Map<String, dynamic> matches;
  final Map<String, dynamic>? label;
  final Map<String, dynamic>? review;

  /// When set, every PUT is refused with a 422 envelope carrying it.
  final String? refuse;
  final List<Object?> puts = [];
  final List<Uri> gets = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (options.method == 'GET') {
      gets.add(options.uri);
    }
    final Object? body;
    if (options.method == 'PUT' && refuse != null) {
      puts.add(options.data);
      return ResponseBody.fromString(
        jsonEncode({
          'error': {'code': 'validation', 'message': refuse},
        }),
        422,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    } else if (options.method == 'PUT') {
      puts.add(options.data);
      body = matches;
    } else if (path.contains('/admin/nutrition_review')) {
      body = review;
    } else if (path.endsWith('/nutrition/matches')) {
      body = matches;
    } else if (path.endsWith('/nutrition')) {
      body = label ?? {'status': 'none'};
    } else {
      body = golden('recipes_search');
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

const ReviewParent _pie = (title: 'Blueberry Pie', hasSections: false);
const ReviewParent _tart = (title: 'Free-Form Apple Tart', hasSections: false);

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

/// The recipe page's label for [label] / [matches]; [open] taps its badge
/// open, as a person does.
Future<_Routes> _page(
  WidgetTester tester, {
  required String matches,
  required String label,
  required ReviewParent parent,
  bool isAdmin = true,
  bool open = true,
  void Function(Map<String, dynamic> match)? edit,
  String self = 'slug',
  String? refuse,
  int others = 0,
  Map<String, dynamic>? body,
}) async {
  _size(tester);
  final routes = _Routes(
    matches:
        body ??
        (edit == null && others == 0
            ? golden(matches)
            : _edited(matches, edit ?? (_) {}, others: others)),
    label: golden(label),
    refuse: refuse,
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    _app(
      routes,
      BlocProvider(
        create: (context) =>
            NutritionCubit(context.read<NutritionRepository>(), self)..load(),
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
  await tester.pumpAndSettle();
  if (open) {
    await tester.tap(find.textContaining('ingredients matched'));
    await tester.pumpAndSettle();
  }
  return routes;
}

/// [name]'s golden with [edit] applied to its reference line's match (the
/// one row carrying a child; a deep copy, the golden is left as shipped),
/// and [others] lines in as many recipes waiting on its item when > 0.
Map<String, dynamic> _edited(
  String name,
  void Function(Map<String, dynamic> match) edit, {
  int others = 0,
}) {
  final body = jsonDecode(jsonEncode(golden(name))) as Map<String, dynamic>;
  for (final item in (body['items']! as List).cast<Map<String, dynamic>>()) {
    if (item['match'] case {'child': final Map<String, dynamic> _} && final m) {
      edit(m as Map<String, dynamic>);
      if (others > 0) {
        item['others'] = others;
        item['others_lines'] = others;
      }
    }
  }
  return body;
}

/// The marinade stand-in: the held tart's row with the reference hold of
/// a poured-away marinade put on it.
void _marinade(Map<String, dynamic> match) {
  match['hold'] = 'discarded_recipe';
  match['child'] = {
    ...match['child']! as Map<String, dynamic>,
    'reason': 'marinade',
  };
}

/// The held tart's golden with its reference item replaced by a real
/// not-routed line's wire shape ([raw], [item], the child's [reason],
/// [name], [kind], [parentKind] and [candidates]), as the server's
/// matchesBody emits it.
Map<String, dynamic> _notRouted({
  required String raw,
  required String item,
  required String reason,
  required String name,
  required String kind,
  required String parentKind,
  required List<Map<String, Object?>> candidates,
}) {
  final body =
      jsonDecode(jsonEncode(golden('nutrition_matches_choose_recipe')))
          as Map<String, dynamic>;
  final row = (body['items']! as List).cast<Map<String, dynamic>>().singleWhere(
    (i) => (i['match'] as Map?)?['child'] != null,
  );
  row
    ..['raw'] = raw
    ..['item'] = item
    ..['line_amount'] = '1 recipe'
    ..['match'] = {
      'fdc_id': null,
      'description':
          'Sub-recipe — made from its own recipe, not counted in these totals',
      'data_type': null,
      'confidence': 1.0,
      'grams': 0.0,
      'gram_source': 'unmeasured',
      'gram_basis': 'a sub-recipe — counted as 0 g',
      'status': 'confirmed',
      'hold': null,
      'hold_note': null,
      'carried_from': null,
      'child': {
        'state': 'not_routed',
        'reason': reason,
        'name': name,
        'slug': null,
        'title': null,
        'share_text': '1',
        'default': false,
        'why': 'none',
        'yield_text': null,
        'share': 1.0,
        'yield_units': <Object?>[],
        'grams': 0.0,
        'kcal': null,
        'kcal_per_serving': null,
        'status': null,
        'matched_count': null,
        'total_count': null,
        'kind': kind,
        'parent_kind': parentKind,
        'candidates': candidates,
      },
      'parts': <Object?>[],
      'flag': null,
    };
  return body;
}

const _notRoutedNotes = [
  'Its section has no totals yet — not counted',
  'Served with this recipe, not made from it — not counted',
  'No amount on the line — not counted',
  'No share the yield can read — not counted',
];

UnitToggle _toggle(WidgetTester t) =>
    t.widget<UnitToggle>(_inPanel(find.byType(UnitToggle)));

/// Scrolls [finder] into the sheet's view, then taps it (a tap off the
/// dialog would dismiss it).
Future<void> _tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Finder _inPanel(Finder finder) =>
    find.descendant(of: find.byType(RecipeFixPanel), matching: finder);

Finder get _primaries => _inPanel(
  find.byWidgetPredicate(
    (w) => w is FButton && w.variant == FButtonVariant.primary,
  ),
);

FButton _button(String label) =>
    find
            .ancestor(of: find.text(label), matching: find.byType(FButton))
            .evaluate()
            .first
            .widget
        as FButton;

const _pieRaw = '1 recipe double-crust pie dough';
const _tartRaw =
    '1 recipe Rustic Tart Dough (this page), rolled into a 12-inch circle '
    'and chilled';
// The recipes_search golden's one result.
const _gemelli =
    'brown-butter-gemelli-with-asparagus-walnuts-and-lemony-ricotta';
const _gemelliTitle =
    'Brown Butter Gemelli with Asparagus, Walnuts, and Lemony Ricotta';

/// Types [term] into the recipe panel's library search and runs it.
Future<void> _search(WidgetTester t, String term) async {
  final field = _inPanel(
    find.descendant(
      of: find.byType(SearchRow),
      matching: find.byType(EditableText),
    ),
  );
  await t.ensureVisible(field);
  await t.enterText(field, term);
  await _tap(t, _inPanel(find.text('Search')));
}

const _flag =
    'approximation (the first dough the note names: All-Butter Double-Crust '
    'Pie Dough)';

void main() {
  group('the routed row (Blueberry Pie, 0979)', () {
    testWidgets('admin: the label, the row, Change and the link', (t) async {
      await _page(
        t,
        matches: 'nutrition_matches_subrecipe',
        label: 'nutrition_subrecipe',
        parent: _pie,
      );
      // The label: the golden's 571.51 kcal, and what it includes.
      expect(find.text('572'), findsOneWidget);
      expect(
        find.text(
          'Includes 1 recipe: All-Butter Double-Crust Pie Dough '
          '(approximation)',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('10 lines · 10 counting, 1 of them from a recipe'),
        findsOneWidget,
      );
      expect(
        find.text('made from the recipe All-Butter Double-Crust Pie Dough'),
        findsOneWidget,
      );
      expect(find.text('Recipe'), findsOneWidget);
      expect(find.text('· 1 recipe · 643 g · 3,057 kcal'), findsOneWidget);
      expect(
        find.text(
          'amount: from the recipe All-Butter Double-Crust Pie Dough: 643 g, '
          '3,057 kcal · +382 kcal per serving',
        ),
        findsOneWidget,
      );
      expect(find.text(_flag), findsOneWidget);
      // The flag on its own line, behind the flag glyph.
      expect(
        find.descendant(
          of: find.ancestor(of: find.text(_flag), matching: find.byType(Row)),
          matching: find.byIcon(FLucideIcons.flag),
        ),
        findsOneWidget,
      );
      expect(find.text('Change'), findsOneWidget);
      expect(find.text("Open the recipe's matches"), findsOneWidget);
      // Its Confirm and Skip live in the recipe panel, not on the bar:
      // the routed row's bar is Change and the link, nothing else.
      expect(find.text('Confirm (poured away)'), findsNothing);
      final bar = find.ancestor(
        of: find.text("Open the recipe's matches"),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ActionBar',
        ),
      );
      expect(bar, findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.text('Change')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('Skip')),
        findsNothing,
      );
      expect(
        find.descendant(of: bar, matching: find.textContaining('Confirm')),
        findsNothing,
      );
      // No food fix on a routed row.
      expect(find.text('Adjust…'), findsNWidgets(9));
    });

    testWidgets('member: the link, the flag and Includes — no Change', (
      t,
    ) async {
      await _page(
        t,
        matches: 'nutrition_matches_subrecipe',
        label: 'nutrition_subrecipe',
        parent: _pie,
        isAdmin: false,
      );
      expect(
        find.text(
          'Includes 1 recipe: All-Butter Double-Crust Pie Dough '
          '(approximation)',
        ),
        findsOneWidget,
      );
      expect(find.text(_flag), findsOneWidget);
      expect(find.text("Open the recipe's matches"), findsOneWidget);
      expect(find.text('Change'), findsNothing);
    });

    // v44 (S14 a): the matches GET lists only CHILD sections under
    // "Another recipe's section" — the dough's three non-child sections
    // left the golden, so the group shows its empty text; the
    // section-stages-nothing pin moves to step 8's section goldens.
    testWidgets('the fix sheet: groups, notes, calories; an unpickable '
        'recipe stages nothing', (t) async {
      await _page(
        t,
        matches: 'nutrition_matches_subrecipe',
        label: 'nutrition_subrecipe',
        parent: _pie,
      );
      await _tap(t, find.text('Change'));
      for (final text in [
        'Made from a recipe: counted with the first dough the note names. '
            'Change it if the pie uses another.',
        'Choose the recipe & set the share',
        "This recipe's sections",
        'Blueberry Pie has no section named "double-crust pie dough".',
        'Library recipes the note names',
        'Other library recipes with a similar title',
        "Another recipe's section",
        'No section is titled "double-crust pie dough".',
        'current · default',
        '3,057 kcal · +382 / serving',
        '3,520 kcal · +440 / serving',
        '3,649 kcal · +456 / serving',
        'The line says "1 recipe". All-Butter Double-Crust Pie Dough makes '
            'enough for one 9-inch pie, so the share is 1.',
        'Share',
      ]) {
        expect(_inPanel(find.text(text)), findsOneWidget, reason: text);
      }
      for (final note in [
        'named first',
        'named second',
        'named third',
        'not named in the note',
      ]) {
        expect(
          _inPanel(find.textContaining(note)),
          findsOneWidget,
          reason: note,
        );
      }
      expect(_inPanel(find.text('phase 2 · no totals yet')), findsNothing);
      // The groups in resolution order, top to bottom.
      final tops = [
        for (final caption in [
          "This recipe's sections",
          'Library recipes the note names',
          'Other library recipes with a similar title',
          "Another recipe's section",
        ])
          t.getTopLeft(_inPanel(find.text(caption))).dy,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: 'caption $i');
      }
      // Not the plain group: the note names its titles.
      expect(_inPanel(find.text('Library recipes')), findsNothing);
      expect(
        _inPanel(find.text('Search the library for another recipe…')),
        findsOneWidget,
      );
      // The share offers only the child's yield units: [recipe].
      expect(_toggle(t).units, ['recipe']);
      // A library recipe with no totals (pickable false) stages nothing.
      await _tap(
        t,
        _inPanel(find.text('Foolproof All-Butter Dough for Double-Crust Pie')),
      );
      expect(
        _inPanel(find.text('Confirm · All-Butter, 1 recipe')),
        findsOneWidget,
      );
    });

    testWidgets('a share typed in a unit of the old yield never rides a '
        'pick: the field and the unit go back to the line', (t) async {
      final routes = await _page(
        t,
        matches: 'nutrition_matches_subrecipe',
        label: 'nutrition_subrecipe',
        parent: _pie,
        edit: (match) => (match['child']! as Map)['yield_units'] = [
          {'unit': 'recipe', 'per_recipe': 1},
          {'unit': 'cup', 'per_recipe': 1.5},
        ],
      );
      await _tap(t, find.text('Change'));
      expect(_toggle(t).units, ['recipe', 'cup']);
      await _tap(t, _inPanel(find.text('cup')));
      expect(_inPanel(find.text('Save share · 1 cup')), findsOneWidget);
      await _tap(t, _inPanel(find.text('Basic Double-Crust Pie Dough')));
      expect(_toggle(t).units, ['recipe']);
      expect(_toggle(t).unit, 'recipe');
      expect(_primaries, findsOneWidget);
      await _tap(t, _inPanel(find.text('Use this recipe · 1 recipe')));
      expect(routes.puts, [
        {'raw': _pieRaw, 'child': 'basic-double-crust-pie-dough'},
      ]);
    });

    testWidgets('ONE primary button follows the pick and the share; the PUT '
        'bodies', (t) async {
      final routes = await _page(
        t,
        matches: 'nutrition_matches_subrecipe',
        label: 'nutrition_subrecipe',
        parent: _pie,
      );
      await _tap(t, find.text('Change'));
      expect(_primaries, findsOneWidget);
      expect(
        _inPanel(find.text('Confirm · All-Butter, 1 recipe')),
        findsOneWidget,
      );
      await _tap(t, _inPanel(find.text('Basic Double-Crust Pie Dough')));
      expect(_primaries, findsOneWidget);
      await _tap(t, _inPanel(find.text('Use this recipe · 1 recipe')));
      // The save landed: the panel closed on it (observed, never assumed).
      expect(find.byType(RecipeFixPanel), findsNothing);

      await _tap(t, find.text('Change'));
      await _tap(t, _inPanel(find.text('All-Butter Double-Crust Pie Dough')));
      await t.enterText(_inPanel(find.byType(EditableText)).last, '½');
      await t.pumpAndSettle();
      expect(_primaries, findsOneWidget);
      await _tap(t, _inPanel(find.text('Save share · ½ recipe')));

      await _tap(t, find.text('Change'));
      expect(_primaries, findsOneWidget);
      await _tap(t, _inPanel(find.text('Confirm · All-Butter, 1 recipe')));

      expect(routes.puts, [
        {'raw': _pieRaw, 'child': 'basic-double-crust-pie-dough'},
        {
          'raw': _pieRaw,
          'child': 'all-butter-double-crust-pie-dough',
          'share': 0.5,
        },
        {'raw': _pieRaw, 'confirmed': true},
      ]);
    });

    testWidgets('a refused pick keeps the recipe panel open and says why', (
      t,
    ) async {
      const refusal = 'That recipe has no totals yet — compute it first.';
      final routes = await _page(
        t,
        matches: 'nutrition_matches_subrecipe',
        label: 'nutrition_subrecipe',
        parent: _pie,
        refuse: refusal,
      );
      await _tap(t, find.text('Change'));
      await _tap(t, _inPanel(find.text('Basic Double-Crust Pie Dough')));
      await _tap(t, _inPanel(find.text('Use this recipe · 1 recipe')));
      expect(routes.puts, [
        {'raw': _pieRaw, 'child': 'basic-double-crust-pie-dough'},
      ]);
      expect(find.byType(RecipeFixPanel), findsOneWidget);
      // The sheet's error strip (and the page's own, behind it).
      expect(find.text(refusal), findsWidgets);
    });

    testWidgets('a recipe pick on a routed row offers apply-to-all; the '
        'resend carries the recipe', (t) async {
      final routes = await _page(
        t,
        matches: 'nutrition_matches_subrecipe',
        label: 'nutrition_subrecipe',
        parent: _pie,
        others: 3,
      );
      await _tap(t, find.text('Change'));
      await _tap(t, _inPanel(find.text('Basic Double-Crust Pie Dough')));
      await _tap(t, _inPanel(find.text('Use this recipe · 1 recipe')));
      expect(
        find.text(
          '3 other lines of double-crust pie dough, in 3 recipes, are still '
          'waiting on this decision.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // The mockup's recipe footer (verify3 O6), never the food wording.
      expect(
        find.text(
          'Sets this recipe on their undecided "double-crust pie dough" '
          'lines, each keeping its own share, and recomputes their labels. '
          'Lines someone already decided are left alone.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Sets this food'), findsNothing);
      await _tap(t, find.text('Apply to 3 lines'));
      expect(routes.puts, [
        {'raw': _pieRaw, 'child': 'basic-double-crust-pie-dough'},
        {
          'raw': _pieRaw,
          'child': 'basic-double-crust-pie-dough',
          'apply_to_all': true,
        },
      ]);
    });

    testWidgets('a Confirm on a routed row offers apply-to-all with the '
        'recipe footer; the resend is the confirm (verify5 D1)', (t) async {
      final routes = await _page(
        t,
        matches: 'nutrition_matches_subrecipe',
        label: 'nutrition_subrecipe',
        parent: _pie,
        others: 3,
      );
      await _tap(t, find.text('Change'));
      await _tap(t, _inPanel(find.text('Confirm · All-Butter, 1 recipe')));
      expect(find.text('Apply to 3 lines'), findsOneWidget);
      expect(
        find.text(
          'Sets this recipe on their undecided "double-crust pie dough" '
          'lines, each keeping its own share, and recomputes their labels. '
          'Lines someone already decided are left alone.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Sets this food'), findsNothing);
      await _tap(t, find.text('Apply to 3 lines'));
      expect(routes.puts, [
        {'raw': _pieRaw, 'confirmed': true},
        {'raw': _pieRaw, 'confirmed': true, 'apply_to_all': true},
      ]);
    });
  });

  group('the held row (Free-Form Apple Tart, 1005)', () {
    testWidgets('the label says what is missing; the row and its sheet', (
      t,
    ) async {
      await _page(
        t,
        matches: 'nutrition_matches_choose_recipe',
        label: 'nutrition_choose_recipe',
        parent: _tart,
        open: false,
      );
      expect(
        find.text(
          'Partial: Rustic Tart Dough is not counted (no recipe chosen).',
        ),
        findsOneWidget,
      );
      expect(find.text('5/6 ingredients matched — review'), findsOneWidget);
      expect(find.textContaining('Includes'), findsNothing);
      await t.tap(find.textContaining('ingredients matched'));
      await t.pumpAndSettle();

      expect(find.text('choose recipe'), findsOneWidget);
      expect(
        find.text(
          'Made from another recipe: no library recipe is titled "Rustic '
          'Tart Dough" — held out of the totals. Pick the recipe it means, '
          'or skip the line',
        ),
        findsOneWidget,
      );
      expect(find.text('no recipe chosen · 1 recipe · 0 g'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      // Only a poured-away marinade confirms without a recipe.
      expect(find.text('Confirm (poured away)'), findsNothing);
      await _tap(t, find.text('Choose a recipe'));
      for (final text in [
        'Free-Form Apple Tart has no section named "Rustic Tart Dough".',
        'No recipe is titled "Rustic Tart Dough".',
        'No section is titled "Rustic Tart Dough".',
        'Enabled once a recipe is picked.',
        'Search the library for another recipe…',
      ]) {
        expect(_inPanel(find.text(text)), findsOneWidget, reason: text);
      }
      expect(_primaries, findsOneWidget);
      expect(_button('Use this recipe').onPress, isNull);
      // No default: no why line, no share sentence.
      expect(_inPanel(find.textContaining('the note names')), findsNothing);
      expect(_inPanel(find.textContaining('The line says')), findsNothing);
    });

    testWidgets('a poured-away marinade offers Skip, Confirm and a recipe — '
        'and is not the medium card', (t) async {
      final item =
          (_edited('nutrition_matches_choose_recipe', _marinade)['items']!
                      as List)
                  .last
              as Map<String, dynamic>;
      final marinade = IngredientMatch.fromJson(item);
      expect(offeredOn(marinade), {
        HoldDecision.skip,
        HoldDecision.confirm,
        HoldDecision.recipe,
      });
      expect(isHeldLine(marinade), isFalse);
      expect(matchBucketOf(marinade), MatchBucket.check);
      // Drawn: the three actions, and not the poured-away/edible-grams card.
      final routes = await _page(
        t,
        matches: 'nutrition_matches_choose_recipe',
        label: 'nutrition_choose_recipe',
        parent: _tart,
        edit: _marinade,
      );
      for (final label in [
        'Choose a recipe',
        'Confirm (poured away)',
        'Skip',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text(heldSkipLabel), findsNothing);
      expect(find.text('Enter edible grams'), findsNothing);
      // The recipe panel — the one every host draws (the sheet, the guided
      // flow, the queue pane) — confirms it with nothing picked; the bar
      // drops its own Confirm while the panel is open.
      await _tap(t, find.text('Choose a recipe'));
      expect(find.text('Confirm (poured away)'), findsOneWidget);
      expect(_primaries, findsOneWidget);
      expect(
        _inPanel(find.text('Enabled once a recipe is picked.')),
        findsNothing,
      );
      await _tap(t, _inPanel(find.text('Confirm (poured away)')));
      expect(routes.puts, [
        {'raw': _tartRaw, 'confirmed': true},
      ]);
    });

    testWidgets('the library search: the title query, one label read per '
        'result, the pick', (t) async {
      final routes = await _page(
        t,
        matches: 'nutrition_matches_choose_recipe',
        label: 'nutrition_choose_recipe',
        parent: _tart,
      );
      await _tap(t, find.text('Choose a recipe'));
      await _search(t, 'tart "dough');
      final search = routes.gets.singleWhere(
        (uri) => uri.path == '/api/v1/recipes',
      );
      expect(search.queryParameters, {
        'page': '1',
        'limit': '10',
        'q': 'title:"tart  dough"',
      });
      // One label read for the one result (after the page's own).
      expect(
        routes.gets.where((uri) => uri.path.endsWith('/nutrition')).last.path,
        '/api/v1/recipes/$_gemelli/nutrition',
      );
      expect(_inPanel(find.text('search result · 2')), findsOneWidget);
      await _tap(t, _inPanel(find.text(_gemelliTitle)));
      expect(_primaries, findsOneWidget);
      await _tap(t, _inPanel(find.text('Use this recipe · 1 recipe')));
      expect(routes.puts, [
        {'raw': _tartRaw, 'child': _gemelli},
      ]);
    });

    testWidgets('the library search never offers the recipe itself', (t) async {
      await _page(
        t,
        matches: 'nutrition_matches_choose_recipe',
        label: 'nutrition_choose_recipe',
        parent: _tart,
        self: _gemelli,
      );
      await _tap(t, find.text('Choose a recipe'));
      await _search(t, 'gemelli');
      expect(_inPanel(find.text(_gemelliTitle)), findsNothing);
      expect(_inPanel(find.textContaining('search result')), findsNothing);
    });
  });

  group('the action table on every row', () {
    test('a routed row offers its table row; a food row never a recipe', () {
      final rows = [
        for (final item
            in golden('nutrition_matches_subrecipe')['items'] as List)
          IngredientMatch.fromJson(item as Map<String, dynamic>),
      ];
      expect(offeredOn(rows.first), {
        HoldDecision.skip,
        HoldDecision.confirm,
        HoldDecision.recipe,
      });
      // blueberry-pie|2 "6 cups (30 ounces) fresh blueberries", auto.
      expect(offers(rows[2], HoldDecision.recipe), isFalse);
    });
  });

  testWidgets('the rendered bacon: one row, two records, Change', (t) async {
    _size(t);
    final routes = _Routes(matches: golden('nutrition_matches_rules'));
    await t.pumpWidget(
      _app(
        routes,
        BlocProvider(
          create: (context) => NutritionCubit(
            context.read<NutritionRepository>(),
            'nutrition-rules-sample',
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FButton(
                  onPress: () => showReviewSheet(context, isAdmin: true),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Counted — looks good'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await _tap(t, find.text('Counted — looks good'));
    await t.scrollUntilVisible(
      find.text(
        'amount: 284 g raw → 94 g cooked bacon + 39 g bacon grease kept in '
        'the pan',
      ),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    // The wilted spinach's bacon (13) and the sample's pancetta (11).
    expect(
      find.text('matched to two records, cooked and drained:'),
      findsNWidgets(2),
    );
    expect(
      // Matcher v51 (M49): AH-102 item 1981's 0.33 (was 114 g).
      find.text('94 g · Pork, cured, bacon, pre-sliced, cooked, pan-fried'),
      findsOneWidget,
    );
    expect(find.text('+ 39 g · Animal fat, bacon grease'), findsOneWidget);
    expect(find.text('· kept in the pan'), findsNWidgets(2));
    expect(
      find.text(
        'amount: 284 g raw → 94 g cooked bacon + 39 g bacon grease kept in '
        'the pan',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'approximate (USDA AH-102 item 1981: bacon, sliced, all methods → '
        'cooked 33 % (18–43))',
      ),
      findsNWidgets(2),
    );
    expect(find.text('Change'), findsNWidgets(2));
  });

  testWidgets('the queue: the Choose recipe chip and its slim row', (t) async {
    _size(t);
    final routes = _Routes(
      matches: golden('nutrition_matches_choose_recipe'),
      review: golden('nutrition_review_choose_recipe'),
    );
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
    expect(find.text('Choose recipe'), findsOneWidget);
    expect(find.text('choose recipe'), findsOneWidget);
    expect(find.text('no recipe chosen'), findsOneWidget);
    expect(
      find.textContaining('1 recipe · counts 0 g until a recipe is chosen'),
      findsOneWidget,
    );
    expect(
      find.text(
        'line hold (choose recipe): no library recipe has this title. Any '
        'decision finishes it: Choose a recipe, or Skip if the recipe is made '
        'without it.',
      ),
      findsOneWidget,
    );
    // The pane: the recipe panel, not the food one.
    expect(find.byType(RecipeFixPanel), findsOneWidget);
    expect(find.byType(FixPanel), findsNothing);
    await _tap(t, find.text('Choose recipe'));
    expect(find.textContaining('Showing choose recipe'), findsOneWidget);
  });

  testWidgets('the queue: a poured-away marinade is confirmed in its pane', (
    t,
  ) async {
    _size(t);
    // The marinade stand-in, as the queue lists it (bucket check, A5 a).
    final review =
        jsonDecode(jsonEncode(golden('nutrition_review_choose_recipe')))
            as Map<String, dynamic>;
    final item = (review['items']! as List).single as Map<String, dynamic>;
    item['bucket'] = 'check';
    _marinade(item['match']! as Map<String, dynamic>);
    final routes = _Routes(
      matches: _edited('nutrition_matches_choose_recipe', _marinade),
      review: review,
    );
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
        'line hold (discarded recipe): decided one line at a time, never '
        'offers apply-to-all. Any decision finishes it: Skip, Confirm '
        '(poured away) or Choose a recipe.',
      ),
      findsOneWidget,
    );
    // A Confirm finishes it: never "until a recipe is chosen".
    expect(find.textContaining('until a recipe is chosen'), findsNothing);
    expect(_primaries, findsOneWidget);
    await _tap(t, _inPanel(find.text('Confirm (poured away)')));
    expect(routes.puts, [
      {'raw': _tartRaw, 'confirmed': true},
    ]);
  });

  group('the not-routed row note (v42, Q2 (a))', () {
    testWidgets('served with: one line under the "not counted" badge', (
      t,
    ) async {
      await _page(
        t,
        matches: 'nutrition_matches_choose_recipe',
        label: 'nutrition_choose_recipe',
        parent: (
          title: 'Restaurant-Style Herb Sauce for Pan-Seared Steaks',
          hasSections: false,
        ),
        body: _notRouted(
          raw: '1 recipe Pan-Seared Steaks (this page)',
          item: 'Pan-Seared Steaks (this page)',
          reason: 'served_with',
          name: 'Pan-Seared Steaks',
          kind: 'steaks',
          parentKind: 'recipe',
          candidates: [
            {
              'group': 'library',
              'slug': 'pan-seared-steaks',
              'title': 'Pan-Seared Steaks',
              'note': null,
              'yield_text': 'SERVES 4',
              'kcal': null,
              'kcal_per_serving': null,
              'current': false,
              'default': false,
              'pickable': false,
              'host_title': null,
            },
          ],
        ),
      );
      final note = find.text(
        'Served with this recipe, not made from it — not counted',
      );
      expect(find.text('not counted'), findsOneWidget);
      expect(note, findsOneWidget);
      // Directly under the badge's row, the raw line's own row.
      final row = find.ancestor(
        of: find.text('1 recipe Pan-Seared Steaks (this page)'),
        matching: find.byType(Row),
      );
      expect(t.getTopLeft(note).dy, greaterThan(t.getBottomLeft(row).dy - 1));
      expect(t.getTopLeft(note).dy, lessThan(t.getBottomLeft(row).dy + 4));
      for (final other in _notRoutedNotes.where(
        (n) => !n.startsWith('Served'),
      )) {
        expect(find.text(other), findsNothing, reason: other);
      }
    });

    testWidgets('section: its own reason', (t) async {
      await _page(
        t,
        matches: 'nutrition_matches_choose_recipe',
        label: 'nutrition_choose_recipe',
        parent: (title: 'Pumpkin Pie', hasSections: false),
        body: _notRouted(
          raw:
              '1 recipe Basic Single-Crust Pie Dough (this page), fitted into '
              'a 9-inch pie plate and chilled',
          item: 'Basic Single-Crust Pie Dough (this page)',
          reason: 'section',
          name: 'Basic Single-Crust Pie Dough',
          kind: 'dough',
          parentKind: 'pie',
          candidates: [
            for (final title in [
              'Basic Single-Crust Pie Dough',
              'Hand Mixed Basic Single-Crust Pie Dough',
            ])
              {
                'group': 'other_section',
                'slug': null,
                'title': title,
                'note': 'a section of Basic Double-Crust Pie Dough',
                'yield_text': null,
                'kcal': null,
                'kcal_per_serving': null,
                'current': false,
                'default': false,
                'pickable': false,
                'host_title': 'Basic Double-Crust Pie Dough',
              },
          ],
        ),
      );
      expect(find.text('not counted'), findsOneWidget);
      expect(
        find.text('Its section has no totals yet — not counted'),
        findsOneWidget,
      );
      for (final other in _notRoutedNotes.where((n) => !n.startsWith('Its'))) {
        expect(find.text(other), findsNothing, reason: other);
      }
    });

    testWidgets('a routed row draws no such note', (t) async {
      await _page(
        t,
        matches: 'nutrition_matches_subrecipe',
        label: 'nutrition_subrecipe',
        parent: _pie,
      );
      expect(
        find.text('made from the recipe All-Butter Double-Crust Pie Dough'),
        findsOneWidget,
      );
      expect(find.text('not counted'), findsNothing);
      for (final note in _notRoutedNotes) {
        expect(find.text(note), findsNothing, reason: note);
      }
    });

    test('the four reasons in the brief\'s words; any other none', () {
      expect([
        for (final r in ['section', 'served_with', 'no_amount', 'no_share'])
          notRoutedNote(r),
      ], _notRoutedNotes);
      expect(notRoutedNote(null), isNull);
      expect(notRoutedNote('missing'), isNull);
    });
  });

  group('matcher v52 (M51): the served-with line', () {
    testWidgets('Pan-Seared Salmon: "Served with … — not counted." under the '
        'label, never a Partial line; the badge reads complete', (t) async {
      await _page(
        t,
        matches: 'nutrition_matches_wb',
        label: 'nutrition_served_with',
        parent: (title: 'Pan-Seared Salmon', hasSections: false),
        open: false,
      );
      expect(
        find.text('Served with Sweet-and-Sour Chutney — not counted.'),
        findsOneWidget,
      );
      expect(find.textContaining('Partial:'), findsNothing);
      expect(find.text('4/4 ingredients matched'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.circleCheck), findsOneWidget);
    });

    testWidgets('Panna Cotta: the whole batch included as an approximation, '
        'no served-with line', (t) async {
      await _page(
        t,
        matches: 'nutrition_matches_wb',
        label: 'nutrition_wb',
        parent: (title: 'Panna Cotta', hasSections: true),
        open: false,
      );
      expect(
        find.text('Includes 1 recipe: Raspberry Coulis (approximation)'),
        findsOneWidget,
      );
      expect(find.textContaining('Served with'), findsNothing);
      expect(find.textContaining('Partial:'), findsNothing);
    });
  });
}
