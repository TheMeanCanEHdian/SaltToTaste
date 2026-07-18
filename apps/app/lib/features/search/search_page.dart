import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/widgets/recipe_grid.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/recipes/list/recipe_list_cubit.dart';

/// Search results for a DSL [query]: the shared grid with a result-count
/// eyebrow. The syntax-help affordance lives in the nav bar's search field
/// (the `?` beside the search button).
class SearchPage extends StatelessWidget {
  const SearchPage({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey(query),
      create: (context) =>
          RecipeListCubit(context.read<RecipeRepository>(), query: query)
            ..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: SaltNavBar(
            showBack: true,
            initialQuery: query,
            onSearchRefresh: () => context.read<RecipeListCubit>().load(),
          ),
          body: Column(
            children: [
              Expanded(
                child: RecipeGrid(
                  countLabel: (state) => '${state.total} RESULTS',
                  // The query rides as a clearable pill; ✕ returns to the
                  // whole library.
                  filter: RecipeListFilter(
                    label: query,
                    onClear: () => context.go('/'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
