import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/recipe_tile.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/recipes/list/recipe_list_cubit.dart';

/// The home page: nav bar + responsive recipe grid with infinite scroll.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          RecipeListCubit(context.read<RecipeRepository>())..load(),
      child: const Scaffold(
        appBar: SaltNavBar(),
        body: _RecipeGrid(),
      ),
    );
  }
}

class _RecipeGrid extends StatefulWidget {
  const _RecipeGrid();

  @override
  State<_RecipeGrid> createState() => _RecipeGridState();
}

class _RecipeGridState extends State<_RecipeGrid> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 600) {
        context.read<RecipeListCubit>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static int _columnsFor(double width) {
    if (width >= Breakpoints.wide) return 4;
    if (width >= Breakpoints.medium) return 3;
    if (width >= Breakpoints.compact) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RecipeListCubit, RecipeListState>(
      builder: (context, state) => switch (state) {
        RecipeListLoading() => const LoadingView(),
        RecipeListError(:final message) => ErrorView(
            message: message,
            onRetry: () => context.read<RecipeListCubit>().load(),
          ),
        RecipeListLoaded() => LayoutBuilder(
            builder: (context, constraints) {
              final columns = _columnsFor(constraints.maxWidth);
              return CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'HOME · ${state.total} RECIPES',
                        style: const TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w700,
                          color: SaltColors.rose,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 4 / 3,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final card = state.items[index];
                          return RecipeTile(
                            card: card,
                            onTap: () => context.push('/r/${card.slug}'),
                          );
                        },
                        childCount: state.items.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _GridFooter(state: state)),
                ],
              );
            },
          ),
      },
    );
  }
}

/// Below-the-grid footer: a spinner while paging, or a retry row when a page
/// failed (so a transient error mid-scroll isn't a silent dead end).
class _GridFooter extends StatelessWidget {
  const _GridFooter({required this.state});

  final RecipeListLoaded state;

  @override
  Widget build(BuildContext context) {
    if (state.loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 28, top: 4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Couldn't load more recipes.",
                style: TextStyle(color: SaltColors.muted),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    context.read<RecipeListCubit>().retryLoadMore(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 28),
        child: Center(
          child: CircularProgressIndicator(color: SaltColors.maroon),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}
