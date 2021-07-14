import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/repositories/recipe_list_repository.dart';
import '../datasources/recipe_list_data_source.dart';

class RecipeListRepositoryImpl implements RecipeListRepository {
  final RecipeListDataSource dataSource;

  RecipeListRepositoryImpl({
    required this.dataSource,
  });

  @override
  Future<Either<Failure, List<Recipe>>> getRecipeList() async {
    try {
      final recipes = await dataSource.getRecipeList();
      return Right(recipes);
    } catch (exception) {
      print(exception);
      //TODO: Customize failures
      return Left(UnknownFailure());
    }
  }
}
