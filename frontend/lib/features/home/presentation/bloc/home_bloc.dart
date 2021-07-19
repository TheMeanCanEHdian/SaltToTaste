import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

import '../../../recipe/domain/entities/recipe.dart';
import '../../../recipe/domain/usecases/get_recipe_list.dart';

part 'home_event.dart';
part 'home_state.dart';

List<Recipe> recipesCache = [];

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final GetRecipeList getRecipeList;

  HomeBloc({required this.getRecipeList}) : super(HomeInitial());

  @override
  Stream<HomeState> mapEventToState(
    HomeEvent event,
  ) async* {
    if (event is HomeFetchRecipes) {
      yield HomeInProgress(
        recipes: recipesCache.isNotEmpty ? recipesCache : [],
      );

      final failureOrRecipes = await getRecipeList();

      yield* failureOrRecipes.fold(
        (failure) async* {
          yield HomeFailure();
        },
        (recipes) async* {
          Function listEquality = const ListEquality().equals;

          // If new list of recipes is different from cached list replace cache
          if (!listEquality(recipes, recipesCache)) {
            recipesCache = [...recipes];
          }

          yield HomeSuccess(recipes: recipesCache);
        },
      );
    }
  }
}
