import 'package:get_it/get_it.dart';

import 'core/api/salt_to_taste_api.dart' as salt_to_taste_api;
import 'features/home/data/datasources/recipe_list_data_source.dart';
import 'features/home/data/repositories/recipes_repository_impl.dart';
import 'features/home/domain/repositories/recipe_list_repository.dart';
import 'features/home/domain/usecases/get_recipe_list.dart';
import 'features/home/presentation/bloc/home_bloc.dart';

// Service locator alias
final sl = GetIt.instance;

Future<void> init() async {
  //! Features - Home
  // Bloc
  sl.registerLazySingleton(
    () => HomeBloc(
      getRecipes: sl(),
    ),
  );

  // Use case
  sl.registerLazySingleton(
    () => GetRecipes(
      repository: sl(),
    ),
  );

  // Repository
  sl.registerLazySingleton<RecipeListRepository>(
    () => RecipeListRepositoryImpl(
      dataSource: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<RecipeListDataSource>(
    () => RecipeListDataSourceImpl(
      recipes: sl(),
    ),
  );

  //! API
  sl.registerLazySingleton<salt_to_taste_api.CallSaltToTaste>(
    () => salt_to_taste_api.CallSaltToTasteImpl(),
  );
  sl.registerLazySingleton<salt_to_taste_api.RecipeList>(
    () => salt_to_taste_api.RecipeListImpl(
      callSaltToTaste: sl(),
    ),
  );
}
