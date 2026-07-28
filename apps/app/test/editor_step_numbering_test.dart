import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/editor/editor_cubit.dart';

import 'support/corpus.dart';

/// A repository stub: serves the loaded recipe and captures the field map a
/// save would send, so step-number serialization can be asserted offline.
class _FakeRepo extends RecipeRepository {
  _FakeRepo(this._detail) : super(dio: Dio());

  final RecipeDetail _detail;
  Map<String, Object?>? captured;

  @override
  Future<RecipeDetail> getRecipe(String idOrSlug) async => _detail;

  @override
  Future<RecipeDetail> updateRecipe(
    String id,
    Map<String, Object?> fields, {
    String? baseHash,
  }) async {
    captured = fields;
    return _detail;
  }
}

void main() {
  // 0485-steak-fajitas encodes the book's alternate branches as two steps
  // sharing a number (charcoal step 2 vs gas step 2) — real data ~103 corpus
  // recipes carry. A routine editor save must not linearize the run (B4).
  group('editor step numbering (review B4)', skip: skipIfNoCorpus, () {
    late Recipe fajitas;
    late List<int> authored;

    setUpAll(() {
      fajitas = loadCorpusRecipe('0485-steak-fajitas.yaml');
      authored = [for (final step in fajitas.steps) step.number];
      expect(
        authored,
        isNot([for (var i = 1; i <= authored.length; i++) i]),
        reason: 'the fixture really is non-sequential',
      );
    });

    List<int> capturedNumbers(_FakeRepo repo) => [
      for (final step in (repo.captured!['steps']! as List))
        (step as Map)['number'] as int,
    ];

    test('a text edit round-trips the authored duplicate run', () async {
      final repo = _FakeRepo(RecipeDetail(recipe: fajitas, sourceSlug: 'atk'));
      final cubit = EditorCubit(repo);
      await cubit.load(fajitas.slug);
      final firstStep = cubit.state.steps.first;
      cubit.setStep(firstStep.key, text: '${firstStep.text} (edited)');
      await cubit.save();
      expect(capturedNumbers(repo), authored);
    });

    test('inserting a step falls back to sequential numbering', () async {
      final repo = _FakeRepo(RecipeDetail(recipe: fajitas, sourceSlug: 'atk'));
      final cubit = EditorCubit(repo);
      await cubit.load(fajitas.slug);
      cubit.addStep();
      cubit.setStep(cubit.state.steps.last.key, text: 'Serve immediately.');
      await cubit.save();
      final expected = [for (var i = 1; i <= authored.length + 1; i++) i];
      expect(capturedNumbers(repo), expected);
    });
  });
}
