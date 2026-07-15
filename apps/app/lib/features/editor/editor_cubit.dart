import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart';

/// One entry of the editor's ingredient list: a group header or a line.
sealed class EditorEntry {
  EditorEntry(this.key);

  /// Stable identity for list diffing/reordering.
  final int key;
}

/// A group header ("FOR THE GLAZE") — renders as a section on the recipe
/// page.
final class EditorGroupHeader extends EditorEntry {
  EditorGroupHeader(super.key, this.name);

  final String name;

  EditorGroupHeader withName(String name) => EditorGroupHeader(key, name);
}

/// One ingredient line. The raw text is authoritative for display; the
/// structured fields feed scaling and nutrition. [manuallyEdited] locks the
/// structured fields against automatic re-parsing (typing in the raw field
/// then only *suggests* — the explicit re-parse button applies).
final class EditorLine extends EditorEntry {
  EditorLine(
    super.key, {
    required this.raw,
    required this.amounts,
    this.item,
    this.prep,
    required this.confidence,
    this.manuallyEdited = false,
    this.expanded = false,
  });

  factory EditorLine.parsed(int key, String raw) {
    final parsed = parseIngredientLine(raw);
    return EditorLine(
      key,
      raw: raw,
      amounts: parsed.amounts,
      item: parsed.item,
      prep: parsed.prep,
      confidence: parsed.confidence,
    );
  }

  final String raw;
  final List<Amount> amounts;
  final String? item;
  final String? prep;
  final ParseConfidence confidence;
  final bool manuallyEdited;
  final bool expanded;

  EditorLine copyWith({
    String? raw,
    List<Amount>? amounts,
    String? item,
    bool clearItem = false,
    String? prep,
    bool clearPrep = false,
    ParseConfidence? confidence,
    bool? manuallyEdited,
    bool? expanded,
  }) =>
      EditorLine(
        key,
        raw: raw ?? this.raw,
        amounts: amounts ?? this.amounts,
        item: clearItem ? null : (item ?? this.item),
        prep: clearPrep ? null : (prep ?? this.prep),
        confidence: confidence ?? this.confidence,
        manuallyEdited: manuallyEdited ?? this.manuallyEdited,
        expanded: expanded ?? this.expanded,
      );

  IngredientLine toIngredientLine() => IngredientLine(
        raw: raw,
        amounts: amounts,
        item: item,
        prep: prep,
      );
}

/// One direction step in the editor.
final class EditorStep {
  EditorStep(this.key, {this.label = '', this.text = ''});

  final int key;
  final String label;
  final String text;

  EditorStep copyWith({String? label, String? text}) => EditorStep(
        key,
        label: label ?? this.label,
        text: text ?? this.text,
      );
}

/// The whole editor state — a working copy of the recipe's editable fields
/// plus save/dirty bookkeeping.
final class EditorState {
  const EditorState({
    this.loading = false,
    this.loadError,
    this.recipeId,
    this.slug,
    this.title = '',
    this.servings = '',
    this.category = '',
    this.sourceName = '',
    this.sourceUrl = '',
    this.tags = const [],
    this.background = '',
    this.prepNotes = '',
    this.notes = '',
    this.entries = const [],
    this.steps = const [],
    this.images = const RecipeImages(),
    this.heroImageUrl,
    this.credit = '',
    this.dirty = false,
    this.saving = false,
    this.uploadingImage = false,
    this.saveError,
    this.savedSlug,
    this.deleted = false,
  });

  final bool loading;
  final String? loadError;

  /// Null while creating a new recipe (id/slug are server-generated).
  final String? recipeId;
  final String? slug;

  final String title;
  final String servings;
  final String category;
  final String sourceName;
  final String sourceUrl;
  final List<String> tags;
  final String background;
  final String prepNotes;
  final String notes;
  final List<EditorEntry> entries;
  final List<EditorStep> steps;

  /// The stored images block (hero/gallery refs live server-side; the
  /// editor edits only the credit and attaches photos via the endpoints).
  final RecipeImages images;
  final String? heroImageUrl;
  final String credit;

  final bool dirty;
  final bool saving;
  final bool uploadingImage;
  final String? saveError;

  /// Set after a successful save — the page navigates to this slug.
  final String? savedSlug;

  /// Set after a successful delete — the page navigates home.
  final bool deleted;

  /// Whether this is a brand-new, never-saved recipe.
  bool get isNew => recipeId == null;

  /// Parsed numeric yield preview for the servings badge.
  Serves? get parsedServes => parseServings(servings);

  EditorState copyWith({
    bool? loading,
    String? loadError,
    String? recipeId,
    String? slug,
    String? title,
    String? servings,
    String? category,
    String? sourceName,
    String? sourceUrl,
    List<String>? tags,
    String? background,
    String? prepNotes,
    String? notes,
    List<EditorEntry>? entries,
    List<EditorStep>? steps,
    RecipeImages? images,
    String? heroImageUrl,
    String? credit,
    bool? dirty,
    bool? saving,
    bool? uploadingImage,
    String? saveError,
    bool clearSaveError = false,
    String? savedSlug,
    bool? deleted,
  }) =>
      EditorState(
        loading: loading ?? this.loading,
        loadError: loadError,
        recipeId: recipeId ?? this.recipeId,
        slug: slug ?? this.slug,
        title: title ?? this.title,
        servings: servings ?? this.servings,
        category: category ?? this.category,
        sourceName: sourceName ?? this.sourceName,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        tags: tags ?? this.tags,
        background: background ?? this.background,
        prepNotes: prepNotes ?? this.prepNotes,
        notes: notes ?? this.notes,
        entries: entries ?? this.entries,
        steps: steps ?? this.steps,
        images: images ?? this.images,
        heroImageUrl: heroImageUrl ?? this.heroImageUrl,
        credit: credit ?? this.credit,
        dirty: dirty ?? this.dirty,
        saving: saving ?? this.saving,
        uploadingImage: uploadingImage ?? this.uploadingImage,
        saveError: clearSaveError ? null : (saveError ?? this.saveError),
        savedSlug: savedSlug ?? this.savedSlug,
        deleted: deleted ?? this.deleted,
      );
}

/// Drives the recipe editor: loads the working copy, applies field edits
/// (marking dirty), parses ingredient lines, and saves through the API.
class EditorCubit extends Cubit<EditorState> {
  EditorCubit(this._repository) : super(const EditorState());

  final RecipeRepository _repository;
  int _nextKey = 0;

  int get _key => _nextKey++;

  /// Starts a new, empty recipe.
  void startNew() {
    emit(EditorState(
      entries: [EditorLine(_key, raw: '', amounts: const [], confidence: ParseConfidence.none)],
      steps: [EditorStep(_key)],
    ));
  }

  /// Whether the parser fully explains this stored line — if not, the
  /// structured fields were curated by a human (the corpus review queue)
  /// and must not be silently replaced by re-parsing on the next keystroke.
  static bool _parserExplains(IngredientLine line) {
    final parsed = parseIngredientLine(line.raw);
    if (parsed.item != line.item || parsed.prep != line.prep) {
      return false;
    }
    if (parsed.amounts.length != line.amounts.length) {
      return false;
    }
    for (var i = 0; i < parsed.amounts.length; i += 1) {
      if (parsed.amounts[i] != line.amounts[i]) {
        return false;
      }
    }
    return true;
  }

  /// Loads an existing recipe into the editor.
  Future<void> load(String idOrSlug) async {
    emit(const EditorState(loading: true));
    try {
      final detail = await _repository.getRecipe(idOrSlug);
      if (isClosed) {
        return;
      }
      final recipe = detail.recipe;
      emit(EditorState(
        recipeId: recipe.id,
        slug: recipe.slug,
        title: recipe.title,
        servings: recipe.servings ?? '',
        category: recipe.category ?? '',
        sourceName: recipe.source.name,
        sourceUrl: recipe.source.url ?? '',
        tags: recipe.tags,
        background: recipe.background ?? '',
        prepNotes: recipe.prepNotes ?? '',
        notes: recipe.notes ?? '',
        entries: [
          for (final group in recipe.ingredients) ...[
            if (group.group != null) EditorGroupHeader(_key, group.group!),
            for (final line in group.items)
              EditorLine(
                _key,
                raw: line.raw,
                amounts: line.amounts,
                item: line.item,
                prep: line.prep,
                confidence: line.amounts.isEmpty
                    ? ParseConfidence.none
                    : ParseConfidence.parsed,
                // Curated structured data (differing from what the parser
                // would produce) is locked against automatic re-parsing.
                manuallyEdited: !_parserExplains(line),
              ),
          ],
        ],
        steps: [
          for (final step in recipe.steps)
            EditorStep(_key, label: step.label ?? '', text: step.text),
        ],
        images: recipe.images,
        heroImageUrl: detail.heroImageUrl,
        credit: recipe.images.credit ?? '',
      ));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(EditorState(loadError: exception.message));
    }
  }

  // ------------------------------------------------------------------
  // Field edits (each marks the document dirty).
  // ------------------------------------------------------------------

  void setTitle(String value) =>
      emit(state.copyWith(title: value, dirty: true));
  void setServings(String value) =>
      emit(state.copyWith(servings: value, dirty: true));
  void setCategory(String value) =>
      emit(state.copyWith(category: value, dirty: true));
  void setSourceName(String value) =>
      emit(state.copyWith(sourceName: value, dirty: true));
  void setSourceUrl(String value) =>
      emit(state.copyWith(sourceUrl: value, dirty: true));
  void setBackground(String value) =>
      emit(state.copyWith(background: value, dirty: true));
  void setPrepNotes(String value) =>
      emit(state.copyWith(prepNotes: value, dirty: true));
  void setNotes(String value) =>
      emit(state.copyWith(notes: value, dirty: true));
  void setCredit(String value) =>
      emit(state.copyWith(credit: value, dirty: true));

  void addTag(String tag) {
    final normalized = tag.trim().toLowerCase();
    if (normalized.isEmpty || state.tags.contains(normalized)) {
      return;
    }
    emit(state.copyWith(tags: [...state.tags, normalized], dirty: true));
  }

  void removeTag(String tag) => emit(state.copyWith(
        tags: [...state.tags]..remove(tag),
        dirty: true,
      ));

  // ------------------------------------------------------------------
  // Ingredient entries.
  // ------------------------------------------------------------------

  void addLine() => emit(state.copyWith(
        entries: [
          ...state.entries,
          EditorLine(_key,
              raw: '', amounts: const [], confidence: ParseConfidence.none),
        ],
        dirty: true,
      ));

  void addGroupHeader() => emit(state.copyWith(
        entries: [...state.entries, EditorGroupHeader(_key, '')],
        dirty: true,
      ));

  /// Appends parsed lines (and `Header:` group rows) from the paste dialog.
  void addPastedLines(List<String> lines) {
    final additions = <EditorEntry>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.endsWith(':')) {
        additions.add(EditorGroupHeader(
          _key,
          line.substring(0, line.length - 1).trim().toUpperCase(),
        ));
      } else {
        additions.add(EditorLine.parsed(_key, line));
      }
    }
    if (additions.isEmpty) {
      return;
    }
    emit(state.copyWith(
      entries: [...state.entries, ...additions],
      dirty: true,
    ));
  }

  void removeEntry(int key) => emit(state.copyWith(
        entries: [
          for (final entry in state.entries)
            if (entry.key != key) entry,
        ],
        dirty: true,
      ));

  /// [newIndex] is already adjusted for the removal (onReorderItem).
  void reorderEntries(int oldIndex, int newIndex) {
    final entries = [...state.entries];
    final entry = entries.removeAt(oldIndex);
    entries.insert(newIndex, entry);
    emit(state.copyWith(entries: entries, dirty: true));
  }

  void renameGroup(int key, String name) => _updateEntry(
        key,
        (entry) => entry is EditorGroupHeader ? entry.withName(name) : entry,
      );

  /// The raw text changed. Committed to state IMMEDIATELY (a save or a
  /// leave-check must never miss in-flight typing); the structured-field
  /// parse follows separately via the debounced [applyAutoParse].
  void setLineRaw(int key, String raw) => _updateEntry(
        key,
        (entry) => entry is EditorLine ? entry.copyWith(raw: raw) : entry,
      );

  /// Applies the parser to the line's CURRENT raw text — called on the
  /// widget's debounce. Hand-edited (locked) lines are left alone; the
  /// explicit re-parse button is their only path.
  void applyAutoParse(int key) => _updateEntry(key, (entry) {
        if (entry is! EditorLine || entry.manuallyEdited) {
          return entry;
        }
        final parsed = parseIngredientLine(entry.raw);
        return entry.copyWith(
          amounts: parsed.amounts,
          item: parsed.item,
          clearItem: parsed.item == null,
          prep: parsed.prep,
          clearPrep: parsed.prep == null,
          confidence: parsed.confidence,
        );
      }, markDirty: false);

  void toggleLineExpanded(int key) => _updateEntry(
        key,
        (entry) => entry is EditorLine
            ? entry.copyWith(expanded: !entry.expanded)
            : entry,
        markDirty: false,
      );

  /// Structured-field edits lock the line against automatic re-parsing.
  void setLineStructured(
    int key, {
    List<Amount>? amounts,
    String? item,
    bool clearItem = false,
    String? prep,
    bool clearPrep = false,
  }) =>
      _updateEntry(key, (entry) {
        if (entry is! EditorLine) {
          return entry;
        }
        return entry.copyWith(
          amounts: amounts,
          item: item,
          clearItem: clearItem,
          prep: prep,
          clearPrep: clearPrep,
          manuallyEdited: true,
        );
      });

  /// The explicit re-parse: applies the parser output and clears the lock.
  void reparseLine(int key) => _updateEntry(key, (entry) {
        if (entry is! EditorLine) {
          return entry;
        }
        final parsed = parseIngredientLine(entry.raw);
        return entry.copyWith(
          amounts: parsed.amounts,
          item: parsed.item,
          clearItem: parsed.item == null,
          prep: parsed.prep,
          clearPrep: parsed.prep == null,
          confidence: parsed.confidence,
          manuallyEdited: false,
        );
      });

  void _updateEntry(
    int key,
    EditorEntry Function(EditorEntry) transform, {
    bool markDirty = true,
  }) {
    emit(state.copyWith(
      entries: [
        for (final entry in state.entries)
          if (entry.key == key) transform(entry) else entry,
      ],
      dirty: markDirty ? true : null,
    ));
  }

  // ------------------------------------------------------------------
  // Steps.
  // ------------------------------------------------------------------

  void addStep() => emit(state.copyWith(
        steps: [...state.steps, EditorStep(_key)],
        dirty: true,
      ));

  void removeStep(int key) => emit(state.copyWith(
        steps: [
          for (final step in state.steps)
            if (step.key != key) step,
        ],
        dirty: true,
      ));

  /// [newIndex] is already adjusted for the removal (onReorderItem).
  void reorderSteps(int oldIndex, int newIndex) {
    final steps = [...state.steps];
    final step = steps.removeAt(oldIndex);
    steps.insert(newIndex, step);
    emit(state.copyWith(steps: steps, dirty: true));
  }

  void setStep(int key, {String? label, String? text}) =>
      emit(state.copyWith(
        steps: [
          for (final step in state.steps)
            if (step.key == key)
              step.copyWith(label: label, text: text)
            else
              step,
        ],
        dirty: true,
      ));

  // ------------------------------------------------------------------
  // Photos (existing recipes only — a new recipe has no id yet).
  // ------------------------------------------------------------------

  Future<void> uploadPhoto(List<int> bytes, {required String role}) async {
    final id = state.recipeId;
    if (id == null || state.uploadingImage) {
      return;
    }
    emit(state.copyWith(uploadingImage: true, clearSaveError: true));
    try {
      final detail = await _repository.uploadImage(
        id,
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        role: role,
      );
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        uploadingImage: false,
        images: detail.recipe.images,
        heroImageUrl: detail.heroImageUrl,
      ));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        uploadingImage: false,
        saveError: exception.message,
      ));
    }
  }

  Future<void> photoFromUrl(String url, {required String role}) async {
    final id = state.recipeId;
    if (id == null || state.uploadingImage) {
      return;
    }
    emit(state.copyWith(uploadingImage: true, clearSaveError: true));
    try {
      final detail = await _repository.imageFromUrl(id, url, role: role);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        uploadingImage: false,
        images: detail.recipe.images,
        heroImageUrl: detail.heroImageUrl,
      ));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        uploadingImage: false,
        saveError: exception.message,
      ));
    }
  }

  // ------------------------------------------------------------------
  // Save / delete.
  // ------------------------------------------------------------------

  Future<void> save() async {
    // Saving mid-upload would send a stale images block (the PUT's merge
    // semantics would unlink the photo the upload just attached).
    if (state.saving || state.uploadingImage) {
      return;
    }
    if (state.title.trim().isEmpty) {
      emit(state.copyWith(saveError: 'A recipe needs a title.'));
      return;
    }
    emit(state.copyWith(saving: true, clearSaveError: true));
    try {
      final fields = _fields();
      final detail = state.isNew
          ? await _repository.createRecipe(fields)
          : await _repository.updateRecipe(state.recipeId!, fields);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        saving: false,
        dirty: false,
        recipeId: detail.recipe.id,
        slug: detail.recipe.slug,
        savedSlug: detail.recipe.slug,
      ));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(saving: false, saveError: exception.message));
    }
  }

  Future<void> delete() async {
    final id = state.recipeId;
    if (id == null || state.saving) {
      return;
    }
    emit(state.copyWith(saving: true, clearSaveError: true));
    try {
      await _repository.deleteRecipe(id);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(saving: false, deleted: true));
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(saving: false, saveError: exception.message));
    }
  }

  /// The editable-field map the server merges (see docs/API.md — absent
  /// keys stay untouched, so times/subsections/techniques survive edits).
  Map<String, Object?> _fields() {
    final groups = <Map<String, Object?>>[];
    String? currentGroup;
    var currentItems = <Map<String, Object?>>[];
    void flush() {
      if (currentItems.isNotEmpty) {
        groups.add({'group': currentGroup, 'items': currentItems});
      }
      currentItems = [];
    }

    for (final entry in state.entries) {
      switch (entry) {
        case EditorGroupHeader(:final name):
          flush();
          currentGroup = name.trim().isEmpty ? null : name.trim();
        case EditorLine():
          if (entry.raw.trim().isNotEmpty) {
            currentItems.add(entry.toIngredientLine().toMap());
          }
      }
    }
    flush();

    return {
      'title': state.title.trim(),
      'servings': _nullable(state.servings),
      'category': _nullable(state.category),
      'tags': state.tags,
      'background': _nullable(state.background),
      'prep_notes': _nullable(state.prepNotes),
      'notes': _nullable(state.notes),
      'source': {
        'name': state.sourceName.trim().isEmpty
            ? 'My Recipes'
            : state.sourceName.trim(),
        'url': _nullable(state.sourceUrl),
      },
      'ingredients': groups,
      'steps': [
        for (final (i, step) in state.steps.indexed)
          if (step.text.trim().isNotEmpty)
            {
              'number': i + 1,
              'label': _nullable(step.label),
              'text': step.text.trim(),
            },
      ],
      // hero/gallery are only ever mutated through the image endpoints;
      // sending them here would race an in-flight upload under the PUT's
      // merge semantics. The block is included only to change the credit.
      if (_nullable(state.credit) != state.images.credit)
        'images': {
          'hero': state.images.hero,
          'gallery': state.images.gallery,
          'credit': _nullable(state.credit),
        },
    };
  }

  static String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
