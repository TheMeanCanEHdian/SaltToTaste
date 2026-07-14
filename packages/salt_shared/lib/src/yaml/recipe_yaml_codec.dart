import 'package:yaml/yaml.dart';

import '../model/recipe.dart';
import '../util/servings_parser.dart';
import 'yaml_emitter.dart';

/// The outcome of decoding a recipe YAML document: the [recipe] plus any
/// non-fatal [warnings] collected while normalizing and upgrading it.
class RecipeDecodeResult {
  const RecipeDecodeResult({required this.recipe, this.warnings = const []});

  final Recipe recipe;

  /// Human-readable notes (e.g. `unparseable servings: MAKES A MESS`);
  /// empty when the document decoded cleanly.
  final List<String> warnings;
}

/// Reads and writes canonical recipe YAML documents.
///
/// [decode] accepts both schema v1 (the Recipe Extraction corpus format) and
/// v2 documents, upgrading v1 on read: `schema_version` is stamped to 2 and
/// [Recipe.serves] is derived from the verbatim `servings` string via
/// [parseServings]. Hand-edited scalars are normalized defensively (a
/// `quantity`, `isbn`, or `extracted_at` that lost its quotes and parsed as
/// a number is coerced back to a string), and the v1 `quantity: null`
/// convention on unitless lines (`Pinch salt`) becomes the empty string.
///
/// [encode] always writes schema v2 in a canonical shape: fixed key order,
/// every key present (nulls and empty lists included) — EXCEPT inside
/// subsections, where `servings`/`prep_notes`/`ingredients`/`steps` are
/// omitted when null (the v1 prose-only convention: a null list means "key
/// absent", an empty list means "present but empty").
class RecipeYamlCodec {
  RecipeYamlCodec._();

  /// Parses [yamlText] into a [Recipe], upgrading v1 documents to v2.
  ///
  /// Throws [FormatException] when the root is not a mapping or the document
  /// does not fit the model (the message names the recipe id/title when
  /// available). A `schema_version` greater than 2 produces a warning but the
  /// decode is still attempted.
  static RecipeDecodeResult decode(String yamlText) {
    final Object? root = _toPlain(loadYaml(yamlText));
    if (root is! Map<String, Object?>) {
      throw const FormatException('Recipe YAML root must be a mapping.');
    }
    final warnings = <String>[];
    _normalizeScalars(root);
    _upgrade(root, warnings);
    try {
      return RecipeDecodeResult(
        recipe: RecipeMapper.fromMap(root),
        warnings: warnings,
      );
    } catch (error) {
      final id = root['id'];
      final title = root['title'];
      final label = [
        if (id != null) 'id: $id',
        if (title != null) 'title: $title',
      ].join(', ');
      throw FormatException(
        'Failed to decode recipe${label.isEmpty ? '' : ' ($label)'}: $error',
      );
    }
  }

  /// Serializes [recipe] as a canonical schema v2 YAML document.
  static String encode(Recipe recipe) => emitYamlDocument(_recipeNode(recipe));

  // --- decode helpers -------------------------------------------------------

  /// Deep-converts `YamlMap`/`YamlList` nodes into plain
  /// `Map<String, Object?>`/`List<Object?>` (map keys are stringified).
  static Object? _toPlain(Object? node) {
    if (node is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in node.entries)
          entry.key.toString(): _toPlain(entry.value),
      };
    }
    if (node is List) {
      return <Object?>[for (final Object? item in node) _toPlain(item)];
    }
    return node;
  }

  /// Coerces scalars that must be strings but may have lost their quotes in
  /// hand-edited files: `source.isbn`, `extraction.extracted_at`, and every
  /// `amounts[].quantity` (top-level and inside subsections).
  static void _normalizeScalars(Map<String, Object?> root) {
    final source = root['source'];
    if (source is Map<String, Object?>) _stringify(source, 'isbn');
    final extraction = root['extraction'];
    if (extraction is Map<String, Object?>) {
      _stringify(extraction, 'extracted_at');
    }
    _normalizeIngredients(root['ingredients']);
    final subsections = root['subsections'];
    if (subsections is List) {
      for (final Object? subsection in subsections) {
        if (subsection is Map<String, Object?>) {
          _normalizeIngredients(subsection['ingredients']);
        }
      }
    }
  }

  /// Coerces `quantity` to a string in every amount of an ingredient-group
  /// list shaped like `[{group, items: [{amounts: [{quantity, ...}]}]}]`.
  static void _normalizeIngredients(Object? groups) {
    if (groups is! List) return;
    for (final Object? group in groups) {
      if (group is! Map<String, Object?>) continue;
      final items = group['items'];
      if (items is! List) continue;
      for (final Object? item in items) {
        if (item is! Map<String, Object?>) continue;
        final amounts = item['amounts'];
        if (amounts is! List) continue;
        for (final Object? amount in amounts) {
          if (amount is! Map<String, Object?>) continue;
          final quantity = amount['quantity'];
          if (quantity == null) {
            // v1 convention for unitless "Pinch salt"/"Dash of hot sauce"
            // lines: `quantity: null`. The v2 model requires a string, so
            // null becomes the empty string (the raw line stays verbatim).
            amount['quantity'] = '';
          } else if (quantity is! String) {
            amount['quantity'] = quantity.toString();
          }
        }
      }
    }
  }

  /// Replaces a non-null, non-string value at [key] with its string form.
  static void _stringify(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value != null && value is! String) map[key] = value.toString();
  }

  /// Upgrades a v1 document (schema_version absent or 1) to v2: stamps
  /// `schema_version: 2` and derives `serves` from the verbatim `servings`
  /// string when absent. `times` needs no placeholder — a missing key decodes
  /// to the empty [RecipeTimes] via the constructor default. A version above
  /// 2 records a warning but decoding is still attempted.
  static void _upgrade(Map<String, Object?> root, List<String> warnings) {
    final version = root['schema_version'];
    if (version == null || version == 1) {
      root['schema_version'] = 2;
      if (root['serves'] == null) {
        final rawServings = root['servings'];
        final servingsText =
            rawServings is String ? rawServings : rawServings?.toString();
        final serves = parseServings(servingsText);
        if (serves != null) {
          root['serves'] = <String, Object?>{
            'min': serves.min,
            'max': serves.max,
          };
        } else if (servingsText != null) {
          warnings.add('unparseable servings: $servingsText');
        }
      }
    } else if (version is int && version > 2) {
      warnings.add(
        'unsupported schema_version: $version (this codec understands <= 2); '
        'attempting to decode anyway',
      );
    }
  }

  // --- encode helpers -------------------------------------------------------

  static Map<String, Object?> _recipeNode(Recipe recipe) {
    final serves = recipe.serves;
    return <String, Object?>{
      'schema_version': recipe.schemaVersion,
      'id': recipe.id,
      'title': recipe.title,
      'slug': recipe.slug,
      'source': _sourceNode(recipe.source),
      'servings': recipe.servings,
      'serves': serves == null
          ? null
          : <String, Object?>{'min': serves.min, 'max': serves.max},
      'category': recipe.category,
      'tags': List<Object?>.of(recipe.tags),
      'background': recipe.background,
      'prep_notes': recipe.prepNotes,
      'times': <String, Object?>{
        'prep': recipe.times.prep,
        'cook': recipe.times.cook,
        'total': recipe.times.total,
      },
      'ingredients': [
        for (final group in recipe.ingredients) _ingredientGroupNode(group),
      ],
      'steps': [for (final step in recipe.steps) _stepNode(step)],
      'subsections': [
        for (final subsection in recipe.subsections)
          _subsectionNode(subsection),
      ],
      'techniques': [
        for (final technique in recipe.techniques) _techniqueNode(technique),
      ],
      'images': <String, Object?>{
        'hero': recipe.images.hero,
        'gallery': List<Object?>.of(recipe.images.gallery),
        'credit': recipe.images.credit,
      },
      'notes': recipe.notes,
      'extraction': _extractionNode(recipe.extraction),
    };
  }

  static Map<String, Object?> _sourceNode(RecipeSource source) =>
      <String, Object?>{
        'name': source.name,
        'type': source.type,
        'publisher': source.publisher,
        'isbn': source.isbn,
        'source_file': source.sourceFile,
        'chapter': source.chapter,
        'section_id': source.sectionId,
        'page_start': source.pageStart,
        'page_end': source.pageEnd,
        'url': source.url,
      };

  static Map<String, Object?> _ingredientGroupNode(IngredientGroup group) =>
      <String, Object?>{
        'group': group.group,
        'items': [for (final item in group.items) _ingredientLineNode(item)],
      };

  static Map<String, Object?> _ingredientLineNode(IngredientLine line) =>
      <String, Object?>{
        'raw': line.raw,
        'amounts': [for (final amount in line.amounts) _amountNode(amount)],
        'item': line.item,
        'prep': line.prep,
      };

  static Map<String, Object?> _amountNode(Amount amount) => <String, Object?>{
        'measure': amount.measure.name,
        'quantity': amount.quantity,
        'unit': amount.unit,
        'approximate': amount.approximate,
        'primary': amount.primary,
      };

  static Map<String, Object?> _stepNode(RecipeStep step) => <String, Object?>{
        'number': step.number,
        'label': step.label,
        'text': step.text,
      };

  /// Subsections keep the v1 prose-only convention: the four sub-recipe keys
  /// are omitted entirely when null and emitted (even when empty) otherwise.
  static Map<String, Object?> _subsectionNode(Subsection subsection) {
    final servings = subsection.servings;
    final prepNotes = subsection.prepNotes;
    final ingredients = subsection.ingredients;
    final steps = subsection.steps;
    return <String, Object?>{
      'title': subsection.title,
      'kind': subsection.kind,
      'body': subsection.body,
      'kind_needs_review': subsection.kindNeedsReview,
      if (servings != null) 'servings': servings,
      if (prepNotes != null) 'prep_notes': prepNotes,
      if (ingredients != null)
        'ingredients': [
          for (final group in ingredients) _ingredientGroupNode(group),
        ],
      if (steps != null) 'steps': [for (final step in steps) _stepNode(step)],
    };
  }

  static Map<String, Object?> _techniqueNode(Technique technique) =>
      <String, Object?>{
        'heading': technique.heading,
        'description': technique.description,
        'steps': [
          for (final step in technique.steps) _techniqueStepNode(step),
        ],
      };

  static Map<String, Object?> _techniqueStepNode(TechniqueStep step) =>
      <String, Object?>{
        'number': step.number,
        'image': step.image,
        'caption': step.caption,
      };

  static Map<String, Object?>? _extractionNode(Extraction? extraction) {
    if (extraction == null) return null;
    return <String, Object?>{
      'extractor': extraction.extractor,
      'extractor_version': extraction.extractorVersion,
      'extracted_at': extraction.extractedAt,
      'warnings': List<Object?>.of(extraction.warnings),
    };
  }
}
