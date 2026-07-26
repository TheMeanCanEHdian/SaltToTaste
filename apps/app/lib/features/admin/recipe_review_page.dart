import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/core/widgets/stat_chip.dart';
import 'package:salt_app/features/admin/nutrition_review_cubit.dart';
import 'package:salt_app/features/admin/nutrition_review_queue.dart';
import 'package:salt_app/features/admin/recipe_review_cubit.dart';

/// Admin data-quality review, in two tabs: recipes the server flagged (missing
/// or incomplete data) and the cross-recipe nutrition-match queue. Reached from
/// the profile menu (admin only).
class RecipeReviewPage extends StatelessWidget {
  const RecipeReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<RecipeRepository>();
    // Both cubits live at the page so each tab's live total shows in its label
    // and switching tabs never reloads.
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => RecipeReviewCubit(repository)..load()),
        BlocProvider(create: (_) => NutritionReviewCubit(repository)..load()),
      ],
      child: const Scaffold(
        appBar: SaltNavBar(showBack: true),
        body: _ReviewTabs(),
      ),
    );
  }
}

/// The shared heading over the two-tab body. Both tab labels carry their
/// cubit's live total once loaded.
class _ReviewTabs extends StatefulWidget {
  const _ReviewTabs();

  @override
  State<_ReviewTabs> createState() => _ReviewTabsState();
}

class _ReviewTabsState extends State<_ReviewTabs>
    with TickerProviderStateMixin {
  late final FTabController _tabs = FTabController(length: 2, vsync: this);
  int _tabIndex = 0;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipeState = context.watch<RecipeReviewCubit>().state;
    final nutritionState = context.watch<NutritionReviewCubit>().state;
    final recipeCount = recipeState is RecipeReviewLoaded
        ? recipeState.total
        : null;
    final nutritionCount = nutritionState is NutritionReviewLoaded
        ? nutritionState.total
        : null;
    final categories = recipeState is RecipeReviewLoaded
        ? recipeState.categories
        : const <RecipeReviewCategory>[];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
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
                  // The category help applies to the Recipes tab only, but its
                  // space is always reserved (maintainSize) so the heading — and
                  // everything below it — never jumps vertically when switching
                  // tabs (the icon button is taller than the title text).
                  Visibility(
                    visible: _tabIndex == 0 && categories.isNotEmpty,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Tooltip(
                      message: 'What each category means',
                      child: FButton.icon(
                        variant: FButtonVariant.ghost,
                        size: FButtonSizeVariant.xs,
                        semanticsLabel: 'What each category means',
                        onPress: () => _showReviewHelp(context, categories),
                        child: const Icon(Icons.help_outline, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Recipes and ingredient matches the server flagged for a look. '
                'Fix them here or open the full recipe.',
                style: TextStyle(fontSize: 14, color: SaltColors.muted),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: FTabs(
                  control: FTabManagedControl(
                    controller: _tabs,
                    onChange: (index) => setState(() => _tabIndex = index),
                  ),
                  // Round the grey track on this page (the theme keeps it square
                  // for the full-bleed review-sheet tabs); the white bordered
                  // indicator from the theme is inherited.
                  style: FTabsStyleDelta.delta(
                    decoration: DecorationDelta.value(
                      const BoxDecoration(
                        color: SaltColors.chipNeutral,
                        borderRadius: BorderRadius.all(Radius.circular(9)),
                      ),
                    ),
                  ),
                  expands: true,
                  // The bar switches views; each tab scrolls on its own.
                  contentPhysics: const NeverScrollableScrollPhysics(),
                  children: [
                    FTabEntry(
                      label: Text(
                        recipeCount == null
                            ? 'Recipes'
                            : 'Recipes · $recipeCount',
                      ),
                      child: const _RecipesTab(),
                    ),
                    FTabEntry(
                      label: Text(
                        nutritionCount == null
                            ? 'Nutrition matches'
                            : 'Nutrition matches · $nutritionCount',
                      ),
                      child: const NutritionReviewQueue(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The recipes tab: the flagged-recipe list, driven by [RecipeReviewCubit].
class _RecipesTab extends StatelessWidget {
  const _RecipesTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RecipeReviewCubit, RecipeReviewState>(
      builder: (context, state) => switch (state) {
        RecipeReviewLoading() => const LoadingView(),
        RecipeReviewError(:final message) => ErrorView(
          message: message,
          onRetry: () => context.read<RecipeReviewCubit>().load(),
        ),
        RecipeReviewLoaded() => _RecipesList(state: state),
      },
    );
  }
}

class _RecipesList extends StatelessWidget {
  const _RecipesList({required this.state});

  final RecipeReviewLoaded state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RecipeReviewCubit>();
    // A SingleChildScrollView (not a lazy ListView) so the scroll extent is
    // measured exactly — the scrollbar thumb tracks correctly instead of
    // jumping.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Filters(state: state, onSelect: cubit.filter),
          const SizedBox(height: 18),
          if (state.items.isEmpty)
            const _Empty()
          else
            FTileGroup(
              children: [
                for (final item in state.items) _reviewTile(context, item),
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
                  child: Text(state.loadingMore ? 'Loading…' : 'Load more'),
                ),
              ),
            ),
        ],
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
          children: [
            for (final issue in item.issues)
              SaltBadge(issue.label, tone: _issueTone(issue.check)),
          ],
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
        StatChip(
          label: 'Need attention',
          count: state.total,
          selected: state.issue == null,
          emphasized: true,
          onTap: () => onSelect(null),
        ),
        for (final category in state.categories)
          StatChip(
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

/// Maps a check id to a badge tone. Red = blocking, amber = needs fixing, grey
/// = missing/informational. Unknown ids (a check added on the server the app
/// doesn't know yet) fall back to neutral.
SaltBadgeTone _issueTone(String check) => switch (check) {
  'no_instructions' => SaltBadgeTone.err,
  'unparsed_ingredients' => SaltBadgeTone.warn,
  'extraction_warnings' => SaltBadgeTone.warn,
  'incomplete_nutrition' => SaltBadgeTone.warn,
  _ => SaltBadgeTone.neutral,
};

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
