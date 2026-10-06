import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:salt_shared/salt_shared.dart' show HoldDecision, parseQuantity;

import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';
import 'package:salt_app/features/nutrition/nutrition_cubit.dart';

/// The recipe a review sheet belongs to, as its fix panels name it: its
/// title, and whether it has sections of its own (null when unknown) — the
/// empty "This recipe's sections" group reads by it (A4).
typedef ReviewParent = ({String title, bool? hasSections});

/// The fix panel of a reference line (v41, mockup §2): it chooses a recipe,
/// not a food. The candidates come in the engine's resolution order; a
/// section is a recipe too (v44), picked by its host's slug AND its title;
/// the library search finds any other recipe. ONE primary button follows the selection and the share
/// field, as the amount block's Confirm follows its number (C1). Nothing is
/// written until it is pressed, and success is observed by the host from
/// cubit state (review B5/B6), never assumed here.
class RecipeFixPanel extends StatefulWidget {
  const RecipeFixPanel({
    super.key,
    required this.match,
    required this.busy,
    this.parent,
    this.onSkip,
  });

  final IngredientMatch match;
  final bool busy;
  final ReviewParent? parent;

  /// The ghost Skip beside the primary button; null for none (a host with
  /// its own skip).
  final VoidCallback? onSkip;

  @override
  State<RecipeFixPanel> createState() => _RecipeFixPanelState();
}

/// [title] less the words of the line's [item] ("All-Butter" of
/// "All-Butter Double-Crust Pie Dough" for "double-crust pie dough"), else
/// the whole title.
String shortTitle(String title, String? item) {
  final words = (item ?? '').toLowerCase().split(RegExp(r'\s+')).toSet();
  final kept = [
    for (final word in title.split(' '))
      if (!words.contains(word.toLowerCase())) word,
  ].join(' ');
  return kept.isEmpty ? title : kept;
}

class _RecipeFixPanelState extends State<RecipeFixPanel> {
  /// A recipe (or section) picked here, not yet written.
  RecipeCandidate? _staged;
  final TextEditingController _share = TextEditingController();
  String _unit = 'recipe';
  bool _dirty = false;
  bool _setting = false;
  String _last = '';

  final TextEditingController _term = TextEditingController();
  List<RecipeCandidate>? _results;
  bool _searching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _reset();
    _share.addListener(_onChanged);
  }

  /// A poured-away marinade (S10 (a)): the share eaten is a person's — the
  /// field starts empty and a pick waits on it.
  bool get _marinade => widget.match.hold == 'discarded_recipe';

  void _reset() {
    _setting = true;
    _share.text = _marinade ? '' : widget.match.child?.shareText ?? '';
    _setting = false;
    _last = _share.text;
    _unit = 'recipe';
    _dirty = false;
  }

  void _onChanged() {
    if (!_setting && _share.text != _last) {
      _dirty = true;
    }
    _last = _share.text;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(RecipeFixPanel old) {
    super.didUpdateWidget(old);
    // A save landed (or the panel stands on another line now): what was
    // staged and typed was for the row as it was.
    final was = old.match.child;
    final now = widget.match.child;
    if (old.match.raw != widget.match.raw ||
        was?.key != now?.key ||
        was?.shareText != now?.shareText ||
        old.match.status != widget.match.status) {
      _staged = null;
      _reset();
    }
  }

  @override
  void dispose() {
    _share.removeListener(_onChanged);
    _share.dispose();
    _term.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final term = _term.text.replaceAll('"', ' ').trim();
    if (term.isEmpty || _searching) {
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    final recipes = context.read<RecipeRepository>();
    final nutrition = context.read<NutritionRepository>();
    final self = context.read<NutritionCubit>().idOrSlug;
    try {
      final page = await recipes.listRecipes(
        page: 1,
        limit: 10,
        query: 'title:"$term"',
      );
      final found = <RecipeCandidate>[];
      for (final card in page.items) {
        if (card.slug == self || card.id == self) {
          continue;
        }
        // One label read per result: its batch calories, and whether it has
        // totals to count (the PUT refuses a recipe without).
        RecipeNutrition? label;
        try {
          label = await nutrition.nutrition(card.slug);
        } on RepositoryException {
          label = null;
        }
        final perServing = label?.caloriesPerServing;
        final batch = label == null || !label.exists || perServing == null
            ? null
            : perServing * (label.servingBasis ?? 1);
        found.add(
          RecipeCandidate(
            group: 'search',
            title: card.title,
            slug: card.slug,
            note: 'search result',
            yieldText: card.servingsText,
            kcal: batch,
            pickable: batch != null,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _results = found;
          _searching = false;
        });
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() {
          _searchError = exception.message;
          _searching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NutritionCubit>();
    final m = widget.match;
    final c = m.child!;
    final busy = widget.busy;
    final routedSlug = c.state == 'routed' ? c.slug : null;
    final current = routedSlug == null ? null : c.key;
    final pick = _staged;
    final selected = pick?.key ?? current;
    final staged = pick != null && pick.key != current;
    // The share field offers only the units the child's yield can read —
    // and reads only one of them: the toggle, the label and the PUT's
    // share all take [unit], never a unit the selected recipe lacks.
    final units = !staged && c.yieldUnits.isNotEmpty
        ? c.yieldUnits
        : const [(unit: 'recipe', perRecipe: 1.0)];
    final (:unit, :perRecipe) = units.firstWhere(
      (u) => u.unit == _unit,
      orElse: () => units.first,
    );
    final typed = parseQuantity(_share.text);
    final share = typed == null || typed <= 0 ? null : typed / perRecipe;
    final text = _share.text.trim();
    final label = text.isEmpty ? null : '$text $unit';
    String withShare(String head) => label == null ? head : '$head · $label';

    final String buttonLabel;
    final VoidCallback? onPress;
    var hint = false;
    var shareHint = false;
    if (staged) {
      buttonLabel = withShare('Use this recipe');
      onPress = busy || ((_dirty || _marinade) && share == null)
          ? null
          : () => cubit.pickRecipe(
              m.position,
              raw: m.raw,
              child: pick.slug!,
              childSection: pick.section,
              share: _dirty ? share : null,
            );
      // S10 (a): the API's own words for the share a marinade pick needs.
      shareHint = _marinade && share == null;
    } else if (routedSlug == null && offers(m, HoldDecision.confirm)) {
      // A held line the table lets a Confirm finish — the poured-away
      // marinade (A5 a) — confirms with nothing picked.
      buttonLabel = 'Confirm (poured away)';
      onPress = busy || m.status == 'confirmed'
          ? null
          : () => cubit.override(m.position, raw: m.raw, confirmed: true);
    } else if (routedSlug == null) {
      buttonLabel = 'Use this recipe';
      onPress = null;
      hint = true;
    } else if (_dirty) {
      buttonLabel = withShare('Save share');
      onPress = busy || share == null
          ? null
          : () => cubit.pickRecipe(
              m.position,
              raw: m.raw,
              child: routedSlug,
              childSection: c.section,
              share: share,
            );
    } else {
      final title = c.title;
      buttonLabel = title == null
          ? withShare('Confirm')
          : 'Confirm · ${shortTitle(title, c.name)}'
                '${label == null ? '' : ', $label'}';
      onPress = busy || m.status == 'confirmed'
          ? null
          : () => cubit.override(m.position, raw: m.raw, confirmed: true);
    }

    final item = c.name ?? m.item ?? '';
    final parent = widget.parent;
    List<RecipeCandidate> of(String group) => [
      for (final candidate in c.candidates)
        if (candidate.group == group) candidate,
    ];
    final noteNamed = of('note_named');
    final library = of('library');
    final similar = of('similar');
    Widget row(RecipeCandidate candidate) => _CandidateRow(
      candidate: candidate,
      selected: candidate.key != null && candidate.key == selected,
      onPick: busy || !candidate.pickable
          ? null
          : () => setState(() {
              // A number typed in a unit of the old child's yield means
              // nothing for another recipe: back to the line's share.
              if (candidate.key != current && _unit != 'recipe') {
                _reset();
              }
              _staged = candidate;
            }),
    );
    List<Widget> group(
      String title,
      List<RecipeCandidate> list,
      String? empty,
    ) => [
      _Caption(title),
      if (list.isEmpty && empty != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            empty,
            style: const TextStyle(fontSize: 12.5, color: SaltColors.muted),
          ),
        ),
      for (final candidate in list) row(candidate),
    ];

    const says = TextStyle(fontSize: 12, color: SaltColors.ink);
    final sentence =
        !staged &&
            c.title != null &&
            c.yieldText != null &&
            m.lineAmount != null &&
            c.shareText != null
        ? 'The line says "${m.lineAmount}". ${c.title} '
              '${c.yieldText!.toLowerCase()}, so the share is ${c.shareText}.'
        : null;

    return Container(
      decoration: BoxDecoration(
        color: SaltColors.panel,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.why == 'default')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(
                'Made from a recipe: counted with the first ${c.kind} the '
                'note names. Change it if the ${c.parentKind} uses another.',
                style: const TextStyle(
                  fontSize: 12,
                  color: SaltColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Text(
              'Choose the recipe & set the share',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: SaltColors.muted,
              ),
            ),
          ),
          ...group(
            "This recipe's sections",
            of('own_section'),
            parent != null && parent.hasSections != true
                ? '${parent.title} has no section named "$item".'
                : 'None is titled "$item".',
          ),
          if (noteNamed.isNotEmpty)
            ...group('Library recipes the note names', noteNamed, null),
          if (library.isNotEmpty || noteNamed.isEmpty)
            ...group(
              'Library recipes',
              library,
              'No recipe is titled "$item".',
            ),
          if (similar.isNotEmpty)
            ...group(
              'Other library recipes with a similar title',
              similar,
              null,
            ),
          ...group(
            "Another recipe's section",
            of('other_section'),
            'No section is titled "$item".',
          ),
          SearchRow(
            controller: _term,
            searching: _searching,
            onSearch: busy ? null : _runSearch,
            hint: 'Search the library for another recipe…',
          ),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                _searchError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: SaltColors.errInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final candidate in _results ?? const <RecipeCandidate>[])
            row(candidate),
          SelectionContainer.disabled(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SaltColors.hairline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Share',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: SaltColors.muted,
                    ),
                  ),
                  if (sentence != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sentence, style: says),
                    ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: FTextField(
                          control: FTextFieldControl.managed(
                            controller: _share,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      UnitToggle(
                        unit: unit,
                        units: [for (final u in units) u.unit],
                        onChanged: (u) => setState(() {
                          _unit = u;
                          _dirty = true;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FButton(
                        mainAxisSize: MainAxisSize.min,
                        onPress: onPress,
                        prefix: const Icon(FLucideIcons.check, size: 14),
                        child: Text(buttonLabel),
                      ),
                      if (widget.onSkip != null)
                        FButton(
                          variant: FButtonVariant.ghost,
                          mainAxisSize: MainAxisSize.min,
                          onPress: busy ? null : widget.onSkip,
                          prefix: const Icon(FLucideIcons.ban, size: 14),
                          child: const Text('Skip'),
                        ),
                    ],
                  ),
                  if (hint || shareHint)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        hint
                            ? 'Enabled once a recipe is picked.'
                            : 'Set the share that is eaten — the rest is '
                                  'poured away.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: SaltColors.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: SaltColors.hairline)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: SaltColors.muted,
      ),
    ),
  );
}

/// One recipe the panel offers: a tick when selected, its title with the
/// note and yield, and on the right "current · default" over its calories —
/// or, for a section (v44), its state when it is not ready. A row that
/// cannot be picked (no lines, no totals) is muted and takes no tap.
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.selected,
    required this.onPick,
  });

  final RecipeCandidate candidate;
  final bool selected;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final kcal = c.kcal;
    final perServing = c.kcalPerServing;
    final note = [?c.note, ?c.yieldText?.toLowerCase()].join(' · ');
    final right = [
      if (c.current) c.isDefault ? 'current · default' : 'current',
      if (switch (c.state) {
            'no_totals' => 'no totals yet',
            'no_ingredients' => 'no ingredients listed',
            'nested' => 'made from another recipe',
            _ => null,
          }
          case final state?)
        state
      else if (kcal != null)
        perServing == null
            ? '${kcalText(kcal)} kcal'
            : '${kcalText(kcal)} kcal · +${perServing.round()} / serving',
    ];
    final ink = c.pickable ? SaltColors.ink : SaltColors.muted;
    return SelectionContainer.disabled(
      child: FTappable(
        onPress: onPick,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? SaltColors.chip : null,
            border: const Border(top: BorderSide(color: SaltColors.hairline)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: selected
                    ? const Icon(
                        FLucideIcons.check,
                        size: 15,
                        color: SaltColors.maroon,
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: ink,
                      ),
                    ),
                    if (note.isNotEmpty)
                      Text(
                        note,
                        style: const TextStyle(
                          fontSize: 11,
                          color: SaltColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final line in right)
                    Text(
                      line,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SaltColors.muted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
