part of 'recipe_bloc.dart';

abstract class RecipeEvent extends Equatable {
  const RecipeEvent();
}

class RecipeFetch extends RecipeEvent {
  final String titleSanitized;

  RecipeFetch({required this.titleSanitized});

  @override
  List<Object?> get props => [titleSanitized];
}
