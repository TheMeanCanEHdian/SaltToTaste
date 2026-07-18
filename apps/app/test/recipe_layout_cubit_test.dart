import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/features/recipes/list/recipe_layout_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The session's list-layout preference and its persistence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('in memory (no prefs)', () {
    test('defaults to the photo grid', () {
      expect(RecipeLayoutCubit().state, RecipeLayout.grid);
    });

    test('select switches the layout', () {
      final cubit = RecipeLayoutCubit();
      cubit.select(RecipeLayout.list);
      expect(cubit.state, RecipeLayout.list);
      cubit.select(RecipeLayout.grid);
      expect(cubit.state, RecipeLayout.grid);
    });

    test('selecting the current layout emits nothing', () async {
      final cubit = RecipeLayoutCubit();
      final seen = <RecipeLayout>[];
      final sub = cubit.stream.listen(seen.add);
      cubit.select(RecipeLayout.grid); // already grid
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      await sub.cancel();
    });
  });

  group('persistence', () {
    test('reads the stored layout on construction', () async {
      SharedPreferences.setMockInitialValues({
        RecipeLayoutCubit.prefsKey: 'list',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(RecipeLayoutCubit(prefs).state, RecipeLayout.list);
    });

    test('defaults to grid when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(RecipeLayoutCubit(prefs).state, RecipeLayout.grid);
    });

    test('an unrecognised stored value falls back to grid', () async {
      SharedPreferences.setMockInitialValues({
        RecipeLayoutCubit.prefsKey: 'bogus',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(RecipeLayoutCubit(prefs).state, RecipeLayout.grid);
    });

    test('select writes the choice through', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      RecipeLayoutCubit(prefs).select(RecipeLayout.list);
      expect(prefs.getString(RecipeLayoutCubit.prefsKey), 'list');
    });
  });
}
