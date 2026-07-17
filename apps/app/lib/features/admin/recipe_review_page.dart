import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/admin/recipe_review_cubit.dart';

/// Admin recipe data-quality review: recipes missing or with incomplete data,
/// grouped by issue. Reached from the profile menu (admin only).
class RecipeReviewPage extends StatelessWidget {
  const RecipeReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          RecipeReviewCubit(context.read<RecipeRepository>())..load(),
      child: Scaffold(
        appBar: const SaltNavBar(showBack: true),
        body: BlocBuilder<RecipeReviewCubit, RecipeReviewState>(
          builder: (context, state) => switch (state) {
            RecipeReviewLoading() => const LoadingView(),
            RecipeReviewError(:final message) => ErrorView(
              message: message,
              onRetry: () => context.read<RecipeReviewCubit>().load(),
            ),
            RecipeReviewLoaded() => _Loaded(state: state),
          },
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final RecipeReviewLoaded state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RecipeReviewCubit>();
    // The scroll view spans the full width so its scrollbar sits at the
    // viewport edge (natural for a web page); each block is centred and capped
    // at the app's 1100px content width.
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        _centered(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recipe review',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: SaltColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Recipes the server flagged as missing or incomplete data. '
                'Open one to fix it in the editor or the nutrition review.',
                style: TextStyle(fontSize: 14, color: SaltColors.muted),
              ),
              const SizedBox(height: 18),
              _Filters(state: state, onSelect: cubit.filter),
              const SizedBox(height: 18),
            ],
          ),
        ),
        if (state.items.isEmpty)
          _centered(const _Empty())
        else
          _centered(
            FTileGroup(
              children: [
                for (final item in state.items) _reviewTile(context, item),
              ],
            ),
          ),
        if (state.hasMore)
          _centered(
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: FButton(
                  variant: FButtonVariant.outline,
                  mainAxisSize: MainAxisSize.min,
                  onPress: state.loadingMore ? null : cubit.loadMore,
                  child: Text(state.loadingMore ? 'Loading…' : 'Load more'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Centres [child] and caps it at the content width, with horizontal padding.
  Widget _centered(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    ),
  );

  FTile _reviewTile(BuildContext context, RecipeReviewItem item) {
    return FTile(
      title: Text(item.title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final issue in item.issues) _IssueBadge(issue)],
        ),
      ),
      suffix: const Icon(Icons.chevron_right, color: SaltColors.muted),
      onPress: () => context.push('/r/${item.slug}'),
    );
  }
}

/// The count chips that double as the category filter. Selecting one narrows
/// the list; "All" clears it.
class _Filters extends StatelessWidget {
  const _Filters({required this.state, required this.onSelect});

  final RecipeReviewLoaded state;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _StatChip(
          label: 'Need attention',
          count: state.total,
          selected: state.issue == null,
          emphasized: true,
          onTap: () => onSelect(null),
        ),
        for (final category in state.categories)
          _StatChip(
            label: category.label,
            count: category.count,
            selected: state.issue == category.id,
            onTap: () => onSelect(category.id),
          ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final int count;
  final bool selected;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected ? SaltColors.maroon : SaltColors.hairline;
    // Selection alone drives the fill; "Need attention" is only emphasised by
    // its maroon number, so it no longer looks selected when it isn't.
    final bg = selected ? const Color(0xFFF7ECEC) : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 104),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: emphasized || selected
                      ? SaltColors.maroon
                      : SaltColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: SaltColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A coloured pill naming one issue on a recipe. The specific detail (e.g. the
/// nutrition ratio, the unparsed line) lives on the recipe the row opens.
class _IssueBadge extends StatelessWidget {
  const _IssueBadge(this.issue);

  final RecipeReviewIssue issue;

  @override
  Widget build(BuildContext context) {
    final (bg, ink) = _issueColors(issue.check);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        issue.label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
      ),
    );
  }
}

/// Maps a check id to a severity colour pair. Red = blocking, amber = needs
/// fixing, grey = missing/informational. Nothing uses green — an issue should
/// never read as a good thing. Unknown ids (a check added on the server the app
/// doesn't know yet) fall back to neutral.
(Color, Color) _issueColors(String checkId) => switch (checkId) {
  'no_instructions' => (SaltColors.errBg, SaltColors.errInk),
  'unparsed_ingredients' => (SaltColors.warnBg, SaltColors.warnInk),
  'extraction_warnings' => (SaltColors.warnBg, SaltColors.warnInk),
  'incomplete_nutrition' => (SaltColors.warnBg, SaltColors.warnInk),
  _ => (SaltColors.chipNeutral, SaltColors.muted),
};

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.check_circle_outline, size: 40, color: SaltColors.okInk),
            SizedBox(height: 12),
            Text(
              'Nothing to review here.',
              style: TextStyle(fontSize: 15, color: SaltColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
