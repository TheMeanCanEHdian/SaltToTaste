import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/recipe.dart';
import '../repositories/recipe_list_repository.dart';

class GetRecipes {
  final RecipeListRepository repository;

  GetRecipes({required this.repository});

  Future<Either<Failure, List<Recipe>>> call() async {
    return await repository.getRecipeList();
  }
}
