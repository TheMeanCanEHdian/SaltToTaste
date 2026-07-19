import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/editor/editor_cubit.dart';

/// A repository stub: serves a canned recipe on load and captures the field map
/// a save would send, so serialization can be asserted without a server. Also
/// stubs the store-image endpoints so the step-photo flow is testable.
class _FakeRepo extends RecipeRepository {
  _FakeRepo(this._detail) : super(dio: Dio());

  final RecipeDetail _detail;
  Map<String, Object?>? captured;
  int storeImageCalls = 0;
  int storeFromUrlCalls = 0;
  String? lastStoreId;

  /// When set, `storeImage` blocks on this instead of returning — lets a test
  /// hold an upload in flight to exercise single-flight and mid-upload races.
  Completer<String>? storeGate;

  /// When set, `storeImage` throws it (the error path).
  Object? storeError;

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

  @override
  Future<String> storeImage(String idOrSlug, Uint8List bytes) async {
    storeImageCalls++;
    lastStoreId = idOrSlug;
    if (storeError != null) throw storeError!;
    if (storeGate != null) return storeGate!.future;
    return 'images/tech-stored.jpg';
  }

  @override
  Future<String> storeImageFromUrl(String idOrSlug, String url) async {
    storeFromUrlCalls++;
    lastStoreId = idOrSlug;
    return 'images/tech-from-url.jpg';
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
    Technique(
      heading: 'Shaping',
      description: 'Keep your hands damp.',
      steps: [
        TechniqueStep(number: 1, image: 'images/shape-01.jpg', caption: 'Roll.'),
      ],
    ),
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
    test('preserves the null-vs-empty distinction', () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      await cubit.save();

      final fields = repo.captured!;
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

  group('techniques', () {
    test('load maps the technique and its illustrated step', () async {
      final cubit = EditorCubit(_FakeRepo(detail()));
      await cubit.load('meatballs');
      expect(cubit.state.techniques, hasLength(1));
      final tech = cubit.state.techniques.single;
      expect(tech.heading, 'Shaping');
      expect(tech.description, 'Keep your hands damp.');
      expect(tech.steps.single.caption, 'Roll.');
      expect(tech.steps.single.image, 'images/shape-01.jpg');
    });

    test('save round-trips heading, description, and the step image', () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      await cubit.save();

      final techs =
          (repo.captured!['techniques']! as List).cast<Map<String, Object?>>();
      expect(techs, hasLength(1));
      expect(techs[0]['heading'], 'Shaping');
      expect(techs[0]['description'], 'Keep your hands damp.');
      final steps = (techs[0]['steps']! as List).cast<Map<String, Object?>>();
      expect(steps.single['image'], 'images/shape-01.jpg');
      expect(steps.single['caption'], 'Roll.');
      expect(steps.single['number'], 1);
    });

    test('an empty technique is dropped; a caption-only step survives', () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');

      cubit.addTechnique(); // empty → dropped
      final techKey = cubit.state.techniques.last.key;
      cubit.addTechniqueStep(techKey);
      final stepKey = cubit.state.techniques.last.steps.single.key;
      cubit.setTechniqueStepCaption(techKey, stepKey, 'Fold gently.');
      await cubit.save();

      final techs =
          (repo.captured!['techniques']! as List).cast<Map<String, Object?>>();
      // The loaded 'Shaping' technique plus the new one with a captioned step —
      // an empty step would have been dropped, this one has a caption.
      expect(techs, hasLength(2));
      final added = techs[1];
      expect(added.containsKey('heading'), isFalse);
      final steps = (added['steps']! as List).cast<Map<String, Object?>>();
      expect(steps.single['caption'], 'Fold gently.');
      expect(steps.single.containsKey('image'), isFalse);
    });

    test('uploadTechniqueStepImage stores the reference into the step', () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      final techKey = cubit.state.techniques.single.key;
      final stepKey = cubit.state.techniques.single.steps.single.key;

      await cubit.uploadTechniqueStepImage(
        techKey,
        stepKey,
        Uint8List.fromList([1, 2, 3]),
      );

      expect(repo.storeImageCalls, 1);
      expect(repo.lastStoreId, 'r1', reason: 'the recipe id, not the slug');
      final step = cubit.state.techniques.single.steps.single;
      expect(step.image, 'images/tech-stored.jpg');
      expect(cubit.state.uploadingImage, isFalse);
      expect(cubit.state.uploadingStepKey, isNull, reason: 'cleared on finish');
      expect(cubit.state.dirty, isTrue);
    });

    test('techniqueStepImageFromUrl stores via the URL endpoint', () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      final techKey = cubit.state.techniques.single.key;
      final stepKey = cubit.state.techniques.single.steps.single.key;

      await cubit.techniqueStepImageFromUrl(techKey, stepKey, 'https://x/a.jpg');

      expect(repo.storeFromUrlCalls, 1);
      expect(
        cubit.state.techniques.single.steps.single.image,
        'images/tech-from-url.jpg',
      );
    });

    test('a new (unsaved) recipe cannot store a step photo — the isNew gate',
        () async {
      final repo = _FakeRepo(detail());
      final cubit = EditorCubit(repo);
      cubit.startNew(); // recipeId stays null
      cubit.addTechnique();
      final techKey = cubit.state.techniques.single.key;
      cubit.addTechniqueStep(techKey);
      final stepKey = cubit.state.techniques.single.steps.single.key;

      await cubit.uploadTechniqueStepImage(
        techKey,
        stepKey,
        Uint8List.fromList([1]),
      );

      expect(repo.storeImageCalls, 0, reason: 'no id to attach to → no call');
      expect(cubit.state.techniques.single.steps.single.image, isNull);
      expect(cubit.state.uploadingImage, isFalse);
    });

    test('a failed store clears the upload flags and surfaces the error',
        () async {
      final repo = _FakeRepo(detail())
        ..storeError = const RepositoryException('upload failed');
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      final techKey = cubit.state.techniques.single.key;
      final stepKey = cubit.state.techniques.single.steps.single.key;
      final before = cubit.state.techniques.single.steps.single.image;

      await cubit.uploadTechniqueStepImage(
        techKey,
        stepKey,
        Uint8List.fromList([1]),
      );

      expect(cubit.state.uploadingImage, isFalse, reason: 'no lockout on error');
      expect(cubit.state.uploadingStepKey, isNull);
      expect(cubit.state.saveError, 'upload failed');
      expect(
        cubit.state.techniques.single.steps.single.image,
        before,
        reason: 'the step image is untouched on failure',
      );
    });

    test('an upload in flight is single-flight — a second is dropped', () async {
      final repo = _FakeRepo(detail())..storeGate = Completer<String>();
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      final techKey = cubit.state.techniques.single.key;
      final stepKey = cubit.state.techniques.single.steps.single.key;

      // First upload blocks on the gate.
      final first = cubit.uploadTechniqueStepImage(
        techKey,
        stepKey,
        Uint8List.fromList([1]),
      );
      expect(cubit.state.uploadingImage, isTrue);
      expect(cubit.state.uploadingStepKey, stepKey);

      // A second, while the first is in flight, returns immediately without a
      // store call (the cubit's single-flight guard).
      await cubit.uploadTechniqueStepImage(
        techKey,
        stepKey,
        Uint8List.fromList([2]),
      );
      expect(repo.storeImageCalls, 1, reason: 'the second upload is dropped');

      repo.storeGate!.complete('images/tech-stored.jpg');
      await first;
      expect(cubit.state.uploadingImage, isFalse);
      expect(cubit.state.techniques.single.steps.single.image,
          'images/tech-stored.jpg');
    });

    test('deleting the step mid-upload drops the reference harmlessly',
        () async {
      final repo = _FakeRepo(detail())..storeGate = Completer<String>();
      final cubit = EditorCubit(repo);
      await cubit.load('meatballs');
      final techKey = cubit.state.techniques.single.key;
      final stepKey = cubit.state.techniques.single.steps.single.key;

      final upload = cubit.uploadTechniqueStepImage(
        techKey,
        stepKey,
        Uint8List.fromList([1]),
      );
      expect(cubit.state.uploadingImage, isTrue);

      // The user deletes the very step being uploaded, then the store lands.
      cubit.removeTechniqueStep(techKey, stepKey);
      repo.storeGate!.complete('images/tech-stored.jpg');
      await upload;

      // No crash; the returned reference lands nowhere (step is gone); flags
      // are cleared.
      expect(cubit.state.techniques.single.steps, isEmpty);
      expect(cubit.state.uploadingImage, isFalse);
      expect(cubit.state.uploadingStepKey, isNull);
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
