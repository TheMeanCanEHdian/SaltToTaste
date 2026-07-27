import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/recipe_row.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/core/widgets/recipe_tile.dart';
import 'package:salt_app/features/recipes/list/recipe_layout_cubit.dart';
import 'package:salt_app/features/recipes/list/recipe_list_cubit.dart';

/// An active filter narrowing the list — the search query, or "My favorites".
/// Rendered as a clearable pill after the count; [onClear] drops it (both
/// current callers return to the home library).
class RecipeListFilter {
  const RecipeListFilter({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;
}

/// The responsive recipe list, driven by the enclosing [RecipeListCubit]
/// (whole library on the home page, results on the search page) and the
/// app-wide [RecipeLayoutCubit] (photo grid or compact rows).
///
/// The header row shows [countLabel] (e.g. "247 RECIPES"), an optional
/// clearable [filter] pill, and the grid/list selector.
class RecipeGrid extends StatefulWidget {
  const RecipeGrid({
    super.key,
    required this.countLabel,
    this.filter,
    this.emptyMessage = 'No recipes match.',
  });

  /// The count text shown at the left of the header (the page decides the
  /// noun — "RECIPES" on the library, "RESULTS" on a search).
  final String Function(RecipeListLoaded state) countLabel;

  /// The active filter pill, or null on the plain library listing.
  final RecipeListFilter? filter;

  /// Shown when the list is empty (the favorites page words it differently
  /// than a search with no hits).
  final String emptyMessage;

  @override
  State<RecipeGrid> createState() => _RecipeGridState();
}

class _RecipeGridState extends State<RecipeGrid> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
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
    final layout = context.watch<RecipeLayoutCubit>().state;
    return BlocBuilder<RecipeListCubit, RecipeListState>(
      builder: (context, state) => switch (state) {
        RecipeListLoading() => const LoadingView(),
        RecipeListError(:final message) => ErrorView(
          message: message,
          onRetry: () => context.read<RecipeListCubit>().load(),
        ),
        RecipeListLoaded() => LayoutBuilder(
          builder: (context, constraints) {
            return CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: _HeaderRow(
                      countLabel: widget.countLabel(state),
                      filter: widget.filter,
                    ),
                  ),
                ),
                if (state.items.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          widget.emptyMessage,
                          style: const TextStyle(
                            fontSize: 15,
                            color: SaltColors.muted,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (layout == RecipeLayout.list)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    sliver: SliverList.separated(
                      itemCount: state.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final card = state.items[index];
                        return RecipeRow(
                          card: card,
                          onTap: () => context.push('/r/${card.slug}'),
                        );
                      },
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _columnsFor(constraints.maxWidth),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 4 / 3,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final card = state.items[index];
                        return RecipeTile(
                          card: card,
                          onTap: () => context.push('/r/${card.slug}'),
                        );
                      }, childCount: state.items.length),
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

/// The header above the list: the count and an optional clearable filter chip
/// (left), and the grid/list layout selector pushed to the far right.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.countLabel, this.filter});

  final String countLabel;
  final RecipeListFilter? filter;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // The count + filter take the free space; the selector is pushed to the
        // far right. The pill sits in a Flexible so a long search query
        // ellipsizes (a pixel bound) rather than shoving the selector off-row —
        // the full query still shows in the nav search field.
        Expanded(
          child: Row(
            children: [
              // liveRegion so the "N recipes / N results" count is announced
              // after a search or reload.
              Semantics(
                liveRegion: true,
                child: Text(
                  countLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: SaltColors.rose,
                  ),
                ),
              ),
              if (filter != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: SaltBadge(
                    filter!.label,
                    onDismiss: filter!.onClear,
                    dismissHint: 'Clear filter',
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        const _LayoutToggle(),
      ],
    );
  }
}

/// The grid/list selector: two Forui icon buttons. The theme paints the
/// variant — selected = primary (maroon), unselected = ghost (grey) — so no
/// colour is set per-widget (see CLAUDE.md's button system).
class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle();

  @override
  Widget build(BuildContext context) {
    final current = context.watch<RecipeLayoutCubit>().state;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LayoutButton(
          icon: FLucideIcons.layoutGrid,
          label: 'Grid view',
          selected: current == RecipeLayout.grid,
          onPress: () =>
              context.read<RecipeLayoutCubit>().select(RecipeLayout.grid),
        ),
        const SizedBox(width: 4),
        _LayoutButton(
          icon: FLucideIcons.list,
          label: 'List view',
          selected: current == RecipeLayout.list,
          onPress: () =>
              context.read<RecipeLayoutCubit>().select(RecipeLayout.list),
        ),
      ],
    );
  }
}

class _LayoutButton extends StatelessWidget {
  const _LayoutButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    // Selected = the solid `primary` maroon; unselected = `ghost` (grey) — the
    // theme paints both. NOT Forui's `selected` flag: that repaints primary in
    // its lighter hover tint, which read as the wrong (too-light) red. Selected
    // state is carried in semantics instead.
    //
    // `excludeFromSemantics` on the Tooltip so it doesn't add its own
    // `tooltip: label` node — the explicit Semantics below already names the
    // button, and both would make a screen reader announce the name twice.
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onPress,
        child: ExcludeSemantics(
          child: FButton.icon(
            variant: selected ? FButtonVariant.primary : FButtonVariant.ghost,
            size: FButtonSizeVariant.xs,
            onPress: onPress,
            child: Icon(icon, size: 18),
          ),
        ),
      ),
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
              FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () => context.read<RecipeListCubit>().retryLoadMore(),
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
          child: CircularProgressIndicator(
            color: SaltColors.maroon,
            semanticsLabel: 'Loading more recipes',
          ),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}
