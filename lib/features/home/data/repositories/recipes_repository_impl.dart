import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/repositories/recipes_repository.dart';
import '../datasources/recipes_data_source.dart';

class RecipesRepositoryImpl implements RecipesRepository {
  final RecipesDataSource dataSource;

  RecipesRepositoryImpl({
    required this.dataSource,
  });

  @override
  Future<Either<Failure, List<Recipe>>> getRecipes() async {
    try {
      final recipes = await dataSource.getRecipes();
      return Right(recipes);
    } catch (exception) {
      print(exception);
      //TODO: Customize failures
      return Left(UnknownFailure());
    }
  }
}
