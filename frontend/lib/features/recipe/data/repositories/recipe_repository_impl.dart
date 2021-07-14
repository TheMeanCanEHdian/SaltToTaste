import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/repositories/recipe_repository.dart';
import '../datasources/recipe_data_source.dart';

class RecipeRepositoryImpl implements RecipeRepository {
  final RecipeDataSource dataSource;

  RecipeRepositoryImpl({
    required this.dataSource,
  });

  @override
  Future<Either<Failure, Recipe>> getRecipe({
    required String titleSanitized,
  }) async {
    try {
      final recipe = await dataSource.getRecipe(titleSanitized: titleSanitized);
      return Right(recipe);
    } catch (exception) {
      print(exception);
      //TODO: Customize failures
      return Left(UnknownFailure());
    }
  }
}
