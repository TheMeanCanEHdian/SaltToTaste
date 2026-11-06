// Matcher v103 (batch fix103) — the app half of Run 075/076's U11, U12, U13.
//
// Real data: every body is a shipped contract golden (real corpus lines
// through the real server routes): Grill-Roasted Beer Can Chicken 0640's
// "3 tablespoons Spice Rub (recipe follows)" (nutrition_matches_staged_share,
// its own Spice Rub at 0.19 and Grilled Pork Chops 0598's "Basic Spice Rub
// for Pork Chops" at ¾), Pumpkin Pie 0987's dough line routed on 0972's
// "Basic Single-Crust Pie Dough" (nutrition_matches_section_other), the
// recipes page and the subrecipe label.
// SYNTHESIZED — disclosed: (1) no golden serves a SECTION's own routed line
// (the snapshot's pecan-pie Triple Chocolate Chunk Pecan Pie line 0 is
// computed only by a sweep), so the section pin serves Pumpkin Pie's real
// routed dough line — the same corpus text — to a section cubit, its
// candidates unpickable as the server writes them on a section's line
// (v47 F8); (2) no golden carries a `self` partial, so the label pin puts
// the v47 Boston Cream Doughnuts shape ("1 recipe Yeasted Doughnuts (this
// page)", reason self) on the real subrecipe label.
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
import 'package:salt_app/features/nutrition/match_fix_panel.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';
import 'package:salt_app/features/nutrition/nutrition_label.dart';
import 'package:salt_app/features/nutrition/recipe_fix_panel.dart';
import 'package:salt_app/features/nutrition/review_sheet.dart';
import 'package:salt_shared/salt_shared.dart' show HoldDecision;

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
  // U12 (Run 076 O7): the staged candidate's own share fills the field and
  // the button — the share the server stores for a pick with none typed.
  testWidgets('U12: staging another section shows ITS share; the PUT sends '
      'none', (t) async {
    final body = _copy('nutrition_matches_staged_share');
    final routes = await _panel(
      t,
      body: body,
      position: 3,
      slug: 'grill-roasted-beer-can-chicken',
    );
    expect(_field(t), '0.19');
    await t.tap(find.text('Basic Spice Rub for Pork Chops'));
    await t.pumpAndSettle();
    expect(_field(t), '¾');
    expect(_button(t), 'Use this recipe · ¾ recipe');
    await t.tap(find.text('Use this recipe · ¾ recipe'));
    await t.pumpAndSettle();
    expect(routes.puts, [
      {
        'raw': '3 tablespoons Spice Rub (recipe follows)',
        'child': 'grilled-pork-chops',
        'section': 'Basic Spice Rub for Pork Chops',
      },
    ]);
    // Back on the current child: its own share again.
    await t.tap(find.text('Spice Rub'));
    await t.pumpAndSettle();
    expect(_field(t), '0.19');
  });

  group('U11: a section\'s own routed line offers no recipe', () {
    Map<String, dynamic> sectionBody() {
      final body = _copy('nutrition_matches_section_other');
      final child =
          (_item(body, 0)['match']! as Map<String, dynamic>)['child']!
              as Map<String, dynamic>;
      for (final c
          in (child['candidates']! as List).cast<Map<String, dynamic>>()) {
        c['pickable'] = false; // SYNTHESIZED (1): the server's v47 F8.
      }
      return body;
    }

    test('the action table: no recipe on the section line, the host '
        'unchanged', () {
      final m = IngredientMatch.fromJson(
        _item(_copy('nutrition_matches_section_other'), 0),
      );
      expect(offers(m, HoldDecision.recipe, section: true), isFalse);
      expect(offers(m, HoldDecision.confirm, section: true), isTrue);
      expect(offers(m, HoldDecision.skip, section: true), isTrue);
      expect(offers(m, HoldDecision.recipe), isTrue);
    });

    testWidgets('a section cubit: no share field, muted search results', (
      t,
    ) async {
      await _panel(
        t,
        body: sectionBody(),
        position: 0,
        slug: 'pecan-pie',
        section: 'Triple Chocolate Chunk Pecan Pie',
      );
      expect(find.byType(UnitToggle), findsNothing);
      await t.enterText(find.byType(EditableText).first, 'gemelli');
      await t.tap(find.text('Search'));
      await t.pumpAndSettle();
      final title = (golden('recipes_page')['items']! as List).first['title'];
      await t.tap(find.text(title as String));
      await t.pumpAndSettle();
      expect(_button(t), startsWith('Confirm'));
    });

    // Verify2 D5: the section bit at the routed row's bar
    // (review_sheet.dart `_referenceActions`).
    testWidgets('the review sheet on a section cubit: the routed line '
        'offers no Change; its sheet link stays', (t) async {
      await _sheet(
        t,
        body: sectionBody(),
        slug: 'pecan-pie',
        section: 'Triple Chocolate Chunk Pecan Pie',
      );
      expect(find.text("Open the recipe's matches"), findsOneWidget);
      expect(find.text('Change'), findsNothing);
    });

    testWidgets('the review sheet on the host cubit: the routed line offers '
        'Change', (t) async {
      await _sheet(
        t,
        body: _copy('nutrition_matches_section_other'),
        slug: 'pumpkin-pie',
      );
      expect(find.text("Open the recipe's matches"), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('the host cubit: the share field and a pickable result', (
      t,
    ) async {
      await _panel(
        t,
        body: _copy('nutrition_matches_section_other'),
        position: 0,
        slug: 'pumpkin-pie',
      );
      expect(find.byType(UnitToggle), findsOneWidget);
      await t.enterText(find.byType(EditableText).first, 'gemelli');
      await t.tap(find.text('Search'));
      await t.pumpAndSettle();
      final title = (golden('recipes_page')['items']! as List).first['title'];
      await t.tap(find.text(title as String));
      await t.pumpAndSettle();
      expect(_button(t), startsWith('Use this recipe'));
    });
  });

  // U13 (Run 075 S8): `self` reads as a sentence, never the raw token.
  test('U13: a self partial line and its note', () {
    final label = _copy('nutrition_subrecipe')
      ..['partial'] = [
        {
          'position': 0,
          'kind': 'not_routed',
          'name': 'Yeasted Doughnuts',
          'title': null,
          'matched': null,
          'total': null,
          'reason': 'self',
        },
      ];
    expect(partialLines(RecipeNutrition.fromJson(label)), [
      'Partial: Yeasted Doughnuts is not counted (it names its own recipe).',
    ]);
    expect(notRoutedNote('self'), 'It names its own recipe — not counted');
  });
}
