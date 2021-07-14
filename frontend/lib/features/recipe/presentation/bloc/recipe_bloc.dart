import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/recipe.dart';
import '../../domain/usecases/get_recipe.dart';

part 'recipe_event.dart';
part 'recipe_state.dart';

class RecipeBloc extends Bloc<RecipeEvent, RecipeState> {
  final GetRecipe getRecipe;

  RecipeBloc({
    required this.getRecipe,
  }) : super(RecipeInitial());

  @override
  Stream<RecipeState> mapEventToState(
    RecipeEvent event,
  ) async* {
    if (event is RecipeFetch) {
      yield RecipeInProgress();

      final failureOrRecipe = await getRecipe(
        titleSanitized: event.titleSanitized,
      );

      yield* failureOrRecipe.fold(
        (failure) async* {
          yield RecipeFailure();
        },
        (recipe) async* {
          yield RecipeSuccess(recipe: recipe);
        },
      );
    }
  }
}
