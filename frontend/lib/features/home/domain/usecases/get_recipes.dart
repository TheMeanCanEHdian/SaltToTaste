import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/recipe.dart';
import '../repositories/recipes_repository.dart';

class GetRecipes {
  final RecipesRepository repository;

  GetRecipes({required this.repository});

  Future<Either<Failure, List<Recipe>>> call() async {
    return await repository.getRecipes();
  }
}
