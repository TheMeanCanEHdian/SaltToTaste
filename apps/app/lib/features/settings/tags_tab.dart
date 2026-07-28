import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/lucide_catalog.g.dart';
import 'package:salt_app/core/widgets/tag_chip.dart';
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/settings/settings_page.dart';
import 'package:salt_app/features/settings/tags_tab_cubit.dart';
import 'package:salt_app/features/tags/tag_styles_cubit.dart';

/// Food-first shortlist shown at the top of the icon grid when the search is
/// empty (order from the approved mockup, docs/mockups/p4-tags.html).
const List<String> _curatedIcons = [
  'cake-slice',
  'cookie',
  'candy',
  'donut',
  'croissant',
  'ice-cream-cone',
  'ice-cream-bowl',
  'egg',
  'egg-fried',
  'beef',
  'ham',
  'drumstick',
  'fish',
  'salad',
  'soup',
  'sandwich',
  'pizza',
  'popcorn',
  'wheat',
  'carrot',
  'apple',
  'banana',
  'cherry',
  'citrus',
  'grape',
  'milk',
  'coffee',
  'cup-soda',
  'wine',
  'martini',
  'beer',
  'utensils',
  'utensils-crossed',
  'chef-hat',
  'cooking-pot',
  'microwave',
  'flame',
  'timer',
  'leaf',
  'snowflake',
  'star',
  'heart',
  'tag',
];

/// The full Lucide catalog with the curated shortlist first.
final List<String> _iconsCuratedFirst = () {
  final curated = _curatedIcons.toSet();
  return List<String>.unmodifiable([
    ..._curatedIcons,
    ...lucideIconsByName.keys.where((name) => !curated.contains(name)),
  ]);
}();

/// A preset color pair (background + text) from the approved mockup.
class _Preset {
  const _Preset(this.name, this.bg, this.ink);

  final String name;
  final String bg;
  final String ink;
}

// The first entry is the default theme: a tag with no explicit style falls back
// to these colours (see TagChip / [SaltColors.chip]). All names are
// food/cooking themed.
const List<_Preset> _presets = [
  _Preset('raspberry', '#F6E4E4', '#7D1420'),
  _Preset('pumpkin', '#FDF1E2', '#8A5A12'),
  _Preset('honey', '#FAF3D9', '#7A6210'),
  _Preset('herb', '#E8F3E4', '#2C5A1E'),
  _Preset('blueberry', '#E3F0F5', '#1E5A72'),
  _Preset('plum', '#EFE9F7', '#5A3D8F'),
  _Preset('cocoa', '#EEE4DC', '#5C3A1E'),
  _Preset('pepper', '#EBEBEB', '#444444'),
];

const Color _errInk = SaltColors.errInk;
const Color _panelBackground = Color(0xFFFDFBF9);

/// Tags tab (admin): style each tag's chip — Lucide icon + text/background
/// colors — with a live preview. Styles apply everywhere the tag appears.
class TagsTab extends StatefulWidget {
  const TagsTab({super.key});

  @override
  State<TagsTab> createState() => _TagsTabState();
}

class _TagsTabState extends State<TagsTab> {
  late final TagsTabCubit _cubit;
  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cubit = TagsTabCubit(
      context.read<TagsRepository>(),
      context.read<TagStylesCubit>(),
    )..load();
  }

  @override
  void dispose() {
    _cubit.close();
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<TagsTabCubit, TagsTabState>(
        builder: (context, state) {
          final visible = state.visibleTags;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PaneTitle(
                'Tags',
                description:
                    'Style the chips shown on recipe cards. Styles '
                    'apply everywhere the tag appears.',
              ),
              if (state.tags == null && state.loadError != null)
                ErrorView(message: state.loadError!, onRetry: _cubit.load)
              else if (state.tags == null)
                const LoadingView()
              else ...[
                _toolbar(state),
                if ((state.tags ?? const []).isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No tags yet — tags come from recipes.',
                      style: TextStyle(color: SaltColors.muted, fontSize: 13.5),
                    ),
                  )
                else if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No tags match your filter.',
                      style: TextStyle(color: SaltColors.muted, fontSize: 13.5),
                    ),
                  )
                else
                  for (final tag in visible)
                    _TagRow(tag: tag, editing: state.editingTag == tag.name),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _toolbar(TagsTabState state) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        // Both controls carry a label, so top-align them: the labels line up
        // on one baseline and the fields line up beneath. (The Sort select
        // used to be the only labelled one, leaving the unlabelled filter
        // floating against its taller column.)
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Semantics(
                label: 'Filter tags',
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: _filter,
                    onChange: (value) => _cubit.setFilter(value.text),
                  ),
                  label: const Text('Filter'),
                  hint: 'Filter tags…',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 168,
            child: FSelect<TagSort>(
              items: const {
                'Most recipes': TagSort.mostRecipes,
                'A–Z': TagSort.alphabetical,
              },
              control: FSelectControl.lifted(
                value: state.sort,
                onChange: (value) =>
                    _cubit.setSort(value ?? TagSort.mostRecipes),
              ),
              label: const Text('Sort'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tag listing row: live-styled chip, name, recipe count, Edit. Every row
/// is an outlined card; editing keeps the same card shell and reveals a divider
/// plus the inline style editor beneath the header ("top bar") with the same
/// fold the nutrition label uses (FCollapsible, 200ms easeInOut).
class _TagRow extends StatefulWidget {
  const _TagRow({required this.tag, required this.editing});

  final TagInfo tag;
  final bool editing;

  @override
  State<_TagRow> createState() => _TagRowState();
}

class _TagRowState extends State<_TagRow>
    with SingleTickerProviderStateMixin {
  // Drives the editor reveal: 1 = fully open, 0 = clipped to the header.
  late final AnimationController _foldController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.editing ? 1 : 0,
  );
  late final CurvedAnimation _fold = CurvedAnimation(
    parent: _foldController,
    curve: Curves.easeInOut,
  );

  // The editor stays mounted while the fold has any height so the close
  // animation can play; once fully folded it is dropped, so a reopen rebuilds
  // it fresh and re-seeds the hex fields from the tag's saved style.
  late bool _showEditor = widget.editing;

  @override
  void initState() {
    super.initState();
    _foldController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted && _showEditor) {
        setState(() => _showEditor = false);
      }
    });
  }

  @override
  void didUpdateWidget(_TagRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing && !oldWidget.editing) {
      _showEditor = true;
      _foldController.forward();
    } else if (!widget.editing && oldWidget.editing) {
      _foldController.reverse();
    }
  }

  @override
  void dispose() {
    _fold.dispose();
    _foldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TagsTabCubit>();
    final tag = widget.tag;
    final row = Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TagChip(tag.name, styleOverride: tag.style),
              Text(
                tag.name,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${tag.count} ${tag.count == 1 ? 'recipe' : 'recipes'}',
                style: const TextStyle(fontSize: 12.5, color: SaltColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // While editing there's no Edit button — the editor's own Cancel
        // closes it — but we keep the button's footprint (invisible and
        // non-interactive) so the header, and the card's top bar, stays the
        // same height whether or not the button is shown.
        Visibility(
          visible: !widget.editing,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: FButton(
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            mainAxisSize: MainAxisSize.min,
            onPress: () => cubit.openEditor(tag),
            child: const Text('Edit'),
          ),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: _panelBackground,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: row,
          ),
          // FCollapsible clips the editor as the fold lerps 0→1; at 0 it also
          // drops the hidden region from semantics and focus.
          AnimatedBuilder(
            animation: _fold,
            builder: (context, child) =>
                FCollapsible(value: _fold.value, child: child!),
            child: _showEditor
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1, color: SaltColors.hairline),
                      _StyleEditor(
                        key: ValueKey(tag.name),
                        tagName: tag.name,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// The inline style editor: icon picker (search + grid), color presets, hex
/// fields, live chip preview, and Save / Cancel / Clear actions.
class _StyleEditor extends StatefulWidget {
  const _StyleEditor({super.key, required this.tagName});

  final String tagName;

  @override
  State<_StyleEditor> createState() => _StyleEditorState();
}

class _StyleEditorState extends State<_StyleEditor> {
  final _iconSearch = TextEditingController();
  late final TextEditingController _color;
  late final TextEditingController _bgColor;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final state = context.read<TagsTabCubit>().state;
    _color = TextEditingController(text: state.draftColor);
    _bgColor = TextEditingController(text: state.draftBgColor);
  }

  @override
  void dispose() {
    _iconSearch.dispose();
    _color.dispose();
    _bgColor.dispose();
    super.dispose();
  }

  List<String> get _visibleIcons {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _iconsCuratedFirst;
    }
    return [
      for (final name in _iconsCuratedFirst)
        if (name.contains(query)) name,
    ];
  }

  void _applyPreset(_Preset preset) {
    _color.text = preset.ink;
    _bgColor.text = preset.bg;
    context.read<TagsTabCubit>().setDraftColors(
      color: preset.ink,
      bgColor: preset.bg,
    );
  }

  // Resets the draft to the default look (no icon, empty colours) without
  // saving. Clears the local hex fields too, since they hold their own text.
  void _reset() {
    _color.clear();
    _bgColor.clear();
    context.read<TagsTabCubit>().resetDraft();
  }

  bool _presetSelected(TagsTabState state, _Preset preset) {
    final ink = state.draftColor.trim().toUpperCase();
    final bg = state.draftBgColor.trim().toUpperCase();
    // A tag with no explicit colour falls back to the default theme, so show
    // the default (first) preset selected rather than nothing.
    if (ink.isEmpty && bg.isEmpty) {
      return identical(preset, _presets.first);
    }
    return ink == preset.ink && bg == preset.bg;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TagsTabCubit>();
    final state = context.watch<TagsTabCubit>().state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumn = constraints.maxWidth >= 560;
          final picker = _iconPicker(cubit, state);
          final colors = _colorsSection(cubit, state);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (twoColumn)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: picker),
                    const SizedBox(width: 26),
                    Expanded(flex: 5, child: colors),
                  ],
                )
              else ...[
                picker,
                const SizedBox(height: 18),
                colors,
              ],
              if (state.saveError != null)
                AuthBanner(message: state.saveError!),
              const SizedBox(height: 14),
              _actions(cubit, state, constraints.maxWidth),
            ],
          );
        },
      ),
    );
  }

  Widget _iconPicker(TagsTabCubit cubit, TagsTabState state) {
    final icons = _visibleIcons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Icon'),
        Semantics(
          label: 'Search icons',
          child: FTextField(
            control: FTextFieldControl.managed(
              controller: _iconSearch,
              onChange: (value) => setState(() => _query = value.text),
            ),
            hint: 'Search Lucide icons — e.g. cake, fish, leaf…',
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 216,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: SaltColors.hairline),
            borderRadius: BorderRadius.circular(10),
          ),
          child: GridView.builder(
            primary: false,
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 48,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: icons.length + 1,
            itemBuilder: (context, index) {
              // The active tag colours (draft, or the default 'raspberry') so the
              // selected cell matches the tag being styled.
              final accentInk =
                  colorFromHex(state.draftColor) ?? SaltColors.chipInk;
              final accentBg =
                  colorFromHex(state.draftBgColor) ?? SaltColors.chip;
              if (index == 0) {
                return _IconCell.none(
                  selected: state.draftIcon == null,
                  onTap: () => cubit.setDraftIcon(null),
                  accentInk: accentInk,
                  accentBg: accentBg,
                );
              }
              final name = icons[index - 1];
              return _IconCell(
                name: name,
                selected: state.draftIcon == name,
                onTap: () => cubit.setDraftIcon(name),
                accentInk: accentInk,
                accentBg: accentBg,
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Searches the full Lucide set (${lucideIconsByName.length} '
          'icons); the grid shows the food shortlist first.',
          style: const TextStyle(fontSize: 12, color: SaltColors.muted),
        ),
      ],
    );
  }

  Widget _colorsSection(TagsTabCubit cubit, TagsTabState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Colors'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final preset in _presets)
              _SwatchChip(
                preset: preset,
                selected: _presetSelected(state, preset),
                onTap: () => _applyPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _HexField(
                label: 'Text',
                controller: _color,
                invalid: state.draftColorInvalid,
                onChanged: (value) => cubit.setDraftColors(color: value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HexField(
                label: 'Background',
                controller: _bgColor,
                invalid: state.draftBgColorInvalid,
                onChanged: (value) => cubit.setDraftColors(bgColor: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Any #RRGGBB works — presets are shortcuts.',
          style: TextStyle(fontSize: 12, color: SaltColors.muted),
        ),
        const SizedBox(height: 16),
        const _FieldLabel('Preview'),
        _previewStrip(state),
      ],
    );
  }

  Widget _previewStrip(TagsTabState state) {
    final style = state.draftStyle;
    return Wrap(
      spacing: 18,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TagChip(widget.tagName, styleOverride: style),
        Container(
          width: 130,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5A3218), Color(0xFF7A4A24), Color(0xFF3F2210)],
              stops: [0, 0.45, 1],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 8,
                bottom: 8,
                child: TagChip(
                  widget.tagName,
                  onCard: true,
                  styleOverride: style,
                ),
              ),
            ],
          ),
        ),
        const Text(
          'on the page · on a photo tile',
          style: TextStyle(fontSize: 12.5, color: SaltColors.muted),
        ),
      ],
    );
  }

  Widget _actions(TagsTabCubit cubit, TagsTabState state, double width) {
    Widget save = FButton(
      mainAxisSize: MainAxisSize.min,
      onPress: state.saving || !state.canSave ? null : cubit.save,
      child: Text(state.saving ? 'Saving…' : 'Save style'),
    );
    if (!state.canSave) {
      save = Tooltip(message: 'Colors must be #RRGGBB', child: save);
    }
    final cancel = FButton(
      variant: FButtonVariant.outline,
      mainAxisSize: MainAxisSize.min,
      onPress: state.saving ? null : cubit.closeEditor,
      child: const Text('Cancel'),
    );
    final reset = FButton(
      variant: FButtonVariant.ghost,
      mainAxisSize: MainAxisSize.min,
      onPress: state.saving ? null : _reset,
      child: const Text('Reset'),
    );
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SaltColors.hairline)),
      ),
      child: width >= 460
          ? Row(
              children: [
                reset,
                const Spacer(),
                save,
                const SizedBox(width: 10),
                cancel,
              ],
            )
          : Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [reset, save, cancel],
            ),
    );
  }
}

/// Bold 12.5px field label, matching the mockup's `label` style.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// One ~44px icon-grid cell; `.none` is the leading "NONE" (no icon) cell.
class _IconCell extends StatelessWidget {
  const _IconCell({
    required String this.name,
    required this.selected,
    required this.onTap,
    required this.accentInk,
    required this.accentBg,
  });

  const _IconCell.none({
    required this.selected,
    required this.onTap,
    required this.accentInk,
    required this.accentBg,
  }) : name = null;

  final String? name;
  final bool selected;
  final VoidCallback onTap;

  /// The tag's active colours (the draft, or the default 'raspberry'), so a selected
  /// cell matches the tag being styled rather than a fixed maroon.
  final Color accentInk;
  final Color accentBg;

  @override
  Widget build(BuildContext context) {
    final cell = Semantics(
      button: true,
      selected: selected,
      label: name == null ? 'No icon' : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accentBg : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accentInk : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: name == null
              ? const Text(
                  'NONE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: SaltColors.muted,
                  ),
                )
              : Icon(
                  lucideIconsByName[name],
                  size: 19,
                  color: selected ? accentInk : SaltColors.ink,
                ),
        ),
      ),
    );
    if (name == null) {
      return cell;
    }
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 400),
      child: cell,
    );
  }
}

/// A preset swatch chip: tag-chip colors with the preset's name as label.
class _SwatchChip extends StatelessWidget {
  const _SwatchChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final _Preset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Selected state is a border in the preset's own text colour; expose it to
    // screen readers, and pad the ~22px pill up to a real (≥24px, larger on
    // touch) target.
    final targetPad = isCompactWidth(context) ? 9.0 : 4.0;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: preset.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: targetPad),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: colorFromHex(preset.bg),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected
                      ? (colorFromHex(preset.ink) ?? SaltColors.maroon)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: ExcludeSemantics(
                child: Text(
                  preset.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorFromHex(preset.ink),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labelled hex input with a color-well square; flags non-empty invalid text
/// (anything that isn't exactly `#RRGGBB`).
class _HexField extends StatelessWidget {
  const _HexField({
    required this.label,
    required this.controller,
    required this.invalid,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool invalid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final well = colorFromHex(controller.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: invalid ? _errInk : SaltColors.hairline,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: well ?? Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0x1F000000)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  label: '$label, hex color',
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: '#RRGGBB',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (invalid)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Colors must be #RRGGBB',
              style: TextStyle(fontSize: 11.5, color: _errInk),
            ),
          ),
      ],
    );
  }
}
