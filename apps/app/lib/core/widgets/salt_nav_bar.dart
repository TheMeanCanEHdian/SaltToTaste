import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
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

  /// Whether to show a leading back control (used on drill-down pages).
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
                if (showBack) ...[
                  IconButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 4),
                ],
                Semantics(
                  button: true,
                  label: 'Home',
                  child: InkWell(
                    onTap: () => context.go('/'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: ExcludeSemantics(
                        child: Image.asset(
                          'assets/images/logo_banner.png',
                          height: 36,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => const Text(
                            'Salt to Taste',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                if (!compact)
                  Expanded(
                    child: _SearchField(
                      initialQuery: initialQuery,
                      onRefresh: onSearchRefresh,
                    ),
                  )
                else ...[
                  const Spacer(),
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
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      icon: const Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: SaltColors.rose,
                      ),
                      onPressed: () => _submit(controller.text),
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

/// The suggestion popover: keyword rows and tag rows, styled to the nav bar
/// rather than to Material's defaults.
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.options,
    required this.onSelected,
    required this.highlight,
  });

  final List<SearchSuggestion> options;
  final void Function(SearchSuggestion) onSelected;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(9),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 280),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
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
          ),
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
    return PopupMenuButton<String>(
      tooltip: 'Account menu',
      offset: const Offset(0, 46),
      onSelected: (value) {
        switch (value) {
          case 'add':
            context.push('/new');
          case 'favorites':
            context.push('/favorites');
          case 'settings':
            context.push('/settings');
          case 'signout':
            context.read<AuthCubit>().signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user.username,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SaltColors.ink,
                ),
              ),
              Text(
                user.role,
                style: const TextStyle(fontSize: 12, color: SaltColors.muted),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (user.isAdmin)
          const PopupMenuItem<String>(value: 'add', child: Text('Add recipe')),
        const PopupMenuItem<String>(
          value: 'favorites',
          child: Text('My favorites'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'settings', child: Text('Settings')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'signout',
          child: Text('Sign out', style: TextStyle(color: Color(0xFF8A1212))),
        ),
      ],
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
    );
  }
}

/// Compact-width search entry point: the inline search field is dropped on
/// narrow screens, so this icon opens a labelled dialog with the same query
/// field, keeping search reachable (and accessible) on mobile.
class _MobileSearchButton extends StatelessWidget {
  const _MobileSearchButton({this.initialQuery, this.onRefresh});

  final String? initialQuery;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Search',
      icon: const Icon(Icons.search, color: Colors.white),
      onPressed: () => _openSearch(context),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final controller = TextEditingController(text: initialQuery);
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Search recipes'),
        content: Semantics(
          label: 'Search recipes',
          child: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'try title:cake or tag:dessert',
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SaltColors.maroon),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
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
