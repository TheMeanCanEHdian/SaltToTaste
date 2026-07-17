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
    // A SingleChildScrollView (not a lazy ListView) so the scroll extent is
    // measured exactly — the scrollbar thumb tracks correctly instead of
    // jumping. It spans the full width so the bar sits at the viewport edge;
    // the content is centred and capped at the app's 1100px width.
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Recipe review',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: SaltColors.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.help_outline, size: 20),
                      color: SaltColors.muted,
                      tooltip: 'What each category means',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _showReviewHelp(context, state.categories),
                    ),
                  ],
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
                if (state.items.isEmpty)
                  const _Empty()
                else
                  FTileGroup(
                    children: [
                      for (final item in state.items)
                        _reviewTile(context, item),
                    ],
                  ),
                if (state.hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Center(
                      child: FButton(
                        variant: FButtonVariant.outline,
                        mainAxisSize: MainAxisSize.min,
                        onPress: state.loadingMore ? null : cubit.loadMore,
                        child: Text(
                          state.loadingMore ? 'Loading…' : 'Load more',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
            // A category with nothing to show isn't a useful filter.
            enabled: category.count > 0,
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
    this.enabled = true,
  });

  final String label;
  final int count;
  final bool selected;
  final bool emphasized;

  /// A disabled chip (a category with a count of 0) is greyed and not tappable.
  final bool enabled;
  final VoidCallback onTap;

  static const Color _disabled = Color(0xFFBCB3AC);

  @override
  Widget build(BuildContext context) {
    // Selection alone drives the fill; "Need attention" is only emphasised by
    // its maroon number, so it no longer looks selected when it isn't.
    final border = !enabled
        ? SaltColors.hairline
        : (selected ? SaltColors.maroon : SaltColors.hairline);
    final bg = !enabled
        ? const Color(0xFFFBF9F7)
        : (selected ? const Color(0xFFF7ECEC) : Colors.white);
    final numberColor = !enabled
        ? _disabled
        : (emphasized || selected ? SaltColors.maroon : SaltColors.ink);
    final labelColor = enabled ? SaltColors.muted : _disabled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
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
                  color: numberColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
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

/// Opens a modal explaining every category, driven by the server-provided
/// descriptions — so a check added on the server documents itself here.
void _showReviewHelp(
  BuildContext context,
  List<RecipeReviewCategory> categories,
) {
  showFDialog<void>(
    context: context,
    builder: (context, _, animation) => FDialog(
      animation: animation,
      builder: (context, style) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              'What each category means',
              style: style.titleTextStyle,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final category in categories) _HelpRow(category),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.centerRight,
              child: FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HelpRow extends StatelessWidget {
  const _HelpRow(this.category);

  final RecipeReviewCategory category;

  @override
  Widget build(BuildContext context) {
    final (bg, ink) = _issueColors(category.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              category.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            category.description,
            style: const TextStyle(
              fontSize: 13.5,
              color: SaltColors.bodyText,
              height: 1.4,
            ),
          ),
        ],
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
