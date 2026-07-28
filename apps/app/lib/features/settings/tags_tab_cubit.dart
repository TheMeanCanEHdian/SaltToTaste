import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/features/tags/tag_styles_cubit.dart';

/// Sort orders for the tags listing.
enum TagSort { mostRecipes, alphabetical }

/// Immutable state for the Settings → Tags tab (approved P4 mockup,
/// docs/mockups/p4-tags.html).
class TagsTabState {
  const TagsTabState({
    this.tags,
    this.loadError,
    this.filter = '',
    this.sort = TagSort.mostRecipes,
    this.editingTag,
    this.draftIcon,
    this.draftColor = '',
    this.draftBgColor = '',
    this.saving = false,
    this.saveError,
  });

  /// Every tag as the server returned it; null until the first load lands.
  final List<TagInfo>? tags;

  /// Failure message from the initial load (or a retry of it).
  final String? loadError;

  /// Case-insensitive substring filter on tag names.
  final String filter;

  final TagSort sort;

  /// Name of the tag whose editor panel is open — at most one at a time.
  final String? editingTag;

  /// Draft icon name for the open editor (null = NONE / no icon).
  final String? draftIcon;

  /// Raw text of the two hex fields — may be empty or mid-edit invalid.
  final String draftColor;
  final String draftBgColor;

  final bool saving;
  final String? saveError;

  static final RegExp _hexPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

  /// The trimmed text when it is exactly `#RRGGBB`, otherwise null.
  static String? validHexOrNull(String text) {
    final trimmed = text.trim();
    return _hexPattern.hasMatch(trimmed) ? trimmed : null;
  }

  /// Non-empty text that is not a valid `#RRGGBB` color.
  bool get draftColorInvalid =>
      draftColor.trim().isNotEmpty && validHexOrNull(draftColor) == null;
  bool get draftBgColorInvalid =>
      draftBgColor.trim().isNotEmpty && validHexOrNull(draftBgColor) == null;

  /// Save is blocked while either hex field holds invalid non-empty text.
  bool get canSave => !draftColorInvalid && !draftBgColorInvalid;

  /// The style the draft would save. Invalid hex fields fall back to null
  /// (the default look) so the live preview always matches what Save sends.
  TagStyle get draftStyle => TagStyle(
    icon: draftIcon,
    color: validHexOrNull(draftColor),
    bgColor: validHexOrNull(draftBgColor),
  );

  /// The rows to display, after applying [filter] and [sort].
  List<TagInfo> get visibleTags {
    final all = tags;
    if (all == null) {
      return const [];
    }
    final query = filter.trim().toLowerCase();
    final matches = [
      for (final tag in all)
        if (query.isEmpty || tag.name.toLowerCase().contains(query)) tag,
    ];
    if (sort == TagSort.mostRecipes) {
      matches.sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0
            ? byCount
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } else {
      matches.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    return matches;
  }

  static const Object _unset = Object();

  TagsTabState copyWith({
    List<TagInfo>? tags,
    Object? loadError = _unset,
    String? filter,
    TagSort? sort,
    Object? editingTag = _unset,
    Object? draftIcon = _unset,
    String? draftColor,
    String? draftBgColor,
    bool? saving,
    Object? saveError = _unset,
  }) {
    return TagsTabState(
      tags: tags ?? this.tags,
      loadError: identical(loadError, _unset)
          ? this.loadError
          : loadError as String?,
      filter: filter ?? this.filter,
      sort: sort ?? this.sort,
      editingTag: identical(editingTag, _unset)
          ? this.editingTag
          : editingTag as String?,
      draftIcon: identical(draftIcon, _unset)
          ? this.draftIcon
          : draftIcon as String?,
      draftColor: draftColor ?? this.draftColor,
      draftBgColor: draftBgColor ?? this.draftBgColor,
      saving: saving ?? this.saving,
      saveError: identical(saveError, _unset)
          ? this.saveError
          : saveError as String?,
    );
  }
}

/// Drives the Settings → Tags tab: loads the tag list, tracks the filter,
/// sort, and the single open inline editor, and saves/clears chip styles.
///
/// After any successful save it reloads the list and refreshes the app-wide
/// [TagStylesCubit] so chips everywhere pick up the new style immediately.
class TagsTabCubit extends Cubit<TagsTabState> {
  TagsTabCubit(this._repository, this._appStyles) : super(const TagsTabState());

  final TagsRepository _repository;
  final TagStylesCubit _appStyles;

  /// Fetches (or refetches) the tag list.
  Future<void> load() async {
    emit(state.copyWith(loadError: null));
    try {
      final tags = await _repository.listTags();
      if (!isClosed) {
        emit(state.copyWith(tags: tags));
      }
    } on RepositoryException catch (exception) {
      if (!isClosed) {
        emit(state.copyWith(loadError: exception.message));
      }
    }
  }

  void setFilter(String filter) => emit(state.copyWith(filter: filter));

  void setSort(TagSort sort) => emit(state.copyWith(sort: sort));

  /// Opens the inline editor for [tag], seeding the draft from its current
  /// style (closing any other editor — only one is open at a time).
  void openEditor(TagInfo tag) {
    if (state.saving) {
      return;
    }
    emit(
      state.copyWith(
        editingTag: tag.name,
        draftIcon: tag.style.icon,
        draftColor: tag.style.color ?? '',
        draftBgColor: tag.style.bgColor ?? '',
        saveError: null,
      ),
    );
  }

  void closeEditor() => emit(state.copyWith(editingTag: null, saveError: null));

  void setDraftIcon(String? icon) => emit(state.copyWith(draftIcon: icon));

  /// Updates one or both draft hex fields (raw text, validated lazily).
  void setDraftColors({String? color, String? bgColor}) =>
      emit(state.copyWith(draftColor: color, draftBgColor: bgColor));

  /// Saves the draft style for the tag being edited.
  Future<void> save() async {
    if (!state.canSave) {
      return;
    }
    await _submit(state.draftStyle);
  }

  /// Resets the open editor's draft to the default chip look (no icon, default
  /// colours) without saving — the user still chooses Save or Cancel.
  void resetDraft() =>
      emit(state.copyWith(draftIcon: null, draftColor: '', draftBgColor: ''));

  Future<void> _submit(TagStyle style) async {
    final tag = state.editingTag;
    if (tag == null || state.saving) {
      return;
    }
    emit(state.copyWith(saving: true, saveError: null));
    try {
      await _repository.setStyle(tag, style);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(saving: false, editingTag: null));
      await load();
      await _appStyles.load();
    } on RepositoryException catch (exception) {
      if (!isClosed) {
        emit(state.copyWith(saving: false, saveError: exception.message));
      }
    }
  }
}
