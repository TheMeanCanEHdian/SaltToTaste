import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart';

/// State of one recipe detail page.
sealed class RecipeDetailState {
  const RecipeDetailState();
}

final class RecipeDetailLoading extends RecipeDetailState {
  const RecipeDetailLoading();
}

final class RecipeDetailError extends RecipeDetailState {
  const RecipeDetailError(this.message);

  final String message;
}

final class RecipeDetailLoaded extends RecipeDetailState {
  const RecipeDetailLoaded(this.detail);

  final RecipeDetail detail;
}

/// Loads a single recipe by id or slug.
class RecipeDetailCubit extends Cubit<RecipeDetailState> {
  RecipeDetailCubit(this._repository) : super(const RecipeDetailLoading());

  final RecipeRepository _repository;

  Future<void> load(String idOrSlug) async {
    emit(const RecipeDetailLoading());
    try {
      emit(RecipeDetailLoaded(await _repository.getRecipe(idOrSlug)));
    } on RepositoryException catch (exception) {
      emit(RecipeDetailError(exception.message));
    }
  }
}
