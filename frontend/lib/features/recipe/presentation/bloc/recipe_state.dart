part of 'recipe_bloc.dart';

abstract class RecipeState extends Equatable {
  const RecipeState();
}

class RecipeInitial extends RecipeState {
  @override
  List<Object> get props => [];
}

class RecipeInProgress extends RecipeState {
  @override
  List<Object?> get props => [];
}

class RecipeSuccess extends RecipeState {
  final Recipe recipe;

  RecipeSuccess({required this.recipe});

  @override
  List<Object?> get props => [recipe];
}

class RecipeFailure extends RecipeState {
  @override
  List<Object?> get props => [];
}
