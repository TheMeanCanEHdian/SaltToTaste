import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the recipe list renders its cards.
enum RecipeLayout {
  /// The photo-tile grid (the default).
  grid,

  /// One row per recipe: thumbnail + title + meta + tags + favorite.
  list,
}

/// The user's chosen list layout, shared across the home, search, and
/// favorites lists and persisted across reloads.
///
/// The choice is stored in [SharedPreferences] (browser localStorage on web),
/// read synchronously at construction so the first paint is already the right
/// layout — no flash of grid. [prefs] is optional: without it the cubit is
/// in-memory only (tests, or if prefs failed to load), defaulting to
/// [RecipeLayout.grid].
class RecipeLayoutCubit extends Cubit<RecipeLayout> {
  RecipeLayoutCubit([this._prefs]) : super(_read(_prefs));

  /// The preferences key holding the layout's [RecipeLayout.name].
  static const String prefsKey = 'recipe_layout';

  final SharedPreferences? _prefs;

  static RecipeLayout _read(SharedPreferences? prefs) {
    return switch (prefs?.getString(prefsKey)) {
      'list' => RecipeLayout.list,
      _ => RecipeLayout.grid,
    };
  }

  void select(RecipeLayout layout) {
    if (layout == state) {
      return;
    }
    emit(layout);
    // Persist best-effort. The in-memory switch already took; a storage
    // failure (quota, or localStorage blocked in a private-mode web context)
    // must not surface as an unhandled async error, so swallow a rejected
    // write.
    final prefs = _prefs;
    if (prefs != null) {
      unawaited(prefs.setString(prefsKey, layout.name).catchError((_) => false));
    }
  }
}
