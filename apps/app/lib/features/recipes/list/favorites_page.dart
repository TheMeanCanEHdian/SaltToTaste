import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/widgets/recipe_grid.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/recipes/list/recipe_list_cubit.dart';

/// The signed-in user's favorites as a grid (approved P5 design); tapping a
/// tile's heart removes it from the list.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RecipeListCubit(
        context.read<RecipeRepository>(),
        favoritesOnly: true,
      )..load(),
      child: Scaffold(
        appBar: const SaltNavBar(showBack: true),
        body: RecipeGrid(
          eyebrowBuilder: (state) => 'MY FAVORITES · ${state.total}',
          emptyMessage:
              'No favorites yet — tap the heart on any recipe to keep it '
              'here.',
        ),
      ),
    );
  }
}
