import 'package:yaml/yaml.dart';

import '../model/recipe.dart';
import '../util/servings_parser.dart';
import '../util/yaml_plain.dart';
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
/// [parseServings]. Scalar-type coercion for hand-edited files (an `isbn` or
/// `quantity` that lost its quotes and parsed as a number) is handled by
/// dart_mappable itself, whose `String` decoder accepts any scalar via
/// `toString()` — a regression test pins that behavior. The one exception is
/// the v1 `quantity: null` convention on unitless lines (`Pinch salt`),
/// normalized here to the empty string because the model field is
/// non-nullable.
///
/// [encode] always writes schema v2 in a canonical shape derived from the
/// generated `Recipe.toMap()` — so every model field is emitted by
/// construction and a newly added field can never be silently dropped — with
/// a fixed top-level key order and every key present (nulls and empty lists
/// included), EXCEPT inside subsections, where
/// `servings`/`prep_notes`/`ingredients`/`steps` are omitted when null (the
/// v1 prose-only convention: a null list means "key absent", an empty list
/// means "present but empty").
class RecipeYamlCodec {
  RecipeYamlCodec._();

  /// Canonical top-level key order for encoded documents. Keys produced by
  /// `toMap()` that are not listed here (future fields) are appended after
  /// the known keys rather than dropped.
  static const List<String> _topKeyOrder = [
    'schema_version',
    'id',
    'title',
    'slug',
    'source',
    'servings',
    'serves',
    'category',
    'tags',
    'background',
    'prep_notes',
    'times',
    'ingredients',
    'steps',
    'subsections',
    'techniques',
    'images',
    'notes',
    'extraction',
  ];

  /// Subsection keys omitted when null (v1 prose-only convention).
  static const List<String> _subsectionOptionalKeys = [
    'servings',
    'prep_notes',
    'ingredients',
    'steps',
  ];

  /// Parses [yamlText] into a [Recipe], upgrading v1 documents to v2.
  ///
  /// Throws [FormatException] when the root is not a mapping or the document
  /// does not fit the model (the message names the recipe id/title when
  /// available). A `schema_version` greater than 2 produces a warning but the
  /// decode is still attempted; an unrecognizable `schema_version` produces a
  /// warning and is treated as v1.
  static RecipeDecodeResult decode(String yamlText) {
    final Object? root = yamlToPlain(loadYaml(yamlText));
    if (root is! Map<String, Object?>) {
      throw const FormatException('Recipe YAML root must be a mapping.');
    }
    final warnings = <String>[];
    _normalizeNullQuantities(root);
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
  static String encode(Recipe recipe) =>
      emitYamlDocument(_canonicalize(recipe.toMap()));

  // --- decode helpers -------------------------------------------------------

  /// Converts the v1 `quantity: null` convention on unitless lines
  /// (`Pinch salt`, `Dash of hot sauce`) to the empty string — the v2 model
  /// field is non-nullable. Applies to top-level and subsection ingredients.
  static void _normalizeNullQuantities(Map<String, Object?> root) {
    _nullQuantitiesToEmpty(root['ingredients']);
    final subsections = root['subsections'];
    if (subsections is List) {
      for (final Object? subsection in subsections) {
        if (subsection is Map<String, Object?>) {
          _nullQuantitiesToEmpty(subsection['ingredients']);
        }
      }
    }
  }

  static void _nullQuantitiesToEmpty(Object? groups) {
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
          if (amount.containsKey('quantity') && amount['quantity'] == null) {
            amount['quantity'] = '';
          }
        }
      }
    }
  }

  /// Upgrades a v1 document (schema_version absent, 1, or unrecognizable) to
  /// v2: stamps `schema_version: 2` and derives `serves` from the verbatim
  /// `servings` string when absent. Versions are read tolerantly (`1`, `'1'`,
  /// and `1.0` all count as 1 — hand-edited files lose quotes both ways). A
  /// version above 2 records a warning but decoding is still attempted.
  static void _upgrade(Map<String, Object?> root, List<String> warnings) {
    final Object? raw = root['schema_version'];
    final version = _versionOf(raw);
    if (raw != null && version == null) {
      warnings.add('unrecognizable schema_version: $raw; treating as v1');
    }
    if (version != null) {
      // Normalize '2'/2.0 spellings so the model always sees an int.
      root['schema_version'] = version;
    }
    if (version == null || version <= 1) {
      root['schema_version'] = 2;
      if (root['serves'] == null) {
        final servingsText = root['servings']?.toString();
        final serves = parseServings(servingsText);
        if (serves != null) {
          root['serves'] = serves.toMap();
        } else if (servingsText != null) {
          warnings.add('unparseable servings: $servingsText');
        }
      }
    } else if (version > 2) {
      warnings.add(
        'unsupported schema_version: $version (this codec understands <= 2); '
        'attempting to decode anyway',
      );
    }
  }

  /// Reads a schema version from an int, a whole double (`1.0`), or a numeric
  /// string (`'1'`); returns null for anything else.
  static int? _versionOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is double && raw == raw.roundToDouble()) return raw.round();
    if (raw is String) {
      final text = raw.trim();
      final asInt = int.tryParse(text);
      if (asInt != null) return asInt;
      final asDouble = double.tryParse(text);
      if (asDouble != null && asDouble == asDouble.roundToDouble()) {
        return asDouble.round();
      }
    }
    return null;
  }

  // --- encode helpers -------------------------------------------------------

  /// Applies the canonical document shape to a generated `toMap()` result:
  /// fixed top-level key order (unknown keys appended, never dropped) and
  /// the subsection null-key omission convention.
  static Map<String, Object?> _canonicalize(Map<String, dynamic> map) {
    final subsections = map['subsections'];
    if (subsections is List) {
      for (final Object? subsection in subsections) {
        if (subsection is Map) {
          for (final key in _subsectionOptionalKeys) {
            if (subsection.containsKey(key) && subsection[key] == null) {
              subsection.remove(key);
            }
          }
        }
      }
    }
    return <String, Object?>{
      for (final key in _topKeyOrder)
        if (map.containsKey(key)) key: map[key] as Object?,
      for (final entry in map.entries)
        if (!_topKeyOrder.contains(entry.key)) entry.key: entry.value as Object?,
    };
  }
}
