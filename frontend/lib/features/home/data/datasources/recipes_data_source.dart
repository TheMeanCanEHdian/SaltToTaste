import '../../../../core/api/salt_to_taste_api.dart' as api;
import '../../domain/entities/recipe.dart';
import '../models/recipe_model.dart';

abstract class RecipesDataSource {
  Future<List<Recipe>> getRecipes();
}

class RecipesDataSourceImpl implements RecipesDataSource {
  final api.Recipes recipes;

  RecipesDataSourceImpl({
    required this.recipes,
  });

  @override
  Future<List<Recipe>> getRecipes() async {
    final recipesJson = await recipes();

    final List<Recipe> recipeList = [];
    recipesJson['data'].forEach((recipe) {
      recipeList.add(RecipeModel.fromJson(recipe));
    });

    return recipeList;
  }
}
