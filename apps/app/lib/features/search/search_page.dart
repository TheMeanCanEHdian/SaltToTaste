import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/recipe_grid.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/recipes/list/recipe_list_cubit.dart';

/// Search results for a DSL [query]: the shared grid with a result-count
/// eyebrow, plus a syntax-help affordance.
class SearchPage extends StatelessWidget {
  const SearchPage({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey(query),
      create: (context) => RecipeListCubit(
        context.read<RecipeRepository>(),
        query: query,
      )..load(),
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
                  eyebrowBuilder: (state) =>
                      '${state.total} RESULTS · ${query.toUpperCase()}',
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.small(
            backgroundColor: SaltColors.maroon,
            foregroundColor: Colors.white,
            tooltip: 'Search syntax',
            onPressed: () => showSearchHelp(context),
            child: const Icon(Icons.question_mark),
          ),
        ),
      ),
    );
  }
}

/// The search-DSL cheat sheet. The semantics deliberately follow modern
/// search conventions (documented decisions): a scope binds one term, and
/// adjacent terms all narrow the results.
void showSearchHelp(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Search syntax'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _HelpRow('chicken soup', 'recipes containing both words'),
            _HelpRow('"sweet potato"', 'exact phrase'),
            _HelpRow('title:cake', 'scoped to the title (one word)'),
            _HelpRow('title:"bundt cake"', 'scoped phrase'),
            _HelpRow('tag:dessert or title:pie', 'either side'),
            _HelpRow('ingredient:ginger and direction:"dutch oven"',
                'combine scopes'),
            _HelpRow('calories:<400', 'calorie filter (needs nutrition)'),
            SizedBox(height: 10),
            Text(
              'Scopes: title, tag, ingredient, direction, note. '
              'Words next to each other all need to match; use "or" to '
              'broaden. Scopes apply to the single word or "quoted phrase" '
              'after them.',
              style: TextStyle(fontSize: 13, color: SaltColors.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _HelpRow extends StatelessWidget {
  const _HelpRow(this.example, this.meaning);

  final String example;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF4EFE9),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              example,
              style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              meaning,
              style:
                  const TextStyle(fontSize: 13, color: SaltColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
