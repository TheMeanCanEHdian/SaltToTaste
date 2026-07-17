import 'package:dart_mappable/dart_mappable.dart' show MapperException;
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_server/src/services/slugify.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('edit');

/// Source directory (and sources-table slug) grouping recipes created in the
/// app, as opposed to imported ones which keep their import source.
const String manualSourceSlug = 'my-recipes';

/// Recipe-document keys a client submission may set.
///
/// Everything else (`id`, `slug`, `schema_version`, `extraction`) is
/// server-owned: preserved on update, generated on create. `source` is
/// special-cased — only its `name` and `url` are client-editable.
const Set<String> editableRecipeKeys = {
  'title',
  'servings',
  'category',
  'tags',
  'times',
  'background',
  'prep_notes',
  'ingredients',
  'steps',
  'subsections',
  'techniques',
  'images',
  'notes',
};

/// What a create/update returned: the stored recipe plus its source slug
/// (the detail-response shape is built from this) and whether anything
/// actually changed.
typedef EditResult = ({Recipe recipe, String sourceSlug, bool changed});

/// The `recipe` object of a create/update request body, or a 422.
Map<String, Object?> recipeObjectOf(Map<String, Object?> body) {
  final recipe = body['recipe'];
  if (recipe is! Map<String, Object?>) {
    throw const ValidationException(
      "Request body must carry a 'recipe' object.",
    );
  }
  return recipe;
}

/// Creates a recipe from a client [submission] (the `recipe` object of the
/// request body), stores it, and exports its canonical YAML.
///
/// Server-generated identity: id `manual-<yyyymmdd>-<slug>` (uniqued),
/// slug from the title (uniqued), source document `{name, type: manual,
/// url?}` grouped under the [manualSourceSlug] library directory.
EditResult createRecipe(
  SaltDatabase db,
  ServerConfig config,
  Map<String, Object?> submission,
) {
  final base = <String, Object?>{
    'schema_version': 2,
    'id': 'pending',
    'title': '',
    'slug': 'pending',
    'source': {'name': 'My Recipes', 'type': 'manual'},
  };
  final merged = _overlay(base, submission);
  var recipe = _recipeFromMap(merged);
  _validateRecipe(recipe);

  final desiredSlug = slugify(recipe.title);
  if (desiredSlug.isEmpty) {
    throw const ValidationException(
      'Title must contain at least one letter or digit.',
    );
  }
  final id = _availableId(db, desiredSlug);
  final slug = db.availableSlug(desiredSlug, ownerId: id);
  recipe = _normalized(recipe).copyWith(id: id, slug: slug);

  db.upsertSource(slug: manualSourceSlug, name: 'My Recipes', type: 'manual');
  _store(db, config, recipe, sourceSlug: manualSourceSlug, previousHash: null);
  _log.info('Created recipe ${recipe.id}');
  return (recipe: recipe, sourceSlug: manualSourceSlug, changed: true);
}

/// Applies a client [submission] to the recipe matching [key] (id or slug)
/// and re-exports its canonical YAML.
///
/// Merge semantics: editable keys *present* in the submission replace the
/// stored value (an explicit null clears an optional field); absent keys are
/// left untouched, so a script can update a single field safely. The slug is
/// deliberately stable across renames so shared links keep working.
EditResult updateRecipe(
  SaltDatabase db,
  ServerConfig config,
  String key,
  Map<String, Object?> submission,
) {
  final existing = db.recipeByIdOrSlug(key);
  if (existing == null) {
    throw NotFoundException('recipe not found: $key');
  }
  final previousHash = db.contentHashOf(existing.recipe.id);

  final merged = _overlay(existing.recipe.toMap(), submission);
  var recipe = _recipeFromMap(merged);
  _validateRecipe(recipe);
  recipe = _normalized(recipe).copyWith(
    id: existing.recipe.id,
    slug: existing.recipe.slug,
    schemaVersion: existing.recipe.schemaVersion,
    extraction: existing.recipe.extraction,
  );

  final canonical = RecipeYamlCodec.encode(recipe);
  if (contentHashOfText(canonical) == previousHash) {
    return (
      recipe: existing.recipe,
      sourceSlug: existing.sourceSlug,
      changed: false,
    );
  }
  _store(
    db,
    config,
    recipe,
    sourceSlug: existing.sourceSlug,
    previousHash: previousHash,
  );
  _log.info('Updated recipe ${recipe.id}');
  return (recipe: recipe, sourceSlug: existing.sourceSlug, changed: true);
}

/// Throws unless [role] names a place an image can attach. Routes call
/// this BEFORE saving the uploaded bytes, so an invalid role never leaves
/// an orphan file on disk.
void requireImageRole(String role) {
  if (role != 'hero' && role != 'gallery') {
    throw const ValidationException("'role' must be 'hero' or 'gallery'.");
  }
}

/// Attaches an already-stored library image (a `images/<file>` reference
/// from `saveRecipeImage`) to the recipe as its hero image or a gallery
/// entry, and re-exports the YAML like any other edit. The updated document
/// passes the same validation as a PUT — the gallery cap cannot be
/// bypassed upload-by-upload (which would leave the recipe uneditable).
EditResult attachRecipeImage(
  SaltDatabase db,
  ServerConfig config,
  String key, {
  required String reference,
  required String role,
}) {
  requireImageRole(role);
  final existing = db.recipeByIdOrSlug(key);
  if (existing == null) {
    throw NotFoundException('recipe not found: $key');
  }
  final images = role == 'hero'
      ? existing.recipe.images.copyWith(hero: reference)
      : existing.recipe.images.copyWith(
          gallery: [...existing.recipe.images.gallery, reference],
        );
  final previousHash = db.contentHashOf(existing.recipe.id);
  final recipe = existing.recipe.copyWith(images: images);
  _validateRecipe(recipe);
  _store(
    db,
    config,
    recipe,
    sourceSlug: existing.sourceSlug,
    previousHash: previousHash,
  );
  _log.info('Attached $role image to ${recipe.id}');
  return (recipe: recipe, sourceSlug: existing.sourceSlug, changed: true);
}

/// Deletes the recipe matching [key] (id or slug) and its library export.
///
/// [beforeDestructive] runs first (the caller passes the backup hook), so
/// the delete is always recoverable. Conflict copies and image files are
/// left in place — they may be shared or hand-managed.
void deleteRecipe(
  SaltDatabase db,
  ServerConfig config,
  String key, {
  void Function()? beforeDestructive,
}) {
  final existing = db.recipeByIdOrSlug(key);
  if (existing == null) {
    throw NotFoundException('recipe not found: $key');
  }
  beforeDestructive?.call();
  db.deleteRecipe(existing.recipe.id);
  deleteExport(config, existing.sourceSlug, existing.recipe.id);
  _log.info('Deleted recipe ${existing.recipe.id}');
}

/// Encodes, hashes, upserts, and exports [recipe] (whose slug is already
/// final). A hand-edited library file that would be overwritten is preserved
/// as a `.conflict-<timestamp>.yaml` copy by [exportRecipeYaml].
void _store(
  SaltDatabase db,
  ServerConfig config,
  Recipe recipe, {
  required String sourceSlug,
  required String? previousHash,
}) {
  final canonical = RecipeYamlCodec.encode(recipe);
  db.upsertRecipe(
    recipe,
    sourceSlug: sourceSlug,
    contentHash: contentHashOfText(canonical),
  );
  exportRecipeYaml(
    config: config,
    sourceSlug: sourceSlug,
    recipeId: recipe.id,
    canonical: canonical,
    previousHash: previousHash,
  );
}

/// `manual-<yyyymmdd>-<slug>`, suffixed `-2`, `-3`, ... until unused.
String _availableId(SaltDatabase db, String desiredSlug) {
  final now = DateTime.now().toUtc();
  final date =
      '${now.year}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  final base = 'manual-$date-$desiredSlug';
  var candidate = base;
  var suffix = 2;
  while (db.recipeExists(candidate)) {
    candidate = '$base-$suffix';
    suffix += 1;
  }
  return candidate;
}

/// Overlays the editable keys of [submission] onto [base]. `source` merges
/// only `name` and `url` into the stored source object.
Map<String, Object?> _overlay(
  Map<String, Object?> base,
  Map<String, Object?> submission,
) {
  final merged = <String, Object?>{...base};
  for (final key in editableRecipeKeys) {
    if (submission.containsKey(key)) {
      merged[key] = submission[key];
    }
  }
  final source = submission['source'];
  if (source is Map<String, Object?>) {
    final baseSource = merged['source'];
    final mergedSource = <String, Object?>{
      if (baseSource is Map<String, Object?>) ...baseSource,
    };
    for (final key in const ['name', 'url']) {
      if (source.containsKey(key)) {
        mergedSource[key] = source[key];
      }
    }
    merged['source'] = mergedSource;
  }
  return merged;
}

/// Decodes the merged document map into a [Recipe], translating mapper
/// errors (wrong types, missing required fields) into 422s the client can
/// act on rather than 500s.
Recipe _recipeFromMap(Map<String, Object?> map) {
  try {
    return RecipeMapper.fromMap(map);
  } on MapperException catch (error) {
    throw ValidationException('Invalid recipe document: ${error.message}');
  }
}

/// Renumbers steps sequentially (top level, subsections, techniques) and
/// derives `serves` from the verbatim servings text, exactly like the YAML
/// decode path does, so a round-trip through the editor is a no-op.
Recipe _normalized(Recipe recipe) {
  final tags = <String>[];
  for (final tag in recipe.tags) {
    final normalized = tag.trim().toLowerCase();
    if (normalized.isNotEmpty && !tags.contains(normalized)) {
      tags.add(normalized);
    }
  }
  return recipe.copyWith(
    schemaVersion: 2,
    serves: parseServings(recipe.servings),
    tags: tags,
    steps: _renumbered(recipe.steps),
    subsections: [
      for (final subsection in recipe.subsections)
        subsection.steps == null
            ? subsection
            : subsection.copyWith(steps: _renumbered(subsection.steps!)),
    ],
    techniques: [
      for (final technique in recipe.techniques)
        technique.copyWith(
          steps: [
            for (final (i, step) in technique.steps.indexed)
              step.copyWith(number: i + 1),
          ],
        ),
    ],
  );
}

List<RecipeStep> _renumbered(List<RecipeStep> steps) => [
  for (final (i, step) in steps.indexed) step.copyWith(number: i + 1),
];

// ---------------------------------------------------------------------
// Validation. Caps are generous for real cookbook content but low enough
// that a malicious document cannot balloon the database or the YAML file.
// ---------------------------------------------------------------------

const int _maxTextField = 50000;

void _validateRecipe(Recipe recipe) {
  _requireLength('title', recipe.title, min: 1, max: 250);
  _checkLength('servings', recipe.servings, 200);
  _checkLength('category', recipe.category, 120);
  _checkLength('background', recipe.background, _maxTextField);
  _checkLength('prep_notes', recipe.prepNotes, _maxTextField);
  _checkLength('notes', recipe.notes, _maxTextField);

  if (recipe.tags.length > 50) {
    throw const ValidationException('At most 50 tags.');
  }
  for (final tag in recipe.tags) {
    final normalized = tag.trim();
    if (normalized.isEmpty || normalized.length > 60) {
      throw const ValidationException('Tags must be 1-60 characters.');
    }
  }

  if (recipe.ingredients.length > 60) {
    throw const ValidationException('At most 60 ingredient groups.');
  }
  var lines = 0;
  for (final group in recipe.ingredients) {
    _checkLength('ingredient group', group.group, 200);
    for (final line in group.items) {
      lines += 1;
      _requireLength('ingredient raw', line.raw, min: 1, max: 1000);
      _checkLength('ingredient item', line.item, 500);
      _checkLength('ingredient prep', line.prep, 500);
      if (line.amounts.length > 8) {
        throw const ValidationException(
          'At most 8 amounts per ingredient line.',
        );
      }
      for (final amount in line.amounts) {
        _requireLength('amount quantity', amount.quantity, min: 0, max: 40);
        _checkLength('amount unit', amount.unit, 40);
      }
    }
  }
  if (lines > 400) {
    throw const ValidationException('At most 400 ingredient lines.');
  }

  for (final (field, minutes) in [
    ('times.prep', recipe.times.prep),
    ('times.cook', recipe.times.cook),
    ('times.total', recipe.times.total),
  ]) {
    if (minutes != null && (minutes < 0 || minutes > 100000)) {
      throw ValidationException("'$field' must be 0-100000 minutes.");
    }
  }

  if (recipe.steps.length > 120) {
    throw const ValidationException('At most 120 steps.');
  }
  for (final step in recipe.steps) {
    _requireLength('step text', step.text, min: 1, max: 10000);
    _checkLength('step label', step.label, 200);
  }
  if (recipe.subsections.length > 60) {
    throw const ValidationException('At most 60 subsections.');
  }
  if (recipe.techniques.length > 60) {
    throw const ValidationException('At most 60 techniques.');
  }

  _checkImagePath('images.hero', recipe.images.hero);
  if (recipe.images.gallery.length > 40) {
    throw const ValidationException('At most 40 gallery images.');
  }
  for (final image in recipe.images.gallery) {
    _checkImagePath('images.gallery', image);
  }
  _checkLength('images.credit', recipe.images.credit, 500);
  for (final technique in recipe.techniques) {
    for (final step in technique.steps) {
      _checkImagePath('technique image', step.image);
    }
  }
}

void _requireLength(
  String field,
  String value, {
  required int min,
  required int max,
}) {
  if (value.length < min || value.length > max) {
    throw ValidationException(
      min > 0
          ? "'$field' must be $min-$max characters."
          : "'$field' must be at most $max characters.",
    );
  }
}

void _checkLength(String field, String? value, int max) {
  if (value != null && value.length > max) {
    throw ValidationException("'$field' must be at most $max characters.");
  }
}

/// Image references are doc-relative (`images/<file>`); anything that could
/// address outside the recipe's library directory is rejected.
void _checkImagePath(String field, String? path) {
  if (path == null) {
    return;
  }
  if (path.isEmpty ||
      path.length > 300 ||
      path.startsWith('/') ||
      path.contains(r'\') ||
      path.split('/').contains('..')) {
    throw ValidationException("'$field' must be a document-relative path.");
  }
}
