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
  }) => EditorLine(
    key,
    raw: raw ?? this.raw,
    amounts: amounts ?? this.amounts,
    item: clearItem ? null : (item ?? this.item),
    prep: clearPrep ? null : (prep ?? this.prep),
    confidence: confidence ?? this.confidence,
    manuallyEdited: manuallyEdited ?? this.manuallyEdited,
    expanded: expanded ?? this.expanded,
  );

  IngredientLine toIngredientLine() =>
      IngredientLine(raw: raw, amounts: amounts, item: item, prep: prep);
}

/// One direction step in the editor.
final class EditorStep {
  EditorStep(this.key, {this.label = '', this.text = ''});

  final int key;
  final String label;
  final String text;

  EditorStep copyWith({String? label, String? text}) =>
      EditorStep(key, label: label ?? this.label, text: text ?? this.text);
}

/// A recipe subsection (a variation or a component) in the editor.
///
/// Prose-only variations carry just [title]/[kind]/[body]. A full sub-recipe
/// additionally carries its own ingredient [entries] and [steps].
/// [hasIngredients]/[hasSteps] preserve the model's null-vs-empty distinction:
/// false means the key is ABSENT (prose-only — the YAML omits it), true means
/// present (possibly an empty list). Promoting a prose variation flips the flag
/// on and seeds one empty row.
final class EditorSubsection {
  EditorSubsection(
    this.key, {
    this.title = '',
    this.kind = 'variation',
    this.kindNeedsReview = false,
    this.body = '',
    this.servings = '',
    this.prepNotes = '',
    this.hasIngredients = false,
    this.entries = const [],
    this.hasSteps = false,
    this.steps = const [],
    this.expanded = true,
  });

  final int key;
  final String title;

  /// `variation` | `component` | `unknown` — preserved verbatim so an untouched
  /// subsection's kind never changes on save.
  final String kind;

  /// Whether the kind was auto-guessed and still awaits human confirmation
  /// (drives the review queue). Cleared when the user picks a kind.
  final bool kindNeedsReview;
  final String body;
  final String servings;
  final String prepNotes;

  /// Whether the subsection carries an ingredient list at all (null-vs-empty).
  final bool hasIngredients;
  final List<EditorEntry> entries;

  /// Whether the subsection carries a step list at all (null-vs-empty).
  final bool hasSteps;
  final List<EditorStep> steps;

  /// UI-only: whether the block is expanded in the editor.
  final bool expanded;

  EditorSubsection copyWith({
    String? title,
    String? kind,
    bool? kindNeedsReview,
    String? body,
    String? servings,
    String? prepNotes,
    bool? hasIngredients,
    List<EditorEntry>? entries,
    bool? hasSteps,
    List<EditorStep>? steps,
    bool? expanded,
  }) => EditorSubsection(
    key,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    kindNeedsReview: kindNeedsReview ?? this.kindNeedsReview,
    body: body ?? this.body,
    servings: servings ?? this.servings,
    prepNotes: prepNotes ?? this.prepNotes,
    hasIngredients: hasIngredients ?? this.hasIngredients,
    entries: entries ?? this.entries,
    hasSteps: hasSteps ?? this.hasSteps,
    steps: steps ?? this.steps,
    expanded: expanded ?? this.expanded,
  );
}

/// One illustrated step of a [EditorTechnique] — a caption and an optional
/// stored image reference (`images/<file>`, uploaded via the store endpoint).
final class EditorTechniqueStep {
  EditorTechniqueStep(this.key, {this.image, this.caption = ''});

  final int key;
  final String? image;
  final String caption;

  EditorTechniqueStep copyWith({
    String? image,
    bool clearImage = false,
    String? caption,
  }) => EditorTechniqueStep(
    key,
    image: clearImage ? null : (image ?? this.image),
    caption: caption ?? this.caption,
  );
}

/// An illustrated technique sidebar in the editor: a heading, a description,
/// and a list of illustrated steps.
final class EditorTechnique {
  EditorTechnique(
    this.key, {
    this.heading = '',
    this.description = '',
    this.steps = const [],
    this.expanded = true,
  });

  final int key;
  final String heading;
  final String description;
  final List<EditorTechniqueStep> steps;
  final bool expanded;

  EditorTechnique copyWith({
    String? heading,
    String? description,
    List<EditorTechniqueStep>? steps,
    bool? expanded,
  }) => EditorTechnique(
    key,
    heading: heading ?? this.heading,
    description: description ?? this.description,
    steps: steps ?? this.steps,
    expanded: expanded ?? this.expanded,
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
    this.subsections = const [],
    this.techniques = const [],
    this.images = const RecipeImages(),
    this.heroImageUrl,
    this.sourceSlug = '',
    this.credit = '',
    this.baseHash,
    this.dirty = false,
    this.saving = false,
    this.uploadingImage = false,
    this.uploadingStepKey,
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

  /// The recipe's variations/components.
  final List<EditorSubsection> subsections;

  /// The recipe's illustrated technique sidebars.
  final List<EditorTechnique> techniques;

  /// The stored images block (hero/gallery refs live server-side; the
  /// editor edits only the credit and attaches photos via the endpoints).
  final RecipeImages images;
  final String? heroImageUrl;

  /// The recipe's source slug, needed to root a bare `images/<file>` reference
  /// (e.g. a stored technique-step photo) into a servable
  /// `/images/<source>/<file>` URL — the server does this for [heroImageUrl]
  /// but hands technique-step references through in canonical model form.
  final String sourceSlug;

  final String credit;

  /// The content hash the working copy was loaded at, echoed on save so a
  /// concurrent save is a 409 conflict instead of a silent overwrite
  /// (review B11). Refreshed from every detail response (save, image
  /// attach) so the still-open editor can keep saving.
  final String? baseHash;

  final bool dirty;
  final bool saving;
  final bool uploadingImage;

  /// The technique step whose photo is being stored, so its card alone shows
  /// the in-flight state; null for the hero upload (or when idle). While any
  /// upload is in flight [uploadingImage] disables every photo control.
  final int? uploadingStepKey;

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
    List<EditorSubsection>? subsections,
    List<EditorTechnique>? techniques,
    RecipeImages? images,
    String? heroImageUrl,
    String? sourceSlug,
    String? credit,
    String? baseHash,
    bool? dirty,
    bool? saving,
    bool? uploadingImage,
    int? uploadingStepKey,
    bool clearUploadingStepKey = false,
    String? saveError,
    bool clearSaveError = false,
    String? savedSlug,
    bool? deleted,
  }) => EditorState(
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
    subsections: subsections ?? this.subsections,
    techniques: techniques ?? this.techniques,
    images: images ?? this.images,
    heroImageUrl: heroImageUrl ?? this.heroImageUrl,
    sourceSlug: sourceSlug ?? this.sourceSlug,
    credit: credit ?? this.credit,
    baseHash: baseHash ?? this.baseHash,
    dirty: dirty ?? this.dirty,
    saving: saving ?? this.saving,
    uploadingImage: uploadingImage ?? this.uploadingImage,
    uploadingStepKey: clearUploadingStepKey
        ? null
        : (uploadingStepKey ?? this.uploadingStepKey),
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
    emit(
      EditorState(
        entries: [
          EditorLine(
            _key,
            raw: '',
            amounts: const [],
            confidence: ParseConfidence.none,
          ),
        ],
        steps: [EditorStep(_key)],
      ),
    );
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

  /// Flattens stored ingredient [groups] into the editor's interleaved entry
  /// list (a group header row, then its lines). Shared by the top-level
  /// ingredient list and each subsection's.
  List<EditorEntry> _entriesFromGroups(List<IngredientGroup> groups) => [
    for (final group in groups) ...[
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
          // Curated structured data (differing from what the parser would
          // produce) is locked against automatic re-parsing.
          manuallyEdited: !_parserExplains(line),
        ),
    ],
  ];

  List<EditorStep> _stepsFrom(List<RecipeStep> steps) => [
    for (final step in steps)
      EditorStep(_key, label: step.label ?? '', text: step.text),
  ];

  EditorSubsection _subsectionFrom(Subsection sub) => EditorSubsection(
    _key,
    title: sub.title ?? '',
    kind: sub.kind ?? 'variation',
    kindNeedsReview: sub.kindNeedsReview,
    body: sub.body ?? '',
    servings: sub.servings ?? '',
    prepNotes: sub.prepNotes ?? '',
    hasIngredients: sub.ingredients != null,
    entries: _entriesFromGroups(sub.ingredients ?? const []),
    hasSteps: sub.steps != null,
    steps: _stepsFrom(sub.steps ?? const []),
    // Collapse on load so a recipe with several full sub-recipes isn't a wall.
    expanded: false,
  );

  EditorTechnique _techniqueFrom(Technique tech) => EditorTechnique(
    _key,
    heading: tech.heading ?? '',
    description: tech.description ?? '',
    steps: [
      for (final step in tech.steps)
        EditorTechniqueStep(_key, image: step.image, caption: step.caption),
    ],
    expanded: false,
  );

  /// Loads an existing recipe into the editor.
  Future<void> load(String idOrSlug) async {
    emit(const EditorState(loading: true));
    try {
      final detail = await _repository.getRecipe(idOrSlug);
      if (isClosed) {
        return;
      }
      final recipe = detail.recipe;
      emit(
        EditorState(
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
          entries: _entriesFromGroups(recipe.ingredients),
          steps: _stepsFrom(recipe.steps),
          subsections: [
            for (final sub in recipe.subsections) _subsectionFrom(sub),
          ],
          techniques: [
            for (final tech in recipe.techniques) _techniqueFrom(tech),
          ],
          images: recipe.images,
          heroImageUrl: detail.heroImageUrl,
          sourceSlug: detail.sourceSlug,
          credit: recipe.images.credit ?? '',
          baseHash: detail.baseHash,
        ),
      );
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

  void removeTag(String tag) =>
      emit(state.copyWith(tags: [...state.tags]..remove(tag), dirty: true));

  // ------------------------------------------------------------------
  // Shared entry-list building blocks (used by the top-level ingredient list
  // AND each subsection's, so the parse/lock rules can never drift between
  // them). The transforms are pure `EditorEntry -> EditorEntry`; the list ops
  // are pure `List -> List`.
  // ------------------------------------------------------------------

  EditorLine _emptyLine() => EditorLine(
    _key,
    raw: '',
    amounts: const [],
    confidence: ParseConfidence.none,
  );

  /// Parses paste-dialog lines into entries (a `Header:` line becomes a group).
  List<EditorEntry> _pastedEntries(List<String> lines) {
    final additions = <EditorEntry>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.endsWith(':')) {
        additions.add(
          EditorGroupHeader(
            _key,
            line.substring(0, line.length - 1).trim().toUpperCase(),
          ),
        );
      } else {
        additions.add(EditorLine.parsed(_key, line));
      }
    }
    return additions;
  }

  static List<EditorEntry> _replaceEntry(
    List<EditorEntry> entries,
    int key,
    EditorEntry Function(EditorEntry) transform,
  ) => [
    for (final entry in entries)
      if (entry.key == key) transform(entry) else entry,
  ];

  static List<T> _reordered<T>(List<T> list, int oldIndex, int newIndex) {
    final copy = [...list];
    copy.insert(newIndex, copy.removeAt(oldIndex));
    return copy;
  }

  static EditorEntry _rename(EditorEntry e, String name) =>
      e is EditorGroupHeader ? e.withName(name) : e;
  static EditorEntry _setRaw(EditorEntry e, String raw) =>
      e is EditorLine ? e.copyWith(raw: raw) : e;
  static EditorEntry _toggleExpanded(EditorEntry e) =>
      e is EditorLine ? e.copyWith(expanded: !e.expanded) : e;

  static EditorEntry _autoParse(EditorEntry e) {
    if (e is! EditorLine || e.manuallyEdited) {
      return e;
    }
    final parsed = parseIngredientLine(e.raw);
    return e.copyWith(
      amounts: parsed.amounts,
      item: parsed.item,
      clearItem: parsed.item == null,
      prep: parsed.prep,
      clearPrep: parsed.prep == null,
      confidence: parsed.confidence,
    );
  }

  static EditorEntry _reparse(EditorEntry e) {
    if (e is! EditorLine) {
      return e;
    }
    final parsed = parseIngredientLine(e.raw);
    return e.copyWith(
      amounts: parsed.amounts,
      item: parsed.item,
      clearItem: parsed.item == null,
      prep: parsed.prep,
      clearPrep: parsed.prep == null,
      confidence: parsed.confidence,
      manuallyEdited: false,
    );
  }

  static EditorEntry _setStructured(
    EditorEntry e, {
    List<Amount>? amounts,
    String? item,
    bool clearItem = false,
    String? prep,
    bool clearPrep = false,
  }) {
    if (e is! EditorLine) {
      return e;
    }
    return e.copyWith(
      amounts: amounts,
      item: item,
      clearItem: clearItem,
      prep: prep,
      clearPrep: clearPrep,
      manuallyEdited: true,
    );
  }

  // ------------------------------------------------------------------
  // Ingredient entries (top-level list).
  // ------------------------------------------------------------------

  void addLine() => emit(
    state.copyWith(entries: [...state.entries, _emptyLine()], dirty: true),
  );

  void addGroupHeader() => emit(
    state.copyWith(
      entries: [...state.entries, EditorGroupHeader(_key, '')],
      dirty: true,
    ),
  );

  /// Appends parsed lines (and `Header:` group rows) from the paste dialog.
  void addPastedLines(List<String> lines) {
    final additions = _pastedEntries(lines);
    if (additions.isEmpty) {
      return;
    }
    emit(
      state.copyWith(entries: [...state.entries, ...additions], dirty: true),
    );
  }

  void removeEntry(int key) => emit(
    state.copyWith(
      entries: [
        for (final entry in state.entries)
          if (entry.key != key) entry,
      ],
      dirty: true,
    ),
  );

  /// [newIndex] is already adjusted for the removal (onReorderItem).
  void reorderEntries(int oldIndex, int newIndex) => emit(
    state.copyWith(
      entries: _reordered(state.entries, oldIndex, newIndex),
      dirty: true,
    ),
  );

  void renameGroup(int key, String name) =>
      _updateEntry(key, (entry) => _rename(entry, name));

  /// The raw text changed. Committed to state IMMEDIATELY (a save or a
  /// leave-check must never miss in-flight typing); the structured-field
  /// parse follows separately via the debounced [applyAutoParse].
  void setLineRaw(int key, String raw) =>
      _updateEntry(key, (entry) => _setRaw(entry, raw));

  /// Applies the parser to the line's CURRENT raw text — called on the
  /// widget's debounce. Hand-edited (locked) lines are left alone; the
  /// explicit re-parse button is their only path.
  void applyAutoParse(int key) =>
      _updateEntry(key, _autoParse, markDirty: false);

  void toggleLineExpanded(int key) =>
      _updateEntry(key, _toggleExpanded, markDirty: false);

  /// Structured-field edits lock the line against automatic re-parsing.
  void setLineStructured(
    int key, {
    List<Amount>? amounts,
    String? item,
    bool clearItem = false,
    String? prep,
    bool clearPrep = false,
  }) => _updateEntry(
    key,
    (entry) => _setStructured(
      entry,
      amounts: amounts,
      item: item,
      clearItem: clearItem,
      prep: prep,
      clearPrep: clearPrep,
    ),
  );

  /// The explicit re-parse: applies the parser output and clears the lock.
  void reparseLine(int key) => _updateEntry(key, _reparse);

  void _updateEntry(
    int key,
    EditorEntry Function(EditorEntry) transform, {
    bool markDirty = true,
  }) {
    emit(
      state.copyWith(
        entries: _replaceEntry(state.entries, key, transform),
        dirty: markDirty ? true : null,
      ),
    );
  }

  // ------------------------------------------------------------------
  // Steps.
  // ------------------------------------------------------------------

  void addStep() => emit(
    state.copyWith(steps: [...state.steps, EditorStep(_key)], dirty: true),
  );

  void removeStep(int key) => emit(
    state.copyWith(
      steps: [
        for (final step in state.steps)
          if (step.key != key) step,
      ],
      dirty: true,
    ),
  );

  /// [newIndex] is already adjusted for the removal (onReorderItem).
  void reorderSteps(int oldIndex, int newIndex) => emit(
    state.copyWith(
      steps: _reordered(state.steps, oldIndex, newIndex),
      dirty: true,
    ),
  );

  void setStep(int key, {String? label, String? text}) => emit(
    state.copyWith(
      steps: [
        for (final step in state.steps)
          if (step.key == key)
            step.copyWith(label: label, text: text)
          else
            step,
      ],
      dirty: true,
    ),
  );

  // ------------------------------------------------------------------
  // Subsections (variations / components). Each carries its own ingredient
  // entry list and step list; nested edits route through the SAME shared
  // transforms as the top-level lists, scoped to one subsection by key.
  // ------------------------------------------------------------------

  void addSubsection(String kind) => emit(
    state.copyWith(
      subsections: [
        ...state.subsections,
        EditorSubsection(_key, kind: kind),
      ],
      dirty: true,
    ),
  );

  void removeSubsection(int key) => emit(
    state.copyWith(
      subsections: [
        for (final sub in state.subsections)
          if (sub.key != key) sub,
      ],
      dirty: true,
    ),
  );

  void reorderSubsections(int oldIndex, int newIndex) => emit(
    state.copyWith(
      subsections: _reordered(state.subsections, oldIndex, newIndex),
      dirty: true,
    ),
  );

  void toggleSubsectionExpanded(int key) => _mutateSub(
    key,
    (s) => s.copyWith(expanded: !s.expanded),
    markDirty: false,
  );

  void setSubsectionTitle(int key, String value) =>
      _mutateSub(key, (s) => s.copyWith(title: value));
  // Picking a kind clears the auto-guess review flag — a human has classified it.
  void setSubsectionKind(int key, String kind) =>
      _mutateSub(key, (s) => s.copyWith(kind: kind, kindNeedsReview: false));
  void setSubsectionBody(int key, String value) =>
      _mutateSub(key, (s) => s.copyWith(body: value));
  void setSubsectionServings(int key, String value) =>
      _mutateSub(key, (s) => s.copyWith(servings: value));
  void setSubsectionPrepNotes(int key, String value) =>
      _mutateSub(key, (s) => s.copyWith(prepNotes: value));

  /// Promotes a prose-only variation into a full sub-recipe: turns the
  /// ingredient list "present" (null -> []) and seeds one empty line.
  void promoteSubsectionIngredients(int key) => _mutateSub(
    key,
    (s) => s.hasIngredients
        ? s
        : s.copyWith(hasIngredients: true, entries: [_emptyLine()]),
  );

  void promoteSubsectionSteps(int key) => _mutateSub(
    key,
    (s) =>
        s.hasSteps ? s : s.copyWith(hasSteps: true, steps: [EditorStep(_key)]),
  );

  // --- a subsection's ingredient entries ---

  void subAddLine(int subKey) => _mutateSub(
    subKey,
    (s) =>
        s.copyWith(hasIngredients: true, entries: [...s.entries, _emptyLine()]),
  );

  void subAddGroupHeader(int subKey) => _mutateSub(
    subKey,
    (s) => s.copyWith(
      hasIngredients: true,
      entries: [...s.entries, EditorGroupHeader(_key, '')],
    ),
  );

  void subAddPastedLines(int subKey, List<String> lines) {
    final additions = _pastedEntries(lines);
    if (additions.isEmpty) {
      return;
    }
    _mutateSub(
      subKey,
      (s) => s.copyWith(
        hasIngredients: true,
        entries: [...s.entries, ...additions],
      ),
    );
  }

  void subRemoveEntry(int subKey, int key) => _mutateSub(
    subKey,
    (s) => s.copyWith(
      entries: [
        for (final entry in s.entries)
          if (entry.key != key) entry,
      ],
    ),
  );

  void subReorderEntries(int subKey, int oldIndex, int newIndex) => _mutateSub(
    subKey,
    (s) => s.copyWith(entries: _reordered(s.entries, oldIndex, newIndex)),
  );

  void subRenameGroup(int subKey, int key, String name) =>
      _mutateSubEntry(subKey, key, (e) => _rename(e, name));
  void subSetLineRaw(int subKey, int key, String raw) =>
      _mutateSubEntry(subKey, key, (e) => _setRaw(e, raw));
  void subApplyAutoParse(int subKey, int key) =>
      _mutateSubEntry(subKey, key, _autoParse, markDirty: false);
  void subToggleLineExpanded(int subKey, int key) =>
      _mutateSubEntry(subKey, key, _toggleExpanded, markDirty: false);
  void subReparseLine(int subKey, int key) =>
      _mutateSubEntry(subKey, key, _reparse);
  void subSetLineStructured(
    int subKey,
    int key, {
    List<Amount>? amounts,
    String? item,
    bool clearItem = false,
    String? prep,
    bool clearPrep = false,
  }) => _mutateSubEntry(
    subKey,
    key,
    (e) => _setStructured(
      e,
      amounts: amounts,
      item: item,
      clearItem: clearItem,
      prep: prep,
      clearPrep: clearPrep,
    ),
  );

  // --- a subsection's steps ---

  void subAddStep(int subKey) => _mutateSub(
    subKey,
    (s) => s.copyWith(hasSteps: true, steps: [...s.steps, EditorStep(_key)]),
  );

  void subRemoveStep(int subKey, int key) => _mutateSub(
    subKey,
    (s) => s.copyWith(
      steps: [
        for (final step in s.steps)
          if (step.key != key) step,
      ],
    ),
  );

  void subReorderSteps(int subKey, int oldIndex, int newIndex) => _mutateSub(
    subKey,
    (s) => s.copyWith(steps: _reordered(s.steps, oldIndex, newIndex)),
  );

  void subSetStep(int subKey, int key, {String? label, String? text}) =>
      _mutateSub(
        subKey,
        (s) => s.copyWith(
          steps: [
            for (final step in s.steps)
              if (step.key == key)
                step.copyWith(label: label, text: text)
              else
                step,
          ],
        ),
      );

  void _mutateSub(
    int subKey,
    EditorSubsection Function(EditorSubsection) transform, {
    bool markDirty = true,
  }) {
    emit(
      state.copyWith(
        subsections: [
          for (final sub in state.subsections)
            if (sub.key == subKey) transform(sub) else sub,
        ],
        dirty: markDirty ? true : null,
      ),
    );
  }

  void _mutateSubEntry(
    int subKey,
    int key,
    EditorEntry Function(EditorEntry) transform, {
    bool markDirty = true,
  }) => _mutateSub(
    subKey,
    (s) => s.copyWith(entries: _replaceEntry(s.entries, key, transform)),
    markDirty: markDirty,
  );

  // ------------------------------------------------------------------
  // Techniques (illustrated sidebars).
  // ------------------------------------------------------------------

  void addTechnique() => emit(
    state.copyWith(
      techniques: [...state.techniques, EditorTechnique(_key)],
      dirty: true,
    ),
  );

  void removeTechnique(int key) => emit(
    state.copyWith(
      techniques: [
        for (final tech in state.techniques)
          if (tech.key != key) tech,
      ],
      dirty: true,
    ),
  );

  void reorderTechniques(int oldIndex, int newIndex) => emit(
    state.copyWith(
      techniques: _reordered(state.techniques, oldIndex, newIndex),
      dirty: true,
    ),
  );

  void toggleTechniqueExpanded(int key) => _mutateTech(
    key,
    (t) => t.copyWith(expanded: !t.expanded),
    markDirty: false,
  );

  void setTechniqueHeading(int key, String value) =>
      _mutateTech(key, (t) => t.copyWith(heading: value));
  void setTechniqueDescription(int key, String value) =>
      _mutateTech(key, (t) => t.copyWith(description: value));

  void addTechniqueStep(int techKey) => _mutateTech(
    techKey,
    (t) => t.copyWith(steps: [...t.steps, EditorTechniqueStep(_key)]),
  );

  void removeTechniqueStep(int techKey, int stepKey) => _mutateTech(
    techKey,
    (t) => t.copyWith(
      steps: [
        for (final step in t.steps)
          if (step.key != stepKey) step,
      ],
    ),
  );

  void reorderTechniqueSteps(int techKey, int oldIndex, int newIndex) =>
      _mutateTech(
        techKey,
        (t) => t.copyWith(steps: _reordered(t.steps, oldIndex, newIndex)),
      );

  void setTechniqueStepCaption(int techKey, int stepKey, String value) =>
      _mutateTechStep(techKey, stepKey, (s) => s.copyWith(caption: value));

  void clearTechniqueStepImage(int techKey, int stepKey) =>
      _mutateTechStep(techKey, stepKey, (s) => s.copyWith(clearImage: true));

  /// Uploads [bytes] as a technique step's photo (stored, not attached) and
  /// drops the returned reference into the step. No-op on a not-yet-saved
  /// recipe — the store endpoint needs a recipe id, like the hero photo.
  Future<void> uploadTechniqueStepImage(
    int techKey,
    int stepKey,
    Uint8List bytes,
  ) => _storeTechniqueStepImage(
    techKey,
    stepKey,
    (id) => _repository.storeImage(id, bytes),
  );

  Future<void> techniqueStepImageFromUrl(
    int techKey,
    int stepKey,
    String url,
  ) => _storeTechniqueStepImage(
    techKey,
    stepKey,
    (id) => _repository.storeImageFromUrl(id, url),
  );

  Future<void> _storeTechniqueStepImage(
    int techKey,
    int stepKey,
    Future<String> Function(String recipeId) store,
  ) async {
    final id = state.recipeId;
    if (id == null || state.uploadingImage) {
      return;
    }
    emit(
      state.copyWith(
        uploadingImage: true,
        uploadingStepKey: stepKey,
        clearSaveError: true,
      ),
    );
    try {
      final reference = await store(id);
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          uploadingImage: false,
          clearUploadingStepKey: true,
          dirty: true,
          techniques: _replaceTechStep(
            state.techniques,
            techKey,
            stepKey,
            (s) => s.copyWith(image: reference),
          ),
        ),
      );
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          uploadingImage: false,
          clearUploadingStepKey: true,
          saveError: exception.message,
        ),
      );
    }
  }

  void _mutateTech(
    int key,
    EditorTechnique Function(EditorTechnique) transform, {
    bool markDirty = true,
  }) {
    emit(
      state.copyWith(
        techniques: [
          for (final tech in state.techniques)
            if (tech.key == key) transform(tech) else tech,
        ],
        dirty: markDirty ? true : null,
      ),
    );
  }

  void _mutateTechStep(
    int techKey,
    int stepKey,
    EditorTechniqueStep Function(EditorTechniqueStep) transform, {
    bool markDirty = true,
  }) => _mutateTech(
    techKey,
    (t) => t.copyWith(steps: _replaceTechStepIn(t.steps, stepKey, transform)),
    markDirty: markDirty,
  );

  static List<EditorTechnique> _replaceTechStep(
    List<EditorTechnique> techniques,
    int techKey,
    int stepKey,
    EditorTechniqueStep Function(EditorTechniqueStep) transform,
  ) => [
    for (final tech in techniques)
      if (tech.key == techKey)
        tech.copyWith(steps: _replaceTechStepIn(tech.steps, stepKey, transform))
      else
        tech,
  ];

  static List<EditorTechniqueStep> _replaceTechStepIn(
    List<EditorTechniqueStep> steps,
    int stepKey,
    EditorTechniqueStep Function(EditorTechniqueStep) transform,
  ) => [
    for (final step in steps)
      if (step.key == stepKey) transform(step) else step,
  ];

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
      emit(
        state.copyWith(
          uploadingImage: false,
          images: detail.recipe.images,
          baseHash: detail.baseHash,
          heroImageUrl: detail.heroImageUrl,
        ),
      );
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(uploadingImage: false, saveError: exception.message));
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
      emit(
        state.copyWith(
          uploadingImage: false,
          images: detail.recipe.images,
          baseHash: detail.baseHash,
          heroImageUrl: detail.heroImageUrl,
        ),
      );
    } on RepositoryException catch (exception) {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(uploadingImage: false, saveError: exception.message));
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
          : await _repository.updateRecipe(
              state.recipeId!,
              fields,
              baseHash: state.baseHash,
            );
      if (isClosed) {
        return;
      }
      // A save can change the recipe-review tally (fixing a flagged issue,
      // or introducing one), so the nav badge's session memo must refetch —
      // this is the wiring invalidateReviewCount was written for (review S4).
      _repository.invalidateReviewCount();
      emit(
        state.copyWith(
          saving: false,
          dirty: false,
          recipeId: detail.recipe.id,
          slug: detail.recipe.slug,
          savedSlug: detail.recipe.slug,
          baseHash: detail.baseHash,
        ),
      );
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

  /// The editable-field map the server merges (see docs/API.md — an absent key
  /// stays untouched; a present key replaces wholesale, so a list must be the
  /// COMPLETE edited list). `times` stays absent (preserved) until its editor
  /// lands.
  Map<String, Object?> _fields() {
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
      'ingredients': _groupsFromEntries(state.entries),
      'steps': _stepsMap(state.steps),
      // Merge replaces the whole key, so emit every subsection (empty ones
      // dropped). Inside each map, hasIngredients/hasSteps decide whether the
      // ingredient/step key is present at all — that is the null-vs-empty
      // distinction the model draws (prose-only omits it).
      'subsections': [
        for (final sub in state.subsections)
          if (!_subsectionIsEmpty(sub)) _subsectionMap(sub),
      ],
      'techniques': [
        for (final tech in state.techniques)
          if (!_techniqueIsEmpty(tech)) _techniqueMap(tech),
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

  /// Re-groups an interleaved entry list into the API's `[{group, items}]`
  /// shape (blank lines and empty trailing groups dropped). Shared by the
  /// top-level ingredients and each subsection's.
  static List<Map<String, Object?>> _groupsFromEntries(
    List<EditorEntry> entries,
  ) {
    final groups = <Map<String, Object?>>[];
    String? currentGroup;
    var currentItems = <Map<String, Object?>>[];
    void flush() {
      if (currentItems.isNotEmpty) {
        groups.add({'group': currentGroup, 'items': currentItems});
      }
      currentItems = [];
    }

    for (final entry in entries) {
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
    return groups;
  }

  static List<Map<String, Object?>> _stepsMap(List<EditorStep> steps) => [
    for (final (i, step) in steps.indexed)
      if (step.text.trim().isNotEmpty)
        {
          'number': i + 1,
          'label': _nullable(step.label),
          'text': step.text.trim(),
        },
  ];

  static Map<String, Object?> _subsectionMap(EditorSubsection sub) => {
    if (sub.title.trim().isNotEmpty) 'title': sub.title.trim(),
    'kind': sub.kind,
    'kind_needs_review': sub.kindNeedsReview,
    if (sub.body.trim().isNotEmpty) 'body': sub.body.trim(),
    if (sub.servings.trim().isNotEmpty) 'servings': sub.servings.trim(),
    if (sub.prepNotes.trim().isNotEmpty) 'prep_notes': sub.prepNotes.trim(),
    if (sub.hasIngredients) 'ingredients': _groupsFromEntries(sub.entries),
    if (sub.hasSteps) 'steps': _stepsMap(sub.steps),
  };

  /// A subsection with no title, prose, or non-empty ingredients/steps is
  /// dropped on save rather than persisted as a junk empty block.
  static bool _subsectionIsEmpty(EditorSubsection sub) =>
      sub.title.trim().isEmpty &&
      sub.body.trim().isEmpty &&
      sub.servings.trim().isEmpty &&
      sub.prepNotes.trim().isEmpty &&
      _groupsFromEntries(sub.entries).isEmpty &&
      _stepsMap(sub.steps).isEmpty;

  static Map<String, Object?> _techniqueMap(EditorTechnique tech) => {
    if (tech.heading.trim().isNotEmpty) 'heading': tech.heading.trim(),
    if (tech.description.trim().isNotEmpty)
      'description': tech.description.trim(),
    'steps': [
      for (final (i, step) in tech.steps.indexed)
        // A step earns a slot once it has a caption or a photo.
        if (step.caption.trim().isNotEmpty || step.image != null)
          {
            'number': i + 1,
            if (step.image != null) 'image': step.image,
            'caption': step.caption.trim(),
          },
    ],
  };

  static bool _techniqueIsEmpty(EditorTechnique tech) =>
      tech.heading.trim().isEmpty &&
      tech.description.trim().isEmpty &&
      tech.steps.every(
        (step) => step.caption.trim().isEmpty && step.image == null,
      );

  static String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
