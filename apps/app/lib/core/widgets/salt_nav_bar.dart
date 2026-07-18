import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_logo.dart';
import 'package:salt_app/core/widgets/search_help.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/search/search_suggestions.dart';

/// The maroon top navigation bar: optional back control, logo, live search
/// field, avatar menu.
class SaltNavBar extends StatelessWidget implements PreferredSizeWidget {
  const SaltNavBar({
    super.key,
    this.showBack = false,
    this.initialQuery,
    this.onSearchRefresh,
  });

  /// Whether to show a leading back control on drill-down pages.
  ///
  /// Suppressed on web: there the browser's own Back button is the affordance
  /// (and now works, since imperative pushes reflect in the URL — see
  /// `main.dart`), so an in-app duplicate is redundant. Kept for the portable
  /// non-web targets, which have no chrome-level back control in this chrome.
  final bool showBack;

  /// Pre-fills the search field (the search page passes its query).
  final String? initialQuery;

  /// Called instead of navigating when the submitted query equals
  /// [initialQuery] — the results page passes a reload so resubmitting the
  /// same query refreshes in place (go() to the current location is a
  /// no-op).
  final VoidCallback? onSearchRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    final logo = Semantics(
      button: true,
      label: 'Home',
      child: InkWell(
        onTap: () => context.go('/'),
        child: const Padding(
          // Tight vertical padding so the enlarged pan glyph fills the 58px bar
          // instead of being scaled back down by the banner's BoxFit.contain.
          padding: EdgeInsets.symmetric(vertical: 6),
          child: ExcludeSemantics(
            child: SaltLogoBanner(color: Colors.white, titleSize: 20),
          ),
        ),
      ),
    );
    return Material(
      color: SaltColors.maroon,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (showBack && !kIsWeb) ...[
                  Tooltip(
                    message: 'Back',
                    // On the maroon bar the icon is painted white explicitly
                    // (the ghost variant's theme foreground is dark — it would
                    // vanish against maroon).
                    child: FButton.icon(
                      variant: FButtonVariant.ghost,
                      size: FButtonSizeVariant.xs,
                      semanticsLabel: 'Back',
                      onPress: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                if (!compact) ...[
                  logo,
                  const SizedBox(width: 18),
                  Expanded(
                    child: _SearchField(
                      initialQuery: initialQuery,
                      onRefresh: onSearchRefresh,
                    ),
                  ),
                ] else ...[
                  // The full lockup can be wider than a narrow bar; shrink it to
                  // fit (never overflow) while it takes the free space on the
                  // left, pushing the search + avatar to the right.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: logo,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _MobileSearchButton(
                    initialQuery: initialQuery,
                    onRefresh: onSearchRefresh,
                  ),
                ],
                const SizedBox(width: 12),
                const _AvatarMenu(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The nav search field: submits the query (search DSL supported) to the
/// results page.
class _SearchField extends StatefulWidget {
  const _SearchField({this.initialQuery, this.onRefresh});

  final String? initialQuery;
  final VoidCallback? onRefresh;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  final FocusNode _focus = FocusNode();

  /// The tag vocabulary, fetched on first focus rather than on mount: the nav
  /// bar is on every page, and most page views never touch the search field.
  /// Not cached beyond this field's life — the list is small, it changes
  /// whenever a recipe is edited, and one fetch per search interaction is
  /// cheaper than a stale vocabulary.
  List<TagInfo> _tags = const [];

  /// Non-null while the vocabulary is in flight.
  ///
  /// `optionsBuilder` RETURNS this future rather than reading a list that has
  /// not arrived, because RawAutocomplete only recomputes rows when the TEXT
  /// changes: landing the tags in a `setState` could never refresh an open
  /// popover, so a pre-filled `tag:dessert` on the results page would offer
  /// nothing at all, permanently. Handing the waiting to the widget is the
  /// same fix the editor's tag field needed for the same reason.
  Future<void>? _loadingTags;

  /// The rows currently on offer, captured as they are computed.
  ///
  /// Enter needs them and the field cannot ask for them:
  /// `AutocompleteHighlightedOption` is installed inside the options view, not
  /// above `fieldViewBuilder`.
  List<SearchSuggestion> _rows = const [];

  /// Which row RawAutocomplete has highlighted, mirrored out of the options
  /// view for the same reason.
  int _highlighted = 0;

  /// Whether the user has explicitly moved onto a row.
  ///
  /// This is the difference between a search bar and the editor's tag field.
  /// RawAutocomplete pre-highlights option 0 and its `onFieldSubmitted` takes
  /// whatever is highlighted — so wiring it up naively would make typing `t`
  /// and pressing Enter search for `tag:` instead of `t`. Enter must mean
  /// "search what I typed" unless the user has actually chosen a row, which is
  /// the same explicit-act rule the tag input arrived at from the opposite
  /// direction.
  ///
  /// It is a flag rather than a derived value, which makes every way it can
  /// desynchronise from the popover a bug — both of the ways found so far made
  /// Enter a DEAD KEY, silently. So it may only ever be armed while rows are
  /// actually on offer, and everything that takes the popover away disarms it:
  /// Escape, a text change, losing focus.
  bool _arrowed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _controller
      ..removeListener(_onTextChange)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _disarm() {
    if (_arrowed) {
      setState(() => _arrowed = false);
    }
  }

  void _onTextChange() {
    // Typing un-chooses whatever was chosen: the rows underneath have changed.
    _disarm();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      unawaited(_loadTags());
    } else {
      _disarm();
    }
  }

  Future<void> _loadTags() async {
    if (_loadingTags != null || _tags.isNotEmpty) {
      return;
    }
    final pending = _fetchTags();
    // A block body, not an arrow: `() => _loadingTags = pending` RETURNS the
    // future, and setState rejects a callback that returns one.
    setState(() {
      _loadingTags = pending;
    });
    await pending;
  }

  Future<void> _fetchTags() async {
    try {
      final tags = await context.read<TagsRepository>().listTags();
      if (mounted) {
        setState(() => _tags = tags);
      }
    } on Object {
      // Suggestions are a convenience; a failed fetch must never break
      // searching. The keyword rows do not need the vocabulary and keep
      // working, and a later focus may retry.
    } finally {
      if (mounted) {
        setState(() => _loadingTags = null);
      }
    }
  }

  /// The rows for [value], waiting for the vocabulary when it is still coming.
  FutureOr<Iterable<SearchSuggestion>> _optionsFor(TextEditingValue value) {
    final pending = _loadingTags;
    if (pending != null) {
      return pending.then((_) => _rowsFor(value));
    }
    return _rowsFor(value);
  }

  List<SearchSuggestion> _rowsFor(TextEditingValue value) {
    return _rows = suggestionsFor(
      text: value.text,
      cursor: value.selection.baseOffset,
      tags: _tags,
    );
  }

  /// Puts [option]'s query in the field.
  ///
  /// Deliberately NOT RawAutocomplete's own selection: that suppresses the
  /// options refresh (it sets `_selecting` while it writes) and then hides the
  /// popover, so taking `tag:` would close the list instead of opening the
  /// tags — the feature's whole two-step. Writing the controller is an ordinary
  /// text change, so the rows recompute for the new caret and the popover
  /// follows the user into the value.
  void _take(SearchSuggestion option) {
    _controller.value = TextEditingValue(
      text: option.query,
      selection: TextSelection.collapsed(offset: option.cursor),
    );
  }

  /// Arrow and Escape keys, seen before RawAutocomplete's own shortcuts.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Escape hides the popover (RawAutocomplete's DismissIntent) but cannot
      // tell this flag, and an armed Enter with no popover showing routes to a
      // handler that no-ops: the key goes dead until another character is
      // typed. Disarm and let the dismissal through.
      _disarm();
      return KeyEventResult.ignored;
    }
    final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!isDown && !isUp) {
      return KeyEventResult.ignored;
    }
    if (_rows.isEmpty) {
      // Nothing to choose. Arming here is how an arrow press on an ordinary
      // query — where no popover ever opened — killed Enter outright.
      return KeyEventResult.ignored;
    }
    if (!_arrowed) {
      // The FIRST arrow press chooses the row already sitting at index 0.
      // Letting it through would advance to index 1 and skip the top row,
      // because RawAutocomplete's highlight starts at 0 rather than at
      // "nothing".
      setState(() {
        _arrowed = true;
        _highlighted = 0;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Enter: take the chosen row, or search exactly what was typed.
  void _onEnter(String value) {
    // Both halves are needed and each alone would do: _onKey will not arm
    // without rows, and this refuses to take one from an empty list. Belt and
    // braces on a flag whose every desync so far made Enter a dead key.
    if (_arrowed && _rows.isNotEmpty) {
      _take(_rows[_highlighted.clamp(0, _rows.length - 1)]);
      return;
    }
    _submit(value);
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      return;
    }
    // Resubmitting the query already on screen: go() to the same location
    // is a no-op (the results cubit is keyed by query), so refresh the
    // results in place instead — e.g. after an import or a load error.
    final onRefresh = widget.onRefresh;
    if (onRefresh != null && query == widget.initialQuery?.trim()) {
      onRefresh();
      return;
    }
    context.go('/search?q=${Uri.encodeQueryComponent(query)}');
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: RawAutocomplete<SearchSuggestion>(
        textEditingController: _controller,
        focusNode: _focus,
        // Rows are taken by _take, never by RawAutocomplete's own selection,
        // so this only feeds the widget's internal bookkeeping.
        displayStringForOption: (option) => option.query,
        optionsBuilder: _optionsFor,
        optionsViewBuilder: (context, onSelected, options) {
          // Mirrored out here because the field cannot reach it: this
          // InheritedNotifier is installed inside the options view, not above
          // fieldViewBuilder.
          _highlighted = AutocompleteHighlightedOption.of(context);
          return _SuggestionList(
            options: options.toList(),
            onSelected: _take,
            // No highlight until the user has actually chosen: a highlighted
            // row that Enter would not take is a lie about what Enter does.
            highlight: _arrowed ? _highlighted : null,
          );
        },
        fieldViewBuilder: (context, controller, focusNode, _) {
          return Container(
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Semantics(
              label: 'Search recipes',
              child: Focus(
                canRequestFocus: false,
                onKeyEvent: _onKey,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  // NOT RawAutocomplete's onFieldSubmitted: it takes whatever
                  // is highlighted, and nothing is chosen until _arrowed.
                  onSubmitted: _onEnter,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search recipes — try title:cake or tag:dessert',
                    hintStyle: const TextStyle(
                      color: SaltColors.muted,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 19,
                      color: SaltColors.muted,
                    ),
                    // A help affordance next to the search action, both living
                    // inside the field (replaces the old floating "?" button).
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Search syntax',
                          child: FButton.icon(
                            variant: FButtonVariant.ghost,
                            size: FButtonSizeVariant.xs,
                            semanticsLabel: 'Search syntax',
                            onPress: () => showSearchHelp(context),
                            child: const Icon(Icons.help_outline, size: 18),
                          ),
                        ),
                        Tooltip(
                          message: 'Search',
                          child: FButton.icon(
                            variant: FButtonVariant.ghost,
                            size: FButtonSizeVariant.xs,
                            semanticsLabel: 'Search',
                            onPress: () => _submit(controller.text),
                            // Keep the rose accent on the submit arrow.
                            child: const Icon(
                              Icons.arrow_forward,
                              size: 18,
                              color: SaltColors.rose,
                            ),
                          ),
                        ),
                      ],
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The suggestion rows: keyword rows and tag rows, styled to the nav bar
/// rather than to Material's defaults.
///
/// Two hosts share this one renderer so the rows can never drift: the desktop
/// field's floating overlay (the default) and the mobile dialog's inline list
/// ([embedded]). Embedded drops the floating card — the Align, the top gap, the
/// elevation, the overlay's own max width — because the dialog already provides
/// the surface and the width.
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.options,
    required this.onSelected,
    required this.highlight,
    this.embedded = false,
  });

  final List<SearchSuggestion> options;
  final void Function(SearchSuggestion) onSelected;
  final int? highlight;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final list = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: embedded ? double.infinity : 620,
        maxHeight: 280,
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        shrinkWrap: true,
        itemCount: options.length,
        itemBuilder: (context, index) {
          final option = options[index];
          return InkWell(
            onTap: () => onSelected(option),
            child: Container(
              color: index == highlight
                  ? SaltColors.maroon.withValues(alpha: 0.08)
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Text(
                    option.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SaltColors.ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option.detail,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SaltColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (embedded) {
      // The rows use InkWell, which needs a Material ancestor. The desktop
      // overlay below supplies one via its elevated Material; the embedded
      // (dialog) case has none — FDialog paints no Material — so add a
      // transparent one here.
      return Material(type: MaterialType.transparency, child: list);
    }
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(9),
          child: list,
        ),
      ),
    );
  }
}

/// Role-aware avatar menu (approved P3 design): username/role header,
/// Settings, Sign out. Members and admins currently share the same entries;
/// admin-only actions (add recipe, import) arrive with their phases.
class _AvatarMenu extends StatelessWidget {
  const _AvatarMenu();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthCubit>().user;
    if (user == null) {
      return const SizedBox.shrink();
    }
    return FPopoverMenu(
      // The menu drops from the avatar at the right edge of the bar.
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      menuBuilder: (menuContext, controller, _) {
        // Close the menu, then act. Popover items are not assumed to
        // auto-dismiss — hide() explicitly so navigation never leaves an
        // open menu behind.
        void go(String route) {
          controller.hide();
          context.push(route);
        }

        return [
          FItemGroup(
            children: [
              FItem(
                enabled: false,
                title: Text(
                  user.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: SaltColors.ink,
                  ),
                ),
                subtitle: Text(user.role),
              ),
            ],
          ),
          FItemGroup(
            children: [
              if (user.isAdmin)
                FItem(
                  title: const Text('Add recipe'),
                  onPress: () => go('/new'),
                ),
              if (user.isAdmin)
                FItem(
                  title: const Text('Recipe review'),
                  suffix: const _ReviewCountBadge(),
                  onPress: () => go('/review'),
                ),
              FItem(
                title: const Text('My favorites'),
                onPress: () => go('/favorites'),
              ),
              FItem(
                title: const Text('Settings'),
                onPress: () => go('/settings'),
              ),
            ],
          ),
          FItemGroup(
            children: [
              FItem(
                // Destructive: the theme paints errInk; label it red to match.
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: SaltColors.errInk),
                ),
                onPress: () {
                  controller.hide();
                  context.read<AuthCubit>().signOut();
                },
              ),
            ],
          ),
        ];
      },
      builder: (context, controller, _) => Semantics(
        button: true,
        label: 'Account menu',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.toggle,
          child: CircleAvatar(
            radius: 17,
            backgroundColor: Colors.white,
            child: Text(
              user.username.isEmpty ? '?' : user.username[0].toUpperCase(),
              style: const TextStyle(
                color: SaltColors.maroon,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The count of recipes needing review, as a small maroon pill beside the
/// "Recipe review" menu item. The tally is memoized on the repository, so this
/// costs one fetch per session; it hides itself while loading or when zero.
class _ReviewCountBadge extends StatelessWidget {
  const _ReviewCountBadge();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: context.read<RecipeRepository>().reviewCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count <= 0) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: SaltColors.maroon,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        );
      },
    );
  }
}

/// Compact-width search entry point: the inline search field is dropped on
/// narrow screens, so this icon opens a labelled dialog carrying the same
/// suggestions (keyword rows, real tag names) the desktop field offers — the
/// feature used to disappear entirely below [Breakpoints.compact].
class _MobileSearchButton extends StatelessWidget {
  const _MobileSearchButton({this.initialQuery, this.onRefresh});

  final String? initialQuery;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Search',
      child: FButton.icon(
        variant: FButtonVariant.ghost,
        size: FButtonSizeVariant.xs,
        semanticsLabel: 'Search',
        onPress: () => _openSearch(context),
        child: const Icon(Icons.search, size: 22, color: Colors.white),
      ),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    // Read the repository from the nav bar's context, not the dialog's: the
    // dialog route may sit under a different provider scope.
    final query = await showFDialog<String>(
      context: context,
      builder: (_, __, animation) => _MobileSearchDialog(
        tagsRepository: context.read<TagsRepository>(),
        initialQuery: initialQuery,
        animation: animation,
      ),
    );
    if (query == null || !context.mounted) {
      return;
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final refresh = onRefresh;
    if (refresh != null && trimmed == initialQuery?.trim()) {
      refresh();
      return;
    }
    context.go('/search?q=${Uri.encodeQueryComponent(trimmed)}');
  }
}

/// The mobile search dialog's content: a query field with the live suggestion
/// list beneath it.
///
/// Simpler than the desktop [_SearchField] by design — a dialog is tap-driven,
/// so none of the arrow-key / `_arrowed` / highlight machinery applies. A row is
/// TAKEN (fills the field, exactly as the desktop `_take` does, so the `tag:`
/// two-step still opens the tags in place); Enter or the Search button SUBMITS
/// whatever is in the field. The tags are fetched once when the dialog opens; a
/// failed fetch is silent, and the keyword rows work without the vocabulary.
class _MobileSearchDialog extends StatefulWidget {
  const _MobileSearchDialog({
    required this.tagsRepository,
    required this.animation,
    this.initialQuery,
  });

  final TagsRepository tagsRepository;

  /// The dialog route's entrance animation, threaded into [FDialog] so it
  /// scales/fades in.
  final Animation<double> animation;
  final String? initialQuery;

  @override
  State<_MobileSearchDialog> createState() => _MobileSearchDialogState();
}

class _MobileSearchDialogState extends State<_MobileSearchDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  List<TagInfo> _tags = const [];
  List<SearchSuggestion> _rows = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_recompute);
    _rows = _rowsFor(_controller.value);
    unawaited(_loadTags());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_recompute)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await widget.tagsRepository.listTags();
      if (mounted) {
        setState(() {
          _tags = tags;
          // Recompute against the vocabulary that just arrived: a pre-filled
          // `tag:des` must gain its rows when the fetch lands, not on the next
          // keystroke.
          _rows = _rowsFor(_controller.value);
        });
      }
    } on Object {
      // Suggestions are a convenience; a failed fetch must never break
      // searching. Keyword rows need no vocabulary and keep working.
    }
  }

  void _recompute() {
    setState(() => _rows = _rowsFor(_controller.value));
  }

  List<SearchSuggestion> _rowsFor(TextEditingValue value) => suggestionsFor(
    text: value.text,
    cursor: value.selection.baseOffset,
    tags: _tags,
  );

  /// Puts [option]'s query in the field; the listener recomputes the rows, so
  /// taking `tag:` reveals the tags without another keystroke.
  void _take(SearchSuggestion option) {
    _controller.value = TextEditingValue(
      text: option.query,
      selection: TextSelection.collapsed(offset: option.cursor),
    );
  }

  // One handler for both onSubmitted (String) and onPressed (no arg): the
  // optional positional makes it assignable to each.
  void _submit([String? _]) => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return FDialog(
      animation: widget.animation,
      builder: (context, style) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Search recipes', style: style.titleTextStyle),
                ),
                Tooltip(
                  message: 'Search syntax',
                  child: FButton.icon(
                    variant: FButtonVariant.ghost,
                    size: FButtonSizeVariant.xs,
                    semanticsLabel: 'Search syntax',
                    onPress: () => showSearchHelp(context),
                    child: const Icon(Icons.help_outline, size: 19),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Semantics(
              label: 'Search recipes',
              child: FTextField(
                control: FTextFieldControl.managed(controller: _controller),
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmit: _submit,
                hint: 'try title:cake or tag:dessert',
              ),
            ),
          ),
          if (_rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: _SuggestionList(
                options: _rows,
                onSelected: _take,
                highlight: null,
                embedded: true,
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
                    onPress: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FButton(onPress: _submit, child: const Text('Search')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
