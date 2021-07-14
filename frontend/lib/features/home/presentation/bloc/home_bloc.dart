import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../recipe/domain/entities/recipe.dart';
import '../../../recipe/domain/usecases/get_recipe_list.dart';

part 'home_event.dart';
part 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final GetRecipes getRecipes;

  HomeBloc({required this.getRecipes}) : super(HomeInitial());

  @override
  Stream<HomeState> mapEventToState(
    HomeEvent event,
  ) async* {
    if (event is HomeFetchRecipes) {
      yield HomeInProgress();

      final failureOrRecipes = await getRecipes();

      yield* failureOrRecipes.fold(
        (failure) async* {
          yield HomeFailure();
        },
        (recipes) async* {
          yield HomeSuccess(recipes: recipes);
        },
      );
    }
  }
}
