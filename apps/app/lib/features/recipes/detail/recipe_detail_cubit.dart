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
  const RecipeDetailLoaded(this.detail, {this.personalDataError});

  final RecipeDetail detail;

  /// Message of the last failed favorite/note write, cleared on the next
  /// successful one — the page shows it as a SnackBar-worthy notice while
  /// the recipe itself stays on screen.
  final String? personalDataError;
}

/// Loads a single recipe by id or slug and mutates the viewer's personal
/// data (favorite mark, private note).
class RecipeDetailCubit extends Cubit<RecipeDetailState> {
  RecipeDetailCubit(this._repository) : super(const RecipeDetailLoading());

  final RecipeRepository _repository;
  bool _togglingFavorite = false;

  Future<void> load(String idOrSlug) async {
    emit(const RecipeDetailLoading());
    try {
      final detail = await _repository.getRecipe(idOrSlug);
      if (isClosed) {
        return;
      }
      emit(RecipeDetailLoaded(detail));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(RecipeDetailError(exception.message));
    }
  }

  /// Flips the favorite mark optimistically, reverting on failure. Ignores
  /// re-entrant taps while a toggle is still in flight so a double-tap
  /// cannot desync the heart from the server.
  Future<void> toggleFavorite() async {
    final current = state;
    if (current is! RecipeDetailLoaded || _togglingFavorite) {
      return;
    }
    _togglingFavorite = true;
    final target = !current.detail.favorite;
    emit(RecipeDetailLoaded(current.detail.copyWith(favorite: target)));
    try {
      await _repository.setFavorite(current.detail.recipe.id, favorite: target);
    } on RepositoryException catch (exception) {
      if (!isClosed) {
        emit(
          RecipeDetailLoaded(
            current.detail,
            personalDataError: exception.message,
          ),
        );
      }
    } finally {
      _togglingFavorite = false;
    }
  }

  /// Saves (or, with an empty string, deletes) the viewer's private note.
  /// Returns whether the write succeeded, so the editor card can stay open
  /// on failure instead of pretending the note was saved.
  Future<bool> saveNote(String note) async {
    final current = state;
    if (current is! RecipeDetailLoaded) {
      return false;
    }
    try {
      final stored = await _repository.setNote(
        current.detail.recipe.id,
        note.trim(),
      );
      if (!isClosed) {
        emit(
          RecipeDetailLoaded(
            current.detail.copyWith(note: stored, clearNote: stored == null),
          ),
        );
      }
      return true;
    } on RepositoryException catch (exception) {
      if (!isClosed) {
        emit(
          RecipeDetailLoaded(
            current.detail,
            personalDataError: exception.message,
          ),
        );
      }
      return false;
    }
  }
}
