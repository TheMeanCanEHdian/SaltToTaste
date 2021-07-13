import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/recipe.dart';

abstract class RecipeListRepository {
  Future<Either<Failure, List<Recipe>>> getRecipeList();
}
