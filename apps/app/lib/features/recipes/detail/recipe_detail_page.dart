import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/photo_fallback.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/core/widgets/tag_chip.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/recipes/detail/recipe_detail_cubit.dart';

/// The recipe detail page (approved P2 design: two-column header on wide
/// screens — title/meta left, hero right — stacking on mobile).
class RecipeDetailPage extends StatelessWidget {
  const RecipeDetailPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Keyed by slug: navigating from one recipe straight to another reuses
      // this element, and an unkeyed provider would keep showing the old
      // recipe under the new URL.
      key: ValueKey(slug),
      create: (context) =>
          RecipeDetailCubit(context.read<RecipeRepository>())..load(slug),
      child: Scaffold(
        appBar: const SaltNavBar(showBack: true),
        body: BlocConsumer<RecipeDetailCubit, RecipeDetailState>(
          // Failed favorite/note writes surface as a SnackBar while the
          // recipe stays on screen.
          listenWhen: (previous, next) =>
              next is RecipeDetailLoaded && next.personalDataError != null,
          listener: (context, state) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  (state as RecipeDetailLoaded).personalDataError!,
                ),
              ),
            );
          },
          builder: (context, state) => switch (state) {
            RecipeDetailLoading() => const LoadingView(),
            RecipeDetailError(:final message) => ErrorView(
                message: message,
                onRetry: () =>
                    context.read<RecipeDetailCubit>().load(slug),
              ),
            RecipeDetailLoaded(:final detail) => _DetailBody(detail: detail),
          },
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final RecipeDetail detail;

  @override
  Widget build(BuildContext context) {
    final recipe = detail.recipe;
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(detail: detail),
                const SizedBox(height: 20),
                _MyNotesCard(detail: detail),
                const SizedBox(height: 22),
                if (recipe.prepNotes != null) ...[
                  _Headnote(text: recipe.prepNotes!),
                  const SizedBox(height: 22),
                ],
                _IngredientsAndSteps(recipe: recipe),
                for (final subsection in recipe.subsections) ...[
                  const SizedBox(height: 26),
                  _SubsectionView(subsection: subsection),
                ],
                for (final technique in recipe.techniques) ...[
                  const SizedBox(height: 26),
                  _TechniqueView(technique: technique),
                ],
                if (recipe.notes != null) ...[
                  const SizedBox(height: 26),
                  const _SectionTitle('Notes'),
                  const SizedBox(height: 8),
                  Text(recipe.notes!, style: _prose),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const TextStyle _prose =
    TextStyle(fontSize: 14.5, height: 1.6, color: Color(0xFF4A4442));

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final RecipeDetail detail;

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= Breakpoints.detailTwoColumn;
    final info = _HeaderInfo(detail: detail);
    final hero = _HeroImage(detail: detail);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(aspectRatio: 16 / 10, child: hero),
          const SizedBox(height: 18),
          info,
        ],
      );
    }
    // A bounded aspect ratio gives the network image a definite height —
    // Image.network reports no intrinsic size, so an IntrinsicHeight row
    // would leave it collapsed.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 11, child: info),
        const SizedBox(width: 28),
        Expanded(
          flex: 9,
          child: AspectRatio(aspectRatio: 4 / 3, child: hero),
        ),
      ],
    );
  }
}

class _HeaderInfo extends StatelessWidget {
  const _HeaderInfo({required this.detail});

  final RecipeDetail detail;

  @override
  Widget build(BuildContext context) {
    final recipe = detail.recipe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (recipe.category != null)
          Text(
            recipe.category!.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: SaltColors.rose,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          recipe.title,
          style: const TextStyle(
            fontSize: 29,
            height: 1.12,
            fontWeight: FontWeight.w700,
            color: SaltColors.maroon,
          ),
        ),
        if (recipe.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in recipe.tags)
                TagChip(
                  tag,
                  onTap: () => context.push(
                    '/search?q=${Uri.encodeQueryComponent(tagQuery(tag))}',
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _TimesStrip(recipe: recipe),
        if (recipe.background != null) ...[
          const SizedBox(height: 16),
          Text(recipe.background!, style: _prose),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  context.read<RecipeDetailCubit>().toggleFavorite(),
              icon: Icon(
                detail.favorite ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: SaltColors.maroon,
              ),
              label: Text(detail.favorite ? 'Favorited' : 'Favorite'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: SaltColors.maroon,
              ),
              onPressed: () => _downloadYaml(context, detail.recipe.slug),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download YAML'),
            ),
            if (context.watch<AuthCubit>().user?.isAdmin ?? false)
              OutlinedButton.icon(
                onPressed: () =>
                    context.push('/r/${detail.recipe.slug}/edit'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
          ],
        ),
      ],
    );
  }
}

/// The viewer's private note (approved P5 design): view mode with an Edit
/// affordance, or an inline editor. Collapsed to a subtle "Add a note"
/// action when empty — personal data, never in the shared YAML.
class _MyNotesCard extends StatefulWidget {
  const _MyNotesCard({required this.detail});

  final RecipeDetail detail;

  @override
  State<_MyNotesCard> createState() => _MyNotesCardState();
}

class _MyNotesCardState extends State<_MyNotesCard> {
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _controller =
      TextEditingController(text: widget.detail.note ?? '');

  @override
  void didUpdateWidget(covariant _MyNotesCard old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.detail.note != old.detail.note) {
      _controller.text = widget.detail.note ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved =
        await context.read<RecipeDetailCubit>().saveNote(_controller.text);
    if (mounted) {
      setState(() {
        _saving = false;
        // A failed save keeps the editor open with the text intact — closing
        // it would make the failure look like success.
        _editing = !saved;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.detail.note;
    if (note == null && !_editing) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _editing = true),
          icon: const Icon(Icons.sticky_note_2_outlined, size: 17),
          label: const Text('Add a private note'),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: SaltColors.panel,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'My notes',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: SaltColors.chipNeutral,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'ONLY YOU',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: SaltColors.muted,
                  ),
                ),
              ),
              const Spacer(),
              if (!_editing)
                TextButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_editing) ...[
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 8,
              autofocus: true,
              decoration: const InputDecoration(
                hintText:
                    'Anything future-you should know — tweaks, timings, '
                    'who loved it…',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: SaltColors.maroon),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save note'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _editing = false;
                            _controller.text = widget.detail.note ?? '';
                          }),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ] else
            Text(note ?? '', style: _prose),
        ],
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.detail});

  final RecipeDetail detail;

  @override
  Widget build(BuildContext context) {
    final url = detail.heroImageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: url == null
          ? const PhotoFallback(iconSize: 56)
          : Image.network(
              apiUrl(url),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const PhotoFallback(showIcon: false),
            ),
    );
  }
}

/// Opens the recipe's canonical YAML export in a new tab/download; surfaces a
/// SnackBar if the platform can't launch it.
Future<void> _downloadYaml(BuildContext context, String slug) async {
  final messenger = ScaffoldMessenger.of(context);
  final url = context.read<RecipeRepository>().yamlUrl(slug);
  var ok = false;
  try {
    ok = await launchUrl(url, mode: LaunchMode.platformDefault);
  } on Exception {
    ok = false;
  }
  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't open the download.")),
    );
  }
}

class _TimesStrip extends StatelessWidget {
  const _TimesStrip({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final serves = recipe.serves;
    final entries = <(String, String)>[
      if (serves != null)
        (
          'Serves',
          serves.min == serves.max
              ? '${serves.min}'
              : '${serves.min}–${serves.max}'
        )
      else if (recipe.servings != null)
        ('Yield', recipe.servings!),
      if (recipe.times.prep != null) ('Prep', '${recipe.times.prep} min'),
      if (recipe.times.cook != null) ('Cook', '${recipe.times.cook} min'),
      if (recipe.times.total != null) ('Total', '${recipe.times.total} min'),
    ];
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: SaltColors.hairline),
          bottom: BorderSide(color: SaltColors.hairline),
        ),
      ),
      child: Wrap(
        spacing: 26,
        runSpacing: 10,
        children: [
          for (final (label, value) in entries)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: SaltColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Headnote extends StatelessWidget {
  const _Headnote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SaltColors.chip.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: _prose.copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 14,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: SaltColors.maroon,
      ),
    );
  }
}

class _IngredientsAndSteps extends StatelessWidget {
  const _IngredientsAndSteps({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= Breakpoints.detailTwoColumn;
    final ingredients = _IngredientsList(groups: recipe.ingredients);
    final steps = _StepsList(steps: recipe.steps);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [ingredients, const SizedBox(height: 24), steps],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 320, child: ingredients),
        const SizedBox(width: 34),
        Expanded(child: steps),
      ],
    );
  }
}

class _IngredientsList extends StatelessWidget {
  const _IngredientsList({required this.groups});

  final List<IngredientGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Ingredients'),
        const SizedBox(height: 10),
        for (final group in groups) ...[
          if (group.group != null) ...[
            const SizedBox(height: 8),
            Text(
              group.group!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SaltColors.rose,
              ),
            ),
            const SizedBox(height: 4),
          ],
          for (final line in group.items)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: SaltColors.hairline),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7, right: 9),
                    decoration: const BoxDecoration(
                      color: SaltColors.rose,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line.raw,
                      style: const TextStyle(fontSize: 13.5, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _StepsList extends StatelessWidget {
  const _StepsList({required this.steps});

  final List<RecipeStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Directions'),
        const SizedBox(height: 10),
        for (final step in steps)
          Container(
            margin: const EdgeInsets.only(bottom: 11),
            padding: const EdgeInsets.fromLTRB(48, 13, 14, 13),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: SaltColors.hairline),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -35,
                  top: -1,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: SaltColors.maroon,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${step.number}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (step.label != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          step.label!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: SaltColors.rose,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    Text(
                      step.text,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: Color(0xFF3F3A38),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SubsectionView extends StatelessWidget {
  const _SubsectionView({required this.subsection});

  final Subsection subsection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subsection.title ?? 'Variation',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: SaltColors.maroon,
                  ),
                ),
              ),
              if (subsection.kind != null) TagChip(subsection.kind!),
            ],
          ),
          if (subsection.servings != null) ...[
            const SizedBox(height: 6),
            Text(
              subsection.servings!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SaltColors.muted,
              ),
            ),
          ],
          if (subsection.body != null) ...[
            const SizedBox(height: 8),
            Text(subsection.body!, style: _prose),
          ],
          if (subsection.prepNotes != null) ...[
            const SizedBox(height: 8),
            Text(
              subsection.prepNotes!,
              style: _prose.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          if (subsection.ingredients case final groups?
              when groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            _IngredientsList(groups: groups),
          ],
          if (subsection.steps case final steps? when steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            _StepsList(steps: steps),
          ],
        ],
      ),
    );
  }
}

class _TechniqueView extends StatelessWidget {
  const _TechniqueView({required this.technique});

  final Technique technique;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SaltColors.chip.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (technique.heading != null)
            Text(
              technique.heading!,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: SaltColors.maroon,
                letterSpacing: 0.6,
              ),
            ),
          if (technique.description != null) ...[
            const SizedBox(height: 6),
            Text(technique.description!, style: _prose),
          ],
          for (final step in technique.steps) ...[
            const SizedBox(height: 10),
            Text(
              '${step.number}. ${step.caption}',
              style: _prose.copyWith(fontSize: 13.5),
            ),
          ],
        ],
      ),
    );
  }
}
