import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/recipe.dart';
import '../repositories/recipe_repository.dart';

class GetRecipe {
  final RecipeRepository repository;

  GetRecipe({required this.repository});

  Future<Either<Failure, Recipe>> call({
    required String titleSanitized,
  }) async {
    return await repository.getRecipe(titleSanitized: titleSanitized);
  }
}
