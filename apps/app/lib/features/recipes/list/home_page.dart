import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/widgets/recipe_grid.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/recipes/list/recipe_list_cubit.dart';

/// The home page: nav bar + the whole library as a responsive grid.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          RecipeListCubit(context.read<RecipeRepository>())..load(),
      child: Scaffold(
        appBar: const SaltNavBar(),
        body: RecipeGrid(
          eyebrowBuilder: (state) => 'HOME · ${state.total} RECIPES',
        ),
      ),
    );
  }
}
