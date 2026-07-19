import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/editor/editor_cubit.dart';

/// A repository stub: serves a canned recipe on load and captures the field map
/// a save would send, so serialization can be asserted without a server.
class _FakeRepo extends RecipeRepository {
  _FakeRepo(this._detail) : super(dio: Dio());

  final RecipeDetail _detail;
  Map<String, Object?>? captured;

  @override
  Future<RecipeDetail> getRecipe(String idOrSlug) async => _detail;

  @override
  Future<RecipeDetail> updateRecipe(String id, Map<String, Object?> fields) async {
    captured = fields;
    return _detail;
  }

  @override
  Future<RecipeDetail> createRecipe(Map<String, Object?> fields) async {
    captured = fields;
    return _detail;
  }
}

Recipe _recipe() => Recipe(
  id: 'r1',
  title: 'Meatballs',
  slug: 'meatballs',
  source: const RecipeSource(name: 'ATK', type: 'manual'),
  ingredients: const [
    IngredientGroup(items: [IngredientLine(raw: '2 cups flour')]),
  ],
  steps: const [RecipeStep(number: 1, text: 'Mix.')],
  subsections: const [
    // prose-only variation: no ingredients/steps keys
    Subsection(
      title: 'Spicy Version',
      kind: 'variation',
      body: 'Add 2 minced chipotles.',
    ),
    // full component: nested ingredients + steps
    Subsection(
      title: 'For the Almond Sauce',
      kind: 'component',
      servings: 'MAKES 2 CUPS',
      ingredients: [
        IngredientGroup(items: [IngredientLine(raw: '1 cup almonds')]),
      ],
      steps: [RecipeStep(number: 1, text: 'Blend.')],
    ),
  ],
  techniques: const [
    Technique(heading: 'Shaping', steps: [TechniqueStep(number: 1, caption: 'Roll.')]),
  ],
);

void main() {
  RecipeDetail detail() =>
      RecipeDetail(recipe: _recipe(), sourceSlug: 'meatballs');

  group('load maps subsections', () {
    test('prose-only vs full sub-recipe are distinguished', () async {
      final cubit = EditorCubit(_FakeRepo(detail()));
      await cubit.load('meatballs');
      final subs = cubit.state.subsections;
      expect(subs, hasLength(2));

      expect(subs[0].title, 'Spicy Version');
      expect(subs[0].kind, 'variation');
      expect(subs[0].body, 'Add 2 minced chipotles.');
      expect(subs[0].hasIngredients, isFalse, reason: 'prose-only');
      expect(subs[0].hasSteps, isFalse);

      expect(subs[1].kind, 'component');
      expect(subs[1].hasIngredients, isTrue);
      expect(subs[1].entries, hasLength(1));
      expect(subs[1].hasSteps, isTrue);
      expect(subs[1].steps.single.text, 'Blend.');
    });
  });

  group('save serialization', () {
    test('preserves the null-vs-empty distinction and leaves techniques alone',
        () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      await cubit.save();

      final fields = repo.captured!;
      // Editing subsections must NOT start dropping techniques — they stay
      // absent so the server merge preserves them.
      expect(fields.containsKey('techniques'), isFalse);

      final subs = (fields['subsections']! as List).cast<Map<String, Object?>>();
      expect(subs, hasLength(2));

      // Prose-only variation: no ingredients/steps keys at all.
      expect(subs[0]['title'], 'Spicy Version');
      expect(subs[0]['kind'], 'variation');
      expect(subs[0].containsKey('ingredients'), isFalse);
      expect(subs[0].containsKey('steps'), isFalse);

      // Full component: ingredients + steps present.
      expect(subs[1]['kind'], 'component');
      expect(subs[1]['servings'], 'MAKES 2 CUPS');
      expect(subs[1]['ingredients'], isA<List<Object?>>());
      expect((subs[1]['ingredients']! as List), isNotEmpty);
      expect((subs[1]['steps']! as List), hasLength(1));
    });

    test('promoting a prose variation emits an (empty) ingredients key',
        () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      final proseKey = cubit.state.subsections[0].key;
      cubit.promoteSubsectionIngredients(proseKey);
      // The seeded empty line carries no text, so it serializes to an empty
      // ingredient list — present, not absent (the null-vs-empty flip).
      await cubit.save();

      final subs =
          (repo.captured!['subsections']! as List).cast<Map<String, Object?>>();
      expect(subs[0].containsKey('ingredients'), isTrue);
      expect(subs[0]['ingredients'], isEmpty);
    });

    test('an emptied subsection is dropped on save', () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      final proseKey = cubit.state.subsections[0].key;
      cubit.setSubsectionTitle(proseKey, '');
      cubit.setSubsectionBody(proseKey, '');
      await cubit.save();

      final subs =
          (repo.captured!['subsections']! as List).cast<Map<String, Object?>>();
      expect(subs, hasLength(1), reason: 'the blanked variation is gone');
      expect(subs[0]['kind'], 'component');
    });
  });

  group('nested editing routes through the shared transforms', () {
    test('a fresh subsection line auto-parses like a top-level one', () async {
      final cubit = EditorCubit(_FakeRepo(detail()));
      await cubit.load('meatballs');
      final subKey = cubit.state.subsections[1].key;

      // A newly-added line isn't locked, so the debounced parse applies.
      cubit.subAddLine(subKey);
      final lineKey = cubit.state.subsections[1].entries
          .whereType<EditorLine>()
          .last
          .key;
      cubit.subSetLineRaw(subKey, lineKey, '2 cups (10 ounces) flour');
      cubit.subApplyAutoParse(subKey, lineKey);

      final line = cubit.state.subsections[1].entries
          .whereType<EditorLine>()
          .last;
      expect(line.raw, '2 cups (10 ounces) flour');
      expect(line.amounts, isNotEmpty, reason: 'the parser ran on the nested line');
    });
  });

  group('top-level editing still works after the refactor', () {
    test('add + parse a line, and steps serialize', () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');

      cubit.addLine();
      final newKey = cubit.state.entries.whereType<EditorLine>().last.key;
      cubit.setLineRaw(newKey, '1 teaspoon salt');
      cubit.applyAutoParse(newKey);
      await cubit.save();

      final ingredients =
          (repo.captured!['ingredients']! as List).cast<Map<String, Object?>>();
      final items = (ingredients.first['items']! as List);
      expect(items, hasLength(2));
      expect((repo.captured!['steps']! as List), hasLength(1));
    });
  });
}
