import 'package:get_it/get_it.dart';

import 'core/api/salt_to_taste_api.dart' as salt_to_taste_api;
import 'features/home/presentation/bloc/home_bloc.dart';
import 'features/recipe/data/datasources/recipe_data_source.dart';
import 'features/recipe/data/datasources/recipe_list_data_source.dart';
import 'features/recipe/data/repositories/recipe_list_repository_impl.dart';
import 'features/recipe/data/repositories/recipe_repository_impl.dart';
import 'features/recipe/domain/repositories/recipe_list_repository.dart';
import 'features/recipe/domain/repositories/recipe_repository.dart';
import 'features/recipe/domain/usecases/get_recipe.dart';
import 'features/recipe/domain/usecases/get_recipe_list.dart';
import 'features/recipe/presentation/bloc/recipe_bloc.dart';
import 'features/settings/data/datasources/settings_data_source.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/settings/domain/usecases/get_settings.dart';
import 'features/settings/domain/usecases/update_setting.dart';
import 'features/settings/presentation/bloc/settings_bloc.dart';
import 'features/settings/presentation/bloc/settings_update_bloc.dart';

// Service locator alias
final sl = GetIt.instance;

Future<void> init() async {
  //! Features - Home
  // Bloc
  sl.registerLazySingleton(
    () => HomeBloc(
      getRecipeList: sl(),
    ),
  );

  //! Features - Recipe
  // Bloc
  sl.registerLazySingleton(
    () => RecipeBloc(
      getRecipe: sl(),
    ),
  );

  // Use case
  sl.registerLazySingleton(
    () => GetRecipe(
      repository: sl(),
    ),
  );

  sl.registerLazySingleton(
    () => GetRecipeList(
      repository: sl(),
    ),
  );

  // Repository
  sl.registerLazySingleton<RecipeRepository>(
    () => RecipeRepositoryImpl(
      dataSource: sl(),
    ),
  );

  sl.registerLazySingleton<RecipeListRepository>(
    () => RecipeListRepositoryImpl(
      dataSource: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<RecipeDataSource>(
    () => RecipeDataSourceImpl(
      recipe: sl(),
    ),
  );

  sl.registerLazySingleton<RecipeListDataSource>(
    () => RecipeListDataSourceImpl(
      recipes: sl(),
    ),
  );

  //! Settings
  // Bloc
  sl.registerLazySingleton(
    () => SettingsBloc(
      getSettings: sl(),
    ),
  );

  sl.registerLazySingleton(
    () => SettingsUpdateBloc(
      updateSetting: sl(),
    ),
  );

  // Use case
  sl.registerLazySingleton(
    () => GetSettings(
      repository: sl(),
    ),
  );

  sl.registerLazySingleton(
    () => UpdateSetting(
      repository: sl(),
    ),
  );

  // Repository
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(
      dataSource: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<SettingsDataSource>(
    () => SettingsDataSourceImpl(
      settings: sl(),
    ),
  );

  //! API
  sl.registerLazySingleton<salt_to_taste_api.CallSaltToTaste>(
    () => salt_to_taste_api.CallSaltToTasteImpl(),
  );
  sl.registerLazySingleton<salt_to_taste_api.Recipe>(
    () => salt_to_taste_api.RecipeImpl(
      callSaltToTaste: sl(),
    ),
  );
  sl.registerLazySingleton<salt_to_taste_api.RecipeList>(
    () => salt_to_taste_api.RecipeListImpl(
      callSaltToTaste: sl(),
    ),
  );
  sl.registerLazySingleton<salt_to_taste_api.Settings>(
    () => salt_to_taste_api.SettingsImpl(
      callSaltToTaste: sl(),
    ),
  );
}
