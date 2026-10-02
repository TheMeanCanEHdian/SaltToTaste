// Run 055 Opus critic 3 (v25 I5): the parser collapses whitespace runs, so
// a line stored before it did ("Salt  and pepper", its item stored with the
// run) parsed to a different item and the editor locked it as
// hand-curated: an edit to "1 teaspoon salt" then kept no amounts. The
// editor reads the stored fields as the parser reads a line (one shared
// `normalizeLineWhitespace`, salt_shared). Synthesized, a stated exception: the
// double space (no corpus line prints a run; "Salt and pepper" is a
// corpus line's text).

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/features/editor/editor_cubit.dart';
import 'package:salt_shared/salt_shared.dart';

class _Repo extends RecipeRepository {
  _Repo(this._detail) : super(dio: Dio());

  final RecipeDetail _detail;

  @override
  Future<RecipeDetail> getRecipe(String idOrSlug) async => _detail;
}

void main() {
  test('a stored "Salt  and pepper" is the parser\'s, not hand-curated: an '
      'edit re-parses it; a really curated item stays locked', () async {
    const recipe = Recipe(
      id: 'r1',
      title: 'Salt',
      slug: 'salt',
      source: RecipeSource(name: 'ATK', type: 'manual'),
      ingredients: [
        IngredientGroup(
          items: [
            IngredientLine(raw: 'Salt  and pepper', item: 'Salt  and pepper'),
            IngredientLine(raw: 'Salt and pepper', item: 'kosher salt'),
          ],
        ),
      ],
      steps: [RecipeStep(number: 1, text: 'Season.')],
    );
    final cubit = EditorCubit(
      _Repo(const RecipeDetail(recipe: recipe, sourceSlug: 'salt')),
    );
    await cubit.load('salt');
    final lines = cubit.state.entries.whereType<EditorLine>().toList();
    expect(lines[0].manuallyEdited, isFalse);
    expect(lines[1].manuallyEdited, isTrue);
    cubit
      ..setLineRaw(lines[0].key, '1 teaspoon salt')
      ..applyAutoParse(lines[0].key);
    final edited = cubit.state.entries.whereType<EditorLine>().first;
    expect(edited.amounts, isNotEmpty);
    expect(edited.item, 'salt');
    expect(
      normalizeLineWhitespace('  Salt \t and\n pepper '),
      'Salt and pepper',
    );
  });

  test('the WHOLE stored line is read as the parser reads it (Run 056 '
      'O12/S26): a pre-v24 quantity run "1  1/2" and a prep run "chopped  '
      'fine" are the parser\'s — an edit re-parses them; a curated '
      'quantity stays locked', () async {
    const recipe = Recipe(
      id: 'r1',
      title: 'Flour',
      slug: 'flour',
      source: RecipeSource(name: 'ATK', type: 'manual'),
      ingredients: [
        IngredientGroup(
          items: [
            IngredientLine(
              raw: '1  1/2 cups flour',
              amounts: [
                Amount(
                  measure: Measure.volume,
                  quantity: '1  1/2',
                  unit: 'cup',
                  primary: true,
                ),
              ],
              item: 'flour',
            ),
            IngredientLine(
              raw: '1 onion, chopped  fine',
              amounts: [
                Amount(measure: Measure.count, quantity: '1', primary: true),
              ],
              item: 'onion',
              prep: 'chopped  fine',
            ),
            IngredientLine(
              raw: '1 1/2 cups flour',
              amounts: [
                Amount(
                  measure: Measure.volume,
                  quantity: '2',
                  unit: 'cup',
                  primary: true,
                ),
              ],
              item: 'flour',
            ),
          ],
        ),
      ],
      steps: [RecipeStep(number: 1, text: 'Mix.')],
    );
    final cubit = EditorCubit(
      _Repo(const RecipeDetail(recipe: recipe, sourceSlug: 'flour')),
    );
    await cubit.load('flour');
    final lines = cubit.state.entries.whereType<EditorLine>().toList();
    expect([for (final l in lines) l.manuallyEdited], [false, false, true]);
    cubit
      ..setLineRaw(lines[0].key, '2 cups sugar')
      ..applyAutoParse(lines[0].key);
    final edited = cubit.state.entries.whereType<EditorLine>().first;
    expect(edited.item, 'sugar');
    expect([for (final a in edited.amounts) a.quantity], ['2']);
  });
}
