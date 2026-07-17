import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
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
    final leave = await showFDialog<bool>(
      context: context,
      builder: (context, _, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text('Discard changes?', style: style.titleTextStyle),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Unsaved changes will be lost.',
                style: style.bodyTextStyle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      autofocus: true,
                      onPress: () => Navigator.of(context).pop(false),
                      child: const Text('Keep editing'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FButton(
                      onPress: () => Navigator.of(context).pop(true),
                      child: const Text('Discard'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

/// An [FTextField] that keeps its controller in sync with cubit state without
/// clobbering the caret while the user types.
class _BoundField extends StatefulWidget {
  const _BoundField({
    required this.value,
    required this.onChanged,
    this.hintText,
    this.semanticLabel,
    this.minLines,
    this.maxLines = 1,
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
      child: FTextField(
        control: FTextFieldControl.managed(
          controller: _controller,
          // The control fires onChange for its own writes too, but the sync in
          // didUpdateWidget writes the controller directly (bypassing this), so
          // this only ever carries real user edits back to the cubit.
          onChange: (value) => widget.onChanged(value.text),
        ),
        focusNode: _focus,
        hint: widget.hintText,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
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

/// The tag field, exposed for widget tests.
///
/// Its keyboard contract (Enter takes a match rather than minting a
/// near-duplicate) is the kind of thing that shipped broken once already, so
/// it is tested directly rather than through the whole editor.
@visibleForTesting
class TagsInputForTest extends StatelessWidget {
  const TagsInputForTest({super.key});

  @override
  Widget build(BuildContext context) => const _TagsInput();
}

class _TagsInput extends StatefulWidget {
  const _TagsInput();

  @override
  State<_TagsInput> createState() => _TagsInputState();
}

class _TagsInputState extends State<_TagsInput> {
  // FAutocomplete's own controller: it extends TextEditingController, so
  // clearing/reading text works as before, and it is what `control` expects.
  final FAutocompleteController _controller = FAutocompleteController();
  final FocusNode _focus = FocusNode();

  /// What the USER typed, as opposed to what is currently in the field.
  ///
  /// They diverge, and the `Create "x"` row depends on the difference. Forui
  /// previews a highlighted row by writing its value INTO the field
  /// (autocomplete.dart:1531-1535), and `contentBuilder` is handed the LIVE
  /// field text as its query (autocomplete_content.dart:87). So arrowing onto
  /// `dessert` merely to look at it turned the query into `dessert`, the
  /// exact-match guard fired, and `Create "des"` vanished from under the
  /// keyboard — leaving no keyboard route to the one row that exists for
  /// deliberately creating a near-miss.
  String _typed = '';

  /// Every tag already in the library — the suggestion pool.
  ///
  /// Alphabetical, because that is what the server sends
  /// (`GROUP BY t.id ORDER BY t.name`, salt_database.dart) — and it does not
  /// matter either way, since [_matches] re-sorts every result itself. This
  /// once claimed "most-used first", which was true of neither end.
  ///
  /// Fetched once when the editor opens. Tags are a small, shared vocabulary
  /// (the whole library has a handful), so this is one cheap request and no
  /// per-keystroke round-trip. A failure leaves the field a plain text input:
  /// suggestions are a convenience, and must never block tagging.
  List<String> _known = const [];

  /// The in-flight fetch, so [_onSubmit] can wait for the vocabulary instead
  /// of deciding against an empty one.
  Future<void>? _loadingKnownTags;

  @override
  void initState() {
    super.initState();
    _loadingKnownTags = _loadKnownTags();
  }

  Future<void> _loadKnownTags() async {
    try {
      final tags = await context.read<TagsRepository>().listTags();
      if (mounted) {
        setState(() => _known = [for (final tag in tags) tag.name]);
      }
    } on Exception {
      // Progressive enhancement — keep the plain field.
    } finally {
      // Settled, success or not: a failed fetch means the vocabulary is
      // legitimately empty (every tag is new) rather than not-known-yet, and
      // nothing may keep waiting on it. Nulling this is what flips [_filter]
      // back to synchronous and lets the `Create` row be offered again.
      _loadingKnownTags = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The tags already on this recipe, lower-cased.
  Set<String> get _taken => context
      .read<EditorCubit>()
      .state
      .tags
      .map((tag) => tag.toLowerCase())
      .toSet();

  /// Every vocabulary tag matching [input], best first — INCLUDING tags this
  /// recipe already has.
  ///
  /// This is what Enter RESOLVES against, and it must not be confused with
  /// [_suggestions], which is what the popover DISPLAYS. The two differ by
  /// exactly one rule — the popover hides a tag you already have, because
  /// offering it is noise — and folding that display rule into the resolution
  /// re-created the junk near-duplicate this whole widget exists to prevent:
  /// with `dessert` already on the recipe it was filtered out of the match
  /// set, so typing `des` + Enter found NOTHING to match and minted `des`
  /// alongside it. Resolution must see the whole vocabulary; if the answer
  /// turns out to be a tag the recipe already has, `EditorCubit.addTag`
  /// already ignores the duplicate, so Enter is a harmless no-op.
  List<String> _matches(String input) {
    final typed = input.trim().toLowerCase();
    // An empty field offers the whole vocabulary — on a small tag set that is
    // a useful "what do we use?" list, not a wall.
    final matches = _known
        .where((tag) => typed.isEmpty || tag.toLowerCase().contains(typed))
        .toList();
    // Exact hit first, then the rest alphabetically (which is the order the
    // server returns: `ORDER BY t.name`, salt_database.dart).
    //
    // This ordering is load-bearing, not cosmetic. Enter resolves to the head
    // of this list, and the display list is capped — so if the tag the user
    // typed EXACTLY were sorted mid-list, the cap could truncate it away and
    // Enter would silently apply a different tag. Sorting the exact hit to the
    // front makes the cap unable to hide it.
    matches.sort((a, b) {
      final aExact = a.toLowerCase() == typed;
      final bExact = b.toLowerCase() == typed;
      if (aExact != bExact) {
        return aExact ? -1 : 1;
      }
      return a.compareTo(b);
    });
    return matches;
  }

  /// Suggestions for what has been typed: [_matches], minus the tags already
  /// on this recipe (offering one you have is just noise).
  Iterable<String> _suggestions(String input) =>
      _matches(input).where((tag) => !_taken.contains(tag.toLowerCase()));

  /// What the popover shows: [_suggestions] capped for display only.
  ///
  /// Kept separate from [_suggestions] on purpose. The cap belongs to the UI —
  /// a popover of 50 rows is unusable — but applying it before the match search
  /// is how Enter ended up adding the wrong tag.
  ///
  /// Returns a FUTURE while the vocabulary is still in flight, and that is the
  /// whole fix for the fetch race. FAutocomplete re-runs this filter ONLY when
  /// the field text changes (autocomplete.dart:1250 returns early otherwise), so
  /// a `setState` landing the vocabulary could never refresh an open popover:
  /// type "des" before the tags arrive and the popover offered `Create "des"`
  /// and nothing else, permanently — pressing it minted the junk near-duplicate
  /// this widget exists to prevent.
  ///
  /// Handing back a Future instead makes forui do the waiting: `Content` puts a
  /// pending future behind a FutureBuilder and shows `contentLoadingBuilder`,
  /// calling [_contentBuilder] only once it resolves
  /// (autocomplete_content.dart:70-80). So the popover cannot offer ANY row —
  /// least of all `Create` — until it knows the real vocabulary.
  FutureOr<Iterable<String>> _filter(String input) {
    final loading = _loadingKnownTags;
    if (loading != null) {
      return loading.then((_) => _suggestions(input).take(8));
    }
    return _suggestions(input).take(8);
  }

  void _addNamed(String tag) {
    context.read<EditorCubit>().addTag(tag);
    _controller.clear();
    _focus.requestFocus();
  }

  /// Pressing a popover row — including the `Create "x"` row — adds its value.
  ///
  /// There is deliberately no sentinel wrapper distinguishing the two. An
  /// earlier version smuggled `Create` through the `List<String>` item channel
  /// as a NUL-prefixed `\x00create:<text>`, which forui defeats twice over:
  /// item values are NOT an opaque channel — merely ARROWING ONTO a row writes
  /// its value into the field (`_controller.text = widget.format(value)`,
  /// autocomplete.dart:1531-1535, where `format` is the identity for
  /// `FAutocomplete.text`). So the sentinel was shown to the user verbatim, and
  /// the blur handler below then committed `\x00create:sheet-pan` as a literal
  /// tag name.
  ///
  /// Giving the `Create` row the typed text as its value removes the need for
  /// any of it: arrowing onto it shows exactly what was typed, and adding it IS
  /// creating it — the row is only offered when nothing in the vocabulary
  /// already matches that text exactly.
  void _onItemPress(String value) => _addNamed(value);

  /// Enter's behaviour, and the reason this widget exists.
  ///
  /// FAutocomplete passes `onSubmit` straight through to its text field, so
  /// Enter arrives here as the RAW typed text — the same trap the old
  /// RawAutocomplete fell into, where typing "des" and pressing Enter minted a
  /// junk tag `des` beside the real `dessert`. The tag vocabulary is shared
  /// across the whole library, so a near-miss duplicate is the failure worth
  /// designing against (approved mockup: docs/mockups/p9-tag-input.html).
  ///
  /// So: if what was typed matches anything, Enter takes the first match
  /// ([_suggestions] sorts an exact hit to the front). Creating a tag that is a
  /// near-miss of an existing one needs the explicit `Create "x"` row. With
  /// nothing matching, Enter just creates.
  ///
  /// It AWAITS the vocabulary first, and must: `_known` is empty until the tags
  /// request lands, and deciding against an empty vocabulary means every tag
  /// looks new — silently reinstating the junk-tag bug for the whole duration
  /// of the fetch, and permanently if it fails. The timeout keeps a dead
  /// network from hanging Enter; past it we genuinely cannot know better than
  /// the user, so the typed text is taken at its word.
  Future<void> _onSubmit(String text) async {
    final typed = text.trim();
    if (typed.isEmpty) {
      return;
    }
    // Empty the field BEFORE the await, not after: Enter should look like it
    // worked the instant it is pressed, not whenever the tags request lands.
    // (This also used to be load-bearing — a blur firing during the await
    // committed the raw text and then the match landed on top of it, giving
    // TWO tags. Blur no longer commits, so this is now only about feeling
    // responsive.)
    _controller.clear();
    try {
      await _loadingKnownTags?.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Decide on what we have.
    }
    if (!mounted) {
      return;
    }
    // Resolve against the WHOLE vocabulary — see [_matches].
    final matches = _matches(typed);
    // Add WITHOUT touching the controller. The field was already emptied above,
    // before the await; clearing it a second time here wipes whatever the user
    // typed DURING the await, which on a slow tags request is a real sentence's
    // worth of typing silently deleted under them. Nor is focus re-requested:
    // Enter never took focus out of the field, and grabbing it back would yank
    // the caret away from a user who has since tabbed on to Save.
    context.read<EditorCubit>().addTag(matches.isEmpty ? typed : matches.first);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EditorCubit>();
    final tags = cubit.state.tags;
    // Chips ABOVE the field, not inside it: FAutocomplete renders its own
    // bordered field, and nesting that in the old bordered chip box would draw
    // a border inside a border. It also reads better past two or three tags,
    // where the old single box shoved the cursor onto its own line anyway.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in tags)
                  InputChip(
                    label: Text(tag, style: const TextStyle(fontSize: 12)),
                    onDeleted: () => cubit.removeTag(tag),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: SaltColors.chip,
                    side: BorderSide.none,
                    labelStyle: const TextStyle(color: SaltColors.chipInk),
                    deleteIconColor: SaltColors.chipInk,
                  ),
              ],
            ),
          ),
        // A tag is committed ONLY by an explicit act — Enter, or pressing a
        // popover row (including `Create "x"`). Blur deliberately commits
        // nothing (user's call, 2026-07-16).
        //
        // This field used to add whatever was typed when focus left it, so
        // clicking Save turned a half-typed `des` into a real tag. That was the
        // last surviving route to the junk near-duplicate the whole widget
        // exists to prevent: Enter looks the text up and takes `dessert`, but
        // blur took it literally, so the same keystrokes meant different things
        // depending on how you left the field. Text left behind now simply
        // stays in the field, visibly not a chip, and is not saved.
        FAutocomplete.text(
          items: _known,
          control: FAutocompleteControl.managed(
            controller: _controller,
            // Fires for forui's own preview writes too (its `_mutating` guard
            // gates the re-filter, not this callback), so gate on the FIELD
            // having focus — that is what separates a keystroke from a preview.
            onChange: (value) {
              if (_focus.hasFocus) {
                _typed = value.text;
              }
            },
          ),
          focusNode: _focus,
          hint: 'Add a tag…',
          // A `description`, not a `hint`: a hint only renders while the field
          // is EMPTY, so it would vanish at the one moment it is needed — when
          // there is uncommitted text sitting there. This is the whole
          // mitigation for the commit contract above (user's call: say so, do
          // NOT make the editor dirty), so it has to be visible while you type.
          description: const Text('Press Enter to add'),
          // Forui's default filter is startsWith; substring matching is what
          // the old field did and what makes a small vocabulary findable
          // ("sert" should still reach "dessert").
          filter: _filter,
          contentBuilder: (context, query, values) {
            // Re-filter here, not just in `filter`. FAutocomplete only re-runs
            // `filter` when the field TEXT changes, and adding a tag does not
            // change it — Enter clears the field first, so the list is
            // computed while the new tag is not yet on the recipe and then
            // never invalidated. That left the popover offering a tag the
            // recipe already had (and clicking it did nothing). contentBuilder
            // runs on every build, so it always sees the current tags.
            final fresh = values.where(
              (tag) => !_taken.contains(tag.toLowerCase()),
            );
            // Build the `Create` row from what the USER typed, NOT from
            // `query` — see [_typed]. `query` is the live field text, which
            // forui rewrites to the highlighted row's value the moment you
            // arrow onto a suggestion, which used to delete this row mid-flow.
            final creatable = _typed.trim();
            return [
              for (final tag in fresh) FAutocompleteItem(value: tag),
              // Offer creating only what could be a NEW tag: something typed,
              // and nothing in the vocabulary already IS that tag. Checked
              // against `_known` rather than `values`, because `values` is the
              // filtered display list and shrinks as forui previews rows.
              if (creatable.isNotEmpty &&
                  !_known.any(
                    (tag) => tag.toLowerCase() == creatable.toLowerCase(),
                  ))
                FAutocompleteItem(
                  // The value is the plain typed text — see [_onItemPress].
                  // Only the TITLE says "Create"; the value must stay clean
                  // because forui writes it into the field on arrow-down.
                  value: creatable,
                  title: Text(
                    'Create “$creatable”',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SaltColors.maroon,
                    ),
                  ),
                ),
            ];
          },
          onItemPress: _onItemPress,
          onSubmit: _onSubmit,
        ),
      ],
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
              FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: cubit.addLine,
                prefix: const Icon(Icons.add, size: 16),
                child: const Text('Ingredient'),
              ),
              FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: cubit.addGroupHeader,
                prefix: const Icon(Icons.add, size: 16),
                child: const Text('Group header'),
              ),
              FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () => showPasteDialog(context),
                prefix: const Icon(Icons.content_paste_go, size: 16),
                child: const Text('Paste a list…'),
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
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Remove group header',
            child: FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: () => cubit.removeEntry(header.key),
              child: const Icon(
                Icons.delete_outline,
                size: 17,
                color: SaltColors.muted,
              ),
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
              Tooltip(
                message: line.expanded ? 'Collapse' : 'Structured fields',
                child: FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: () => cubit.toggleLineExpanded(line.key),
                  child: Icon(
                    line.expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: SaltColors.muted,
                  ),
                ),
              ),
              Tooltip(
                message: 'Remove',
                child: FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: () => cubit.removeEntry(line.key),
                  child: const Icon(
                    Icons.delete_outline,
                    size: 17,
                    color: SaltColors.muted,
                  ),
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
          FButton(
            variant: FButtonVariant.ghost,
            mainAxisSize: MainAxisSize.min,
            onPress: () => cubit.setLineStructured(
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
            prefix: const Icon(Icons.add, size: 15),
            child: const Text(
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
              FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () => cubit.reparseLine(line.key),
                prefix: const Icon(Icons.refresh, size: 15),
                child: const Text('Re-parse from text'),
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
          SizedBox(
            width: 122,
            child: FSelect<Measure>(
              items: {
                for (final measure in Measure.values) measure.name: measure,
              },
              control: FSelectControl.lifted(
                value: amount.measure,
                onChange: (measure) {
                  if (measure != null) {
                    _replace(context, amount.copyWith(measure: measure));
                  }
                },
              ),
            ),
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
                FCheckbox(
                  value: amount.approximate,
                  onChange: (value) =>
                      _replace(context, amount.copyWith(approximate: value)),
                ),
                const SizedBox(width: 4),
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
          Tooltip(
            message: 'Remove amount',
            child: FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: () {
                final amounts = [...line.amounts]..removeAt(index);
                cubit.setLineStructured(line.key, amounts: amounts);
              },
              child: const Icon(Icons.close, size: 15, color: SaltColors.muted),
            ),
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
            child: FButton(
              variant: FButtonVariant.outline,
              mainAxisSize: MainAxisSize.min,
              onPress: cubit.addStep,
              prefix: const Icon(Icons.add, size: 16),
              child: const Text('Step'),
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
              Tooltip(
                message: 'Remove step',
                child: FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: () => cubit.removeStep(step.key),
                  child: const Icon(
                    Icons.delete_outline,
                    size: 17,
                    color: SaltColors.muted,
                  ),
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
                    FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: state.uploadingImage ? null : _pickAndUpload,
                      prefix: const Icon(Icons.upload_outlined, size: 16),
                      child: Text(
                        state.uploadingImage ? 'Working…' : 'Upload photo',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FTextField(
                            control: FTextFieldControl.managed(
                              controller: _urlController,
                            ),
                            hint: '…or paste an image URL',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FButton(
                          variant: FButtonVariant.outline,
                          mainAxisSize: MainAxisSize.min,
                          onPress: state.uploadingImage
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
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, _, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text('Delete this recipe?', style: style.titleTextStyle),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'A backup is taken first, so it can be recovered from '
                'Settings → Library. The library YAML file is removed.',
                style: style.bodyTextStyle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      autofocus: true,
                      onPress: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.destructive,
                      onPress: () => Navigator.of(context).pop(true),
                      child: const Text('Delete recipe'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
          FButton(
            variant: FButtonVariant.destructive,
            mainAxisSize: MainAxisSize.min,
            onPress: state.saving ? null : () => _confirmDelete(context),
            prefix: const Icon(Icons.delete_outline, size: 17),
            child: const Text('Delete recipe'),
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
              FButton(
                mainAxisSize: MainAxisSize.min,
                onPress: state.saving || state.uploadingImage
                    ? null
                    : cubit.save,
                prefix: const Icon(Icons.save_outlined, size: 17),
                child: Text(state.saving ? 'Saving…' : 'Save recipe'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
