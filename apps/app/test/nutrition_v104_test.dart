// Matcher v104 (batch fix104) — the app half of Run 077/078's U15, U18,
// U19, U20.
//
// Real data: every body is a shipped contract golden (real corpus lines
// through the real server routes): Grill-Roasted Beer Can Chicken 0640's
// "3 tablespoons Spice Rub (recipe follows)" (nutrition_matches_staged_share,
// its own Spice Rub at 0.19 and Grilled Pork Chops 0598's "Basic Spice Rub
// for Pork Chops" at ¾), Pumpkin Pie 0987's dough line routed on 0972's
// "Basic Single-Crust Pie Dough" (nutrition_matches_section_other), the
// recipes page and the subrecipe label.
// SYNTHESIZED — disclosed (each as the fleets' probes did): (1) a staged
// candidate's share_text set to null (the GET's candidate whose route reads
// no share; no golden carries one); (2) the current child's share 0.001
// with share_text '<0.01' (the floor no golden carries); (3) the section
// cubit on Pumpkin Pie's real routed line (v103's disclosed shape: no
// golden serves a SECTION's own routed line); (4) a line shifted one
// position by a save (an offer's reload).
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
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/recipe_fix_panel.dart';
import 'package:salt_app/features/nutrition/review_sheet.dart';

import 'support/contract_goldens.dart';

/// The recipes page for any list GET, [matches] (when given) for a matches
/// GET, the subrecipe label for any other GET, [put] for every PUT
/// (recorded).
class _Routes implements HttpClientAdapter {
  _Routes(this.put, {this.matches});

  final Object put;
  final Object? matches;
  final List<Object?> puts = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Object body;
    if (options.method == 'PUT') {
      puts.add(options.data);
      body = put;
    } else if (options.path == '/api/v1/recipes') {
      body = golden('recipes_page');
    } else if (matches != null && options.path.contains('/nutrition/matches')) {
      body = matches!;
    } else {
      body = golden('nutrition_subrecipe');
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

Map<String, dynamic> _copy(String name) =>
    jsonDecode(jsonEncode(golden(name))) as Map<String, dynamic>;

Map<String, dynamic> _item(Map<String, dynamic> body, int position) =>
    (body['items']! as List).cast<Map<String, dynamic>>().singleWhere(
      (i) => i['position'] == position,
    );

Future<_Routes> _panel(
  WidgetTester t, {
  required Map<String, dynamic> body,
  required int position,
  required String slug,
  String? section,
}) async {
  t.view.physicalSize = const Size(1000, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final routes = _Routes(body);
  final dio = Dio(BaseOptions(baseUrl: 'http://contract'))
    ..httpClientAdapter = routes;
  final repo = NutritionRepository(dio);
  final cubit = NutritionCubit(repo, slug, section: section);
  addTearDown(cubit.close);
  final match = IngredientMatch.fromJson(_item(body, position));
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: repo),
        RepositoryProvider.value(value: RecipeRepository(dio: dio)),
      ],
      child: MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
        builder: (context, child) =>
            FTheme(data: buildForuiTheme(), child: child!),
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 900,
                child: RecipeFixPanel(match: match, busy: false),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return routes;
}

/// The review sheet (admin) opened on a cubit for [slug] / [section], its
/// matches GET answered by [body] — the row's bar is the routed line's.
Future<void> _sheet(
  WidgetTester t, {
  required Map<String, dynamic> body,
  required String slug,
  String? section,
}) async {
  t.view.physicalSize = const Size(1000, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final dio = Dio(BaseOptions(baseUrl: 'http://contract'))
    ..httpClientAdapter = _Routes(body, matches: body);
  final repo = NutritionRepository(dio);
  final cubit = NutritionCubit(repo, slug, section: section);
  addTearDown(cubit.close);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: repo),
        RepositoryProvider.value(value: RecipeRepository(dio: dio)),
      ],
      child: MaterialApp(
        theme: buildMaterialTheme(buildForuiTheme()),
        builder: (context, child) =>
            FTheme(data: buildForuiTheme(), child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => FButton(
              onPress: () =>
                  showReviewSheet(context, isAdmin: true, cubit: cubit),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

String _button(WidgetTester t) => t
    .widgetList<Text>(
      find.descendant(of: find.byType(FButton), matching: find.byType(Text)),
    )
    .map((w) => w.data ?? '')
    .firstWhere((s) => s.startsWith('Confirm') || s.startsWith('Use'));

String _field(WidgetTester t) =>
    t.widget<EditableText>(find.byType(EditableText).last).controller.text;

void main() {
  Map<String, dynamic> stagedShare({
    bool candidateShare = true,
    bool floor = false,
  }) {
    final body = _copy('nutrition_matches_staged_share');
    final child =
        (_item(body, 3)['match']! as Map<String, dynamic>)['child']!
            as Map<String, dynamic>;
    if (!candidateShare) {
      for (final c
          in (child['candidates']! as List).cast<Map<String, dynamic>>()) {
        if (c['title'] == 'Basic Spice Rub for Pork Chops') {
          c['share_text'] = null; // SYNTHESIZED (1).
        }
      }
    }
    if (floor) {
      child['share'] = 0.001; // SYNTHESIZED (2).
      child['share_text'] = '<0.01';
    }
    return body;
  }

  // U18 (S10 = O10): a staged candidate with no share_text — the field
  // empty, the button names no figure, the PUT sends no share.
  testWidgets('U18: the GET arm — no share_text: empty field, no figure, '
      'no share sent; a typed share is sent', (t) async {
    final routes = await _panel(
      t,
      body: stagedShare(candidateShare: false),
      position: 3,
      slug: 'grill-roasted-beer-can-chicken',
    );
    expect(_field(t), '0.19');
    await t.tap(find.text('Basic Spice Rub for Pork Chops'));
    await t.pumpAndSettle();
    expect(_field(t), '');
    expect(_button(t), 'Use this recipe');
    await t.tap(find.text('Use this recipe'));
    await t.pumpAndSettle();
    expect(routes.puts, [
      {
        'raw': '3 tablespoons Spice Rub (recipe follows)',
        'child': 'grilled-pork-chops',
        'section': 'Basic Spice Rub for Pork Chops',
      },
    ]);
    await t.enterText(find.byType(EditableText).last, '½');
    await t.pumpAndSettle();
    expect(_button(t), 'Use this recipe · ½ recipe');
    await t.tap(find.text('Use this recipe · ½ recipe'));
    await t.pumpAndSettle();
    expect(routes.puts.last, {
      'raw': '3 tablespoons Spice Rub (recipe follows)',
      'child': 'grilled-pork-chops',
      'section': 'Basic Spice Rub for Pork Chops',
      'share': 0.5,
    });
  });

  testWidgets('U18: the search arm — a result carries no share: empty field, '
      'no figure', (t) async {
    await _panel(
      t,
      body: stagedShare(),
      position: 3,
      slug: 'grill-roasted-beer-can-chicken',
    );
    await t.enterText(find.byType(EditableText).first, 'gemelli');
    await t.tap(find.text('Search'));
    await t.pumpAndSettle();
    final title = (golden('recipes_page')['items']! as List).first['title'];
    await t.tap(find.text(title as String));
    await t.pumpAndSettle();
    expect(_field(t), '');
    expect(_button(t), 'Use this recipe');
  });

  testWidgets('U18: the control — a candidate WITH share_text keeps it', (
    t,
  ) async {
    await _panel(
      t,
      body: stagedShare(),
      position: 3,
      slug: 'grill-roasted-beer-can-chicken',
    );
    await t.tap(find.text('Basic Spice Rub for Pork Chops'));
    await t.pumpAndSettle();
    expect(_field(t), '¾');
    expect(_button(t), 'Use this recipe · ¾ recipe');
  });

  // U20 (Sonnet C2): '<0.01' does not parse — the field reads the numeric
  // share at four places.
  testWidgets("U20: a '<0.01' share prefills its number", (t) async {
    await _panel(
      t,
      body: stagedShare(floor: true),
      position: 3,
      slug: 'grill-roasted-beer-can-chicken',
    );
    expect(_field(t), '0.001');
  });

  // U19 (O9): a section's own routed line draws Confirm and Skip as the
  // table offers them; the host's routed line keeps Change (its panel
  // carries them).
  testWidgets('U19: the section cubit draws Confirm and Skip on the routed '
      'line; the host cubit does not', (t) async {
    await _sheet(
      t,
      body: _copy('nutrition_matches_section_other'),
      slug: 'pecan-pie',
      section: 'Triple Chocolate Chunk Pecan Pie',
    );
    // The 12 food lines' bars carry a Skip each; the routed line's is the
    // 13th (base: 12 — the routed line's bar held only its sheet link).
    expect(find.text('Change'), findsNothing);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Skip'), findsNWidgets(13));
    await _sheet(
      t,
      body: _copy('nutrition_matches_section_other'),
      slug: 'pumpkin-pie',
    );
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Skip'), findsNWidgets(12));
  });

  // U15 (O6): an offer pending on a SECTION pick, the line moved by a save:
  // the reload places it on its new row and keeps the section the resend
  // carries.
  test('U15: offerOnReload keeps childSection when the line moved', () {
    final body = _copy('nutrition_matches_staged_share');
    final items = (body['items']! as List).cast<Map<String, dynamic>>();
    final shifted = [
      for (final i in items)
        IngredientMatch.fromJson({
          ...i,
          'position': (i['position']! as int) + 1,
        }),
    ];
    final ApplyOffer offer = (
      position: 3,
      raw: '3 tablespoons Spice Rub (recipe follows)',
      label: 'Basic Spice Rub for Pork Chops',
      fdcId: null,
      confirmed: false,
      grams: null,
      others: 1,
      lines: 1,
      child: 'grilled-pork-chops',
      share: 0.75,
      childSection: 'Basic Spice Rub for Pork Chops',
      recipe: true,
    );
    final moved = offerOnReload(offer, shifted)!;
    expect(moved.position, 4);
    expect(moved.childSection, 'Basic Spice Rub for Pork Chops');
    expect(moved.child, 'grilled-pork-chops');
  });
}
