import '../../../../core/api/salt_to_taste_api.dart' as api;
import '../../domain/entities/recipe.dart';
import '../models/recipe_model.dart';

abstract class RecipeDataSource {
  Future<Recipe> getRecipe({
    required String titleSanitized,
  });
}

class RecipeDataSourceImpl implements RecipeDataSource {
  final api.Recipe recipe;

  RecipeDataSourceImpl({
    required this.recipe,
  });

  @override
  Future<Recipe> getRecipe({
    required String titleSanitized,
  }) async {
    final recipeJson = await recipe(titleSanitized: titleSanitized);

    return RecipeModel.fromJson(recipeJson['data']);
  }
}
