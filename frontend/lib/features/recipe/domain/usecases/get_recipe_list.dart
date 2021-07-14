import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/recipe.dart';
import '../repositories/recipe_list_repository.dart';

class GetRecipeList {
  final RecipeListRepository repository;

  GetRecipeList({required this.repository});

  Future<Either<Failure, List<Recipe>>> call() async {
    return await repository.getRecipeList();
  }
}
