import '../../../../core/api/salt_to_taste_api.dart' as api;
import '../../domain/entities/recipe.dart';
import '../models/recipe_model.dart';

abstract class RecipeListDataSource {
  Future<List<Recipe>> getRecipeList();
}

class RecipeListDataSourceImpl implements RecipeListDataSource {
  final api.RecipeList recipes;

  RecipeListDataSourceImpl({
    required this.recipes,
  });

  @override
  Future<List<Recipe>> getRecipeList() async {
    final recipesJson = await recipes();

    final List<Recipe> recipeList = [];
    recipesJson['data'].forEach((recipe) {
      recipeList.add(RecipeModel.fromJson(recipe));
    });

    return recipeList;
  }
}
