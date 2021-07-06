import 'package:get_it/get_it.dart';
import 'package:salt_to_taste/features/home/presentation/bloc/home_bloc.dart';

import 'core/api/salt_to_taste_api.dart' as salt_to_taste_api;
import 'features/home/data/datasources/recipes_data_source.dart';
import 'features/home/data/repositories/recipes_repository_impl.dart';
import 'features/home/domain/repositories/recipes_repository.dart';
import 'features/home/domain/usecases/get_recipes.dart';

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
  sl.registerLazySingleton<RecipesRepository>(
    () => RecipesRepositoryImpl(
      dataSource: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<RecipesDataSource>(
    () => RecipesDataSourceImpl(
      recipes: sl(),
    ),
  );

  //! API
  sl.registerLazySingleton<salt_to_taste_api.CallSaltToTaste>(
    () => salt_to_taste_api.CallSaltToTasteImpl(),
  );
  sl.registerLazySingleton<salt_to_taste_api.Recipes>(
    () => salt_to_taste_api.RecipesImpl(
      callSaltToTaste: sl(),
    ),
  );
}
