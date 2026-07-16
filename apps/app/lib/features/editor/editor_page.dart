import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/photo_fallback.dart';
import 'package:salt_app/features/editor/editor_cubit.dart';
import 'package:salt_app/features/editor/paste_dialog.dart';

/// The recipe editor (approved P5 design): raw-first ingredient rows with
/// parse-status chips and an expandable structured panel, direction cards,
/// photos, and a sticky save bar. Admin-only (the router guards the route;
/// the server enforces regardless).
class EditorPage extends StatelessWidget {
  const EditorPage({super.key, this.slug});

  /// Null edits a brand-new recipe.
  final String? slug;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Keyed by slug for the same reason as the detail page: /r/a/edit ->
      // /r/b/edit must not keep editing the old recipe.
      key: ValueKey(slug),
      create: (context) {
        final cubit = EditorCubit(context.read<RecipeRepository>());
        if (slug == null) {
          cubit.startNew();
        } else {
          cubit.load(slug!);
        }
        return cubit;
      },
      child: BlocConsumer<EditorCubit, EditorState>(
        listenWhen: (previous, current) =>
            (current.savedSlug != null && previous.savedSlug == null) ||
            (current.deleted && !previous.deleted),
        listener: (context, state) {
          if (state.deleted) {
            context.go('/');
          } else if (state.savedSlug != null) {
            context.go('/r/${state.savedSlug}');
          }
        },
        builder: (context, state) {
          if (state.loading) {
            return const Scaffold(body: LoadingView());
          }
          final loadError = state.loadError;
          if (loadError != null) {
            return Scaffold(
              appBar: AppBar(
                backgroundColor: SaltColors.maroon,
                foregroundColor: Colors.white,
                title: const Text('Edit recipe'),
              ),
              body: ErrorView(
                message: loadError,
                onRetry: () => context.read<EditorCubit>().load(slug!),
              ),
            );
          }
          return const _EditorScaffold();
        },
      ),
    );
  }
}

class _EditorScaffold extends StatelessWidget {
  const _EditorScaffold();

  Future<void> _confirmLeave(BuildContext context) async {
    final state = context.read<EditorCubit>().state;
    if (!state.dirty) {
      _leave(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Unsaved changes will be lost.'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SaltColors.maroon),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave ?? false) {
      if (context.mounted) {
        _leave(context);
      }
    }
  }

  void _leave(BuildContext context) {
    final state = context.read<EditorCubit>().state;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(state.slug == null ? '/' : '/r/${state.slug}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorCubit>().state;
    return PopScope(
      // System/browser back gets the same discard confirmation as the
      // in-app Back and Cancel buttons (best effort on web — a hard
      // refresh can't be intercepted).
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmLeave(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: SaltColors.maroon,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => _confirmLeave(context),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  state.isNew
                      ? 'New recipe'
                      : 'Editing · ${state.title.isEmpty ? '…' : state.title}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16.5),
                ),
              ),
              if (state.dirty) ...[
                const SizedBox(width: 8),
                const Tooltip(
                  message: 'Unsaved changes',
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: Color(0xFFFFD28A),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _confirmLeave(context),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: SaltColors.maroon,
                  // The theme forces filled-button icons white (for the maroon
                  // buttons); this white-on-white save button must opt back
                  // out or its icon vanishes.
                  iconColor: SaltColors.maroon,
                ),
                onPressed: state.saving || state.uploadingImage
                    ? null
                    : () => context.read<EditorCubit>().save(),
                icon: const Icon(Icons.save_outlined, size: 17),
                label: Text(state.saving ? 'Saving…' : 'Save recipe'),
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: const [
                          _BasicsCard(),
                          SizedBox(height: 18),
                          _StoryCard(),
                          SizedBox(height: 18),
                          _IngredientsCard(),
                          SizedBox(height: 18),
                          _DirectionsCard(),
                          SizedBox(height: 18),
                          _PhotosCard(),
                          SizedBox(height: 18),
                          _DangerCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const _SaveBar(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Shared building blocks.
// ---------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.danger = false});

  final String title;
  final Widget child;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: danger ? const Color(0xFFECCFCF) : SaltColors.hairline,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: danger ? SaltColors.errInk : SaltColors.maroon,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text.rich(
        TextSpan(
          text: text,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          children: [
            if (hint != null)
              TextSpan(
                text: '  $hint',
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  color: SaltColors.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A TextField that keeps its controller in sync with cubit state without
/// clobbering the caret while the user types.
class _BoundField extends StatefulWidget {
  const _BoundField({
    required this.value,
    required this.onChanged,
    this.hintText,
    this.semanticLabel,
    this.minLines,
    this.maxLines = 1,
    this.style,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? hintText;

  /// Accessible name for the field. The visible `_FieldLabel` above a field
  /// isn't programmatically linked, so a screen reader would otherwise
  /// announce only "text field". Falls back to [hintText] when omitted.
  final String? semanticLabel;
  final int? minLines;
  final int? maxLines;
  final TextStyle? style;

  @override
  State<_BoundField> createState() => _BoundFieldState();
}

class _BoundFieldState extends State<_BoundField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _BoundField old) {
    super.didUpdateWidget(old);
    // Never clobber the field the user is typing in: while focused, the
    // controller leads the (possibly debounced) state, and syncing here
    // would wipe in-progress text and collapse the caret. Unfocused fields
    // follow state as usual.
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel ?? widget.hintText,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onChanged: widget.onChanged,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        style: widget.style ?? const TextStyle(fontSize: 14),
        decoration: InputDecoration(hintText: widget.hintText, isDense: true),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Basics.
// ---------------------------------------------------------------------

class _BasicsCard extends StatelessWidget {
  const _BasicsCard();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EditorCubit>();
    final state = cubit.state;
    final serves = state.parsedServes;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;

    final servingsField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Servings'),
        _BoundField(
          value: state.servings,
          onChanged: cubit.setServings,
          hintText: 'e.g. SERVES 4 TO 6',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            serves == null
                ? 'Shown verbatim; add a number for scaling later.'
                : 'Reads as ${serves.min == serves.max ? '${serves.min}' : '${serves.min}–${serves.max}'} '
                      'servings — shown verbatim, parsed for scaling.',
            style: const TextStyle(fontSize: 11.5, color: SaltColors.muted),
          ),
        ),
      ],
    );
    final categoryField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Category'),
        _BoundField(
          value: state.category,
          onChanged: cubit.setCategory,
          semanticLabel: 'Category',
        ),
      ],
    );
    final sourceFields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Source', hint: '(name · link)'),
        _BoundField(
          value: state.sourceName,
          onChanged: cubit.setSourceName,
          hintText: 'My Recipes',
        ),
        const SizedBox(height: 6),
        _BoundField(
          value: state.sourceUrl,
          onChanged: cubit.setSourceUrl,
          hintText: 'https://… (optional)',
        ),
      ],
    );

    return _Card(
      title: 'Basics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Title'),
          _BoundField(
            value: state.title,
            onChanged: cubit.setTitle,
            semanticLabel: 'Title',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (!state.isNew)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'URL slug "${state.slug}" — kept stable on rename so links '
                "don't break.",
                style: const TextStyle(fontSize: 11.5, color: SaltColors.muted),
              ),
            ),
          const SizedBox(height: 14),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: servingsField),
                const SizedBox(width: 14),
                Expanded(child: categoryField),
                const SizedBox(width: 14),
                Expanded(child: sourceFields),
              ],
            )
          else ...[
            servingsField,
            const SizedBox(height: 14),
            categoryField,
            const SizedBox(height: 14),
            sourceFields,
          ],
          const SizedBox(height: 14),
          const _FieldLabel('Tags'),
          const _TagsInput(),
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Text(
              'New tags are created on save and show up in Settings → Tags '
              'for styling.',
              style: TextStyle(fontSize: 11.5, color: SaltColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsInput extends StatefulWidget {
  const _TagsInput();

  @override
  State<_TagsInput> createState() => _TagsInputState();
}

class _TagsInputState extends State<_TagsInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add({bool keepFocus = false}) {
    context.read<EditorCubit>().addTag(_controller.text);
    _controller.clear();
    if (keepFocus) {
      // Adding several tags in a row shouldn't need a mouse round-trip.
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EditorCubit>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: SaltColors.hairline, width: 1.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in cubit.state.tags)
            InputChip(
              label: Text(tag, style: const TextStyle(fontSize: 12)),
              onDeleted: () => cubit.removeTag(tag),
              visualDensity: VisualDensity.compact,
              backgroundColor: SaltColors.chip,
              side: BorderSide.none,
              labelStyle: const TextStyle(color: SaltColors.chipInk),
              deleteIconColor: SaltColors.chipInk,
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            // Commit on blur too: clicking Save (or tapping away on mobile)
            // must not silently drop a half-typed tag.
            child: Focus(
              onFocusChange: (focused) {
                if (!focused && _controller.text.trim().isNotEmpty) {
                  _add();
                }
              },
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                onSubmitted: (_) => _add(keepFocus: true),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Add tag…',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Story & cook's notes.
// ---------------------------------------------------------------------

class _StoryCard extends StatelessWidget {
  const _StoryCard();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EditorCubit>();
    final state = cubit.state;
    return _Card(
      title: "Story & cook's notes",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Background', hint: '(the "why this works" prose)'),
          _BoundField(
            value: state.background,
            onChanged: cubit.setBackground,
            semanticLabel: 'Background',
            minLines: 3,
            maxLines: 10,
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Prep notes', hint: '(before you begin)'),
          _BoundField(
            value: state.prepNotes,
            onChanged: cubit.setPrepNotes,
            semanticLabel: 'Prep notes',
            minLines: 2,
            maxLines: 8,
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Notes', hint: '(shared with everyone)'),
          _BoundField(
            value: state.notes,
            onChanged: cubit.setNotes,
            semanticLabel: 'Notes',
            minLines: 1,
            maxLines: 8,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Ingredients.
// ---------------------------------------------------------------------

class _IngredientsCard extends StatelessWidget {
  const _IngredientsCard();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EditorCubit>();
    final entries = cubit.state.entries;
    return _Card(
      title: 'Ingredients',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: entries.length,
            onReorderItem: cubit.reorderEntries,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return KeyedSubtree(
                key: ValueKey(entry.key),
                child: switch (entry) {
                  EditorGroupHeader() => _GroupHeaderRow(
                    index: index,
                    header: entry,
                  ),
                  EditorLine() => _IngredientRow(index: index, line: entry),
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: cubit.addLine,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Ingredient'),
              ),
              OutlinedButton.icon(
                onPressed: cubit.addGroupHeader,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Group header'),
              ),
              OutlinedButton.icon(
                onPressed: () => showPasteDialog(context),
                icon: const Icon(Icons.content_paste_go, size: 16),
                label: const Text('Paste a list…'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupHeaderRow extends StatelessWidget {
  const _GroupHeaderRow({required this.index, required this.header});

  final int index;
  final EditorGroupHeader header;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<EditorCubit>();
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Tooltip(
              message: 'Drag to reorder',
              child: Icon(
                Icons.drag_indicator,
                size: 17,
                color: Color(0xFFCFC8C2),
                semanticLabel: 'Drag to reorder group',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: _BoundField(
                  value: header.name,
                  onChanged: (value) => cubit.renameGroup(header.key, value),
                  hintText: 'GROUP NAME — e.g. FOR THE GLAZE',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove group header',
            onPressed: () => cubit.removeEntry(header.key),
            icon: const Icon(
              Icons.delete_outline,
              size: 17,
              color: SaltColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatefulWidget {
  const _IngredientRow({required this.index, required this.line});

  final int index;
  final EditorLine line;

  @override
  State<_IngredientRow> createState() => _IngredientRowState();
}

class _IngredientRowState extends State<_IngredientRow> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _rawChanged(String value) {
    // Raw text goes to state IMMEDIATELY — a save or leave-check must never
    // miss the last 350ms of typing. Only the parse is debounced.
    context.read<EditorCubit>().setLineRaw(widget.line.key, value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        context.read<EditorCubit>().applyAutoParse(widget.line.key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<EditorCubit>();
    final line = widget.line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: widget.index,
                child: const Tooltip(
                  message: 'Drag to reorder',
                  child: Icon(
                    Icons.drag_indicator,
                    size: 17,
                    color: Color(0xFFCFC8C2),
                    semanticLabel: 'Drag to reorder ingredient',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BoundField(
                  value: line.raw,
                  onChanged: _rawChanged,
                  hintText: 'e.g. 2 cups (10 ounces) all-purpose flour',
                ),
              ),
              const SizedBox(width: 8),
              _ConfidenceChip(line: line),
              IconButton(
                tooltip: line.expanded ? 'Collapse' : 'Structured fields',
                onPressed: () => cubit.toggleLineExpanded(line.key),
                icon: Icon(
                  line.expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: SaltColors.muted,
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () => cubit.removeEntry(line.key),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 17,
                  color: SaltColors.muted,
                ),
              ),
            ],
          ),
        ),
        if (line.expanded) _StructuredPanel(line: line),
      ],
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.line});

  final EditorLine line;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground, icon) = line.manuallyEdited
        ? (
            'manual',
            SaltColors.chipNeutral,
            SaltColors.muted,
            Icons.lock_outline,
          )
        : switch (line.confidence) {
            ParseConfidence.parsed => (
              'parsed',
              SaltColors.okBg,
              SaltColors.okInk,
              Icons.check,
            ),
            ParseConfidence.check => (
              'check',
              SaltColors.warnBg,
              SaltColors.warnInk,
              Icons.warning_amber_outlined,
            ),
            ParseConfidence.none => (
              'no amount',
              SaltColors.chipNeutral,
              SaltColors.muted,
              null,
            ),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _StructuredPanel extends StatelessWidget {
  const _StructuredPanel({required this.line});

  final EditorLine line;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<EditorCubit>();
    return Container(
      margin: const EdgeInsets.fromLTRB(25, 2, 0, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: SaltColors.panel,
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, amount) in line.amounts.indexed)
            _AmountRow(line: line, index: i, amount: amount),
          TextButton.icon(
            onPressed: () => cubit.setLineStructured(
              line.key,
              amounts: [
                ...line.amounts,
                Amount(
                  measure: Measure.volume,
                  quantity: '',
                  // The only amount on a line must be the primary one.
                  primary: line.amounts.isEmpty,
                ),
              ],
            ),
            icon: const Icon(Icons.add, size: 15),
            label: const Text(
              'Add amount (e.g. the weight in parentheses)',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Item'),
                    _BoundField(
                      value: line.item ?? '',
                      semanticLabel: 'Item',
                      onChanged: (value) => cubit.setLineStructured(
                        line.key,
                        item: value.isEmpty ? null : value,
                        clearItem: value.isEmpty,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Prep'),
                    _BoundField(
                      value: line.prep ?? '',
                      onChanged: (value) => cubit.setLineStructured(
                        line.key,
                        prep: value.isEmpty ? null : value,
                        clearPrep: value.isEmpty,
                      ),
                      hintText: 'e.g. softened, chopped coarse',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => cubit.reparseLine(line.key),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Re-parse from text'),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Hand-edited fields lock — retyping the line above only '
                  'suggests changes.',
                  style: TextStyle(fontSize: 11.5, color: SaltColors.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.line,
    required this.index,
    required this.amount,
  });

  final EditorLine line;
  final int index;
  final Amount amount;

  void _replace(BuildContext context, Amount updated) {
    final amounts = [...line.amounts];
    amounts[index] = updated;
    context.read<EditorCubit>().setLineStructured(line.key, amounts: amounts);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<EditorCubit>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          DropdownButton<Measure>(
            value: amount.measure,
            isDense: true,
            // DropdownButton.style REPLACES the ambient text style, so it must
            // carry the bundled font or the selected value renders invisible
            // in the offline (--no-web-resources-cdn) build.
            style: const TextStyle(
              fontSize: 13,
              color: SaltColors.ink,
              fontFamily: 'OpenSans',
            ),
            items: [
              for (final measure in Measure.values)
                DropdownMenuItem(value: measure, child: Text(measure.name)),
            ],
            onChanged: (measure) {
              if (measure != null) {
                _replace(context, amount.copyWith(measure: measure));
              }
            },
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: _BoundField(
              value: amount.quantity,
              onChanged: (value) =>
                  _replace(context, amount.copyWith(quantity: value)),
              hintText: '1 3/4',
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: _BoundField(
              value: amount.unit ?? '',
              onChanged: (value) => _replace(
                context,
                amount.copyWith(unit: value.isEmpty ? null : value),
              ),
              hintText: 'cup',
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Approximate ("about")',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: amount.approximate,
                  visualDensity: VisualDensity.compact,
                  onChanged: (value) => _replace(
                    context,
                    amount.copyWith(approximate: value ?? false),
                  ),
                ),
                const Text('≈', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Primary amount',
            child: Radio<int>(
              value: index,
              // ignore: deprecated_member_use
              groupValue: line.amounts.indexWhere((a) => a.primary),
              // ignore: deprecated_member_use
              onChanged: (_) {
                final amounts = [
                  for (final (i, a) in line.amounts.indexed)
                    a.copyWith(primary: i == index),
                ];
                cubit.setLineStructured(line.key, amounts: amounts);
              },
            ),
          ),
          IconButton(
            tooltip: 'Remove amount',
            onPressed: () {
              final amounts = [...line.amounts]..removeAt(index);
              cubit.setLineStructured(line.key, amounts: amounts);
            },
            icon: const Icon(Icons.close, size: 15, color: SaltColors.muted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Directions.
// ---------------------------------------------------------------------

class _DirectionsCard extends StatelessWidget {
  const _DirectionsCard();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EditorCubit>();
    final steps = cubit.state.steps;
    return _Card(
      title: 'Directions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: steps.length,
            onReorderItem: cubit.reorderSteps,
            itemBuilder: (context, index) => KeyedSubtree(
              key: ValueKey(steps[index].key),
              child: _StepCard(index: index, step: steps[index]),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: cubit.addStep,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Step'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Steps renumber automatically when reordered.',
              style: TextStyle(fontSize: 11.5, color: SaltColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.index, required this.step});

  final int index;
  final EditorStep step;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<EditorCubit>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border.all(color: SaltColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: SaltColors.maroon,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: _BoundField(
                      value: step.label,
                      onChanged: (value) =>
                          cubit.setStep(step.key, label: value),
                      hintText: 'Optional label — e.g. MAKE THE BATTER',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _BoundField(
                  value: step.text,
                  onChanged: (value) => cubit.setStep(step.key, text: value),
                  minLines: 2,
                  maxLines: 12,
                  hintText: 'What to do…',
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Column(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Tooltip(
                  message: 'Drag to reorder',
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 17,
                      color: Color(0xFFCFC8C2),
                      semanticLabel: 'Drag to reorder step',
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove step',
                onPressed: () => cubit.removeStep(step.key),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 17,
                  color: SaltColors.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Photos.
// ---------------------------------------------------------------------

class _PhotosCard extends StatefulWidget {
  const _PhotosCard();

  @override
  State<_PhotosCard> createState() => _PhotosCardState();
}

class _PhotosCardState extends State<_PhotosCard> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final cubit = context.read<EditorCubit>();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes != null) {
      await cubit.uploadPhoto(bytes, role: 'hero');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EditorCubit>();
    final state = cubit.state;
    if (state.isNew) {
      return const _Card(
        title: 'Photos',
        child: Text(
          'Save the recipe first, then add photos here.',
          style: TextStyle(fontSize: 13, color: SaltColors.muted),
        ),
      );
    }
    final hero = state.heroImageUrl;
    return _Card(
      title: 'Photos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 200,
                  height: 130,
                  child: hero == null
                      ? const PhotoFallback()
                      : Image.network(
                          apiUrl(hero),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const PhotoFallback(),
                        ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: state.uploadingImage ? null : _pickAndUpload,
                      icon: const Icon(Icons.upload_outlined, size: 16),
                      label: Text(
                        state.uploadingImage ? 'Working…' : 'Upload photo',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: '…or paste an image URL',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: state.uploadingImage
                              ? null
                              : () => cubit.photoFromUrl(
                                  _urlController.text.trim(),
                                  role: 'hero',
                                ),
                          child: const Text('Fetch'),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'JPEG/PNG/WebP up to 25 MB — files are '
                        'content-checked and renamed server-side.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: SaltColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _FieldLabel('Photo credit', hint: '(optional)'),
                    _BoundField(
                      value: state.credit,
                      onChanged: cubit.setCredit,
                      hintText: "e.g. © America's Test Kitchen",
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Danger zone + save bar.
// ---------------------------------------------------------------------

class _DangerCard extends StatelessWidget {
  const _DangerCard();

  Future<void> _confirmDelete(BuildContext context) async {
    final cubit = context.read<EditorCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recipe?'),
        content: const Text(
          'A backup is taken first, so it can be recovered from '
          'Settings → Library. The library YAML file is removed.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SaltColors.errInk),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete recipe'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await cubit.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorCubit>().state;
    if (state.isNew) {
      return const SizedBox.shrink();
    }
    return _Card(
      title: 'Danger zone',
      danger: true,
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Deleting removes the recipe and its library YAML. A backup is '
            "taken first, so it's recoverable.",
            style: TextStyle(fontSize: 13, color: SaltColors.muted),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: SaltColors.errInk,
              side: const BorderSide(color: Color(0xFFECCFCF)),
            ),
            onPressed: state.saving ? null : () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline, size: 17),
            label: const Text('Delete recipe'),
          ),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EditorCubit>();
    final state = cubit.state;
    return Material(
      color: SaltColors.panel,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SaltColors.hairline)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              if (state.saveError != null)
                Expanded(
                  child: Text(
                    state.saveError!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: SaltColors.errInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    state.dirty
                        ? 'Unsaved changes — saving updates the database and '
                              'rewrites the library YAML.'
                        : 'All changes saved.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: SaltColors.muted,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: SaltColors.maroon,
                ),
                onPressed: state.saving || state.uploadingImage
                    ? null
                    : cubit.save,
                icon: const Icon(Icons.save_outlined, size: 17),
                label: Text(state.saving ? 'Saving…' : 'Save recipe'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
