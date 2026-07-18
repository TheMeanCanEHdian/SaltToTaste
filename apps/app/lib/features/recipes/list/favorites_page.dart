import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/widgets/recipe_grid.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/recipes/list/recipe_list_cubit.dart';

/// The signed-in user's favorites as a grid (approved P5 design).
///
/// The tile heart is an indicator, not a control — unfavoriting happens on
/// the recipe page. This grid stays alive under that page, so its cubit
/// reconciles from `RecipeRepository.favoriteChanges` and the card is gone
/// by the time the user comes back.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          RecipeListCubit(context.read<RecipeRepository>(), favoritesOnly: true)
            ..load(),
      child: Scaffold(
        appBar: const SaltNavBar(showBack: true),
        body: RecipeGrid(
          countLabel: (state) => '${state.total} RECIPES',
          // Favorites reads like a filter on the library: count first, then a
          // clearable pill whose ✕ returns to the whole library.
          filter: RecipeListFilter(
            label: 'My favorites',
            onClear: () => context.go('/'),
          ),
          emptyMessage:
              'No favorites yet — tap the heart on any recipe to keep it '
              'here.',
        ),
      ),
    );
  }
}
