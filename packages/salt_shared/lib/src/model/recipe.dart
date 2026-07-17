import 'package:dart_mappable/dart_mappable.dart';

part 'recipe.mapper.dart';

/// How an [Amount] measures its ingredient.
@MappableEnum()
enum Measure { volume, weight, count }

/// A single parsed quantity for an ingredient line.
///
/// An ingredient line can carry 0, 1, or 2 amounts (dual lines like
/// `1¾ cups (8¾ ounces) flour` have one volume and one weight amount, with
/// exactly one flagged [primary]).
@MappableClass(caseStyle: CaseStyle.snakeCase)
class Amount with AmountMappable {
  const Amount({
    required this.measure,
    required this.quantity,
    this.unit,
    this.approximate = false,
    this.primary = false,
  });

  final Measure measure;

  /// Kept as the source string (`'2'`, `1/2`, `4 1/4`); use the quantity
  /// utils to get a numeric value.
  final String quantity;
  final String? unit;
  final bool approximate;
  final bool primary;
}

/// One ingredient line: the verbatim publisher text plus parsed structure.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class IngredientLine with IngredientLineMappable {
  const IngredientLine({
    required this.raw,
    this.amounts = const [],
    this.item,
    this.prep,
  });

  /// Verbatim source line — always preserved, never regenerated.
  final String raw;
  final List<Amount> amounts;

  /// The ingredient name (text before the first top-level comma).
  final String? item;

  /// Prep instructions (text after the first top-level comma).
  final String? prep;
}

/// A run of ingredient lines under an optional group heading (e.g. `STOCK`).
@MappableClass(caseStyle: CaseStyle.snakeCase)
class IngredientGroup with IngredientGroupMappable {
  const IngredientGroup({this.group, this.items = const []});

  final String? group;
  final List<IngredientLine> items;
}

/// A numbered direction step, optionally with a phase label
/// (e.g. `FOR THE STOCK`).
@MappableClass(caseStyle: CaseStyle.snakeCase)
class RecipeStep with RecipeStepMappable {
  const RecipeStep({required this.number, this.label, required this.text});

  final int number;
  final String? label;
  final String text;
}

/// A variation or component nested under a recipe.
///
/// Prose-only variations carry just [title]/[kind]/[body]; full sub-recipes
/// additionally carry [servings]/[prepNotes]/[ingredients]/[steps]. For those
/// four fields `null` means "not present in the document" (prose-only), while
/// an empty list means "present but empty" — the YAML codec preserves the
/// distinction by omitting null keys.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class Subsection with SubsectionMappable {
  const Subsection({
    this.title,
    this.kind,
    this.body,
    this.kindNeedsReview = false,
    this.servings,
    this.prepNotes,
    this.ingredients,
    this.steps,
  });

  final String? title;

  /// `variation` | `component` | `unknown`.
  final String? kind;
  final String? body;
  final bool kindNeedsReview;
  final String? servings;
  final String? prepNotes;
  final List<IngredientGroup>? ingredients;
  final List<RecipeStep>? steps;
}

/// One illustrated step in a technique sidebar.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class TechniqueStep with TechniqueStepMappable {
  const TechniqueStep({
    required this.number,
    this.image,
    required this.caption,
  });

  final int number;

  /// Relative image path (e.g. `images/0020-slug-technique-01-01.jpg`).
  final String? image;
  final String caption;
}

/// An illustrated technique sidebar attached to a recipe.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class Technique with TechniqueMappable {
  const Technique({this.heading, this.description, this.steps = const []});

  final String? heading;
  final String? description;
  final List<TechniqueStep> steps;
}

/// Provenance of the recipe document.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class RecipeSource with RecipeSourceMappable {
  const RecipeSource({
    required this.name,
    required this.type,
    this.publisher,
    this.isbn,
    this.sourceFile,
    this.chapter,
    this.sectionId,
    this.pageStart,
    this.pageEnd,
    this.url,
  });

  final String name;

  /// `epub` | `website` | `page_image` | `manual`.
  final String type;
  final String? publisher;
  final String? isbn;
  final String? sourceFile;
  final String? chapter;
  final String? sectionId;
  final int? pageStart;
  final int? pageEnd;

  /// v2: source URL for website recipes.
  final String? url;
}

/// v2: numeric yield parsed from the verbatim servings string.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class Serves with ServesMappable {
  const Serves({required this.min, required this.max});

  final int min;
  final int max;
}

/// v2: recipe times in minutes.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class RecipeTimes with RecipeTimesMappable {
  const RecipeTimes({this.prep, this.cook, this.total});

  final int? prep;
  final int? cook;
  final int? total;

  bool get isEmpty => prep == null && cook == null && total == null;
}

/// Image references, relative to the recipe's source root.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class RecipeImages with RecipeImagesMappable {
  const RecipeImages({this.hero, this.gallery = const [], this.credit});

  final String? hero;

  /// v2: additional image paths.
  final List<String> gallery;

  /// v2: URL the hero image came from (old app's `imagecredit`).
  final String? credit;
}

/// Metadata recorded by the extractor that produced the document.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class Extraction with ExtractionMappable {
  const Extraction({
    this.extractor,
    this.extractorVersion,
    this.extractedAt,
    this.warnings = const [],
  });

  final String? extractor;
  final String? extractorVersion;

  /// `YYYY-MM-DD` date string.
  final String? extractedAt;
  final List<String> warnings;
}

/// The canonical recipe document (schema v2 — a strict superset of the
/// Recipe Extraction v1 format).
///
/// The YAML codec upgrades v1 documents on read (deriving [serves] from the
/// verbatim [servings] string); exports always write v2.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class Recipe with RecipeMappable {
  const Recipe({
    this.schemaVersion = 2,
    required this.id,
    required this.title,
    required this.slug,
    required this.source,
    this.servings,
    this.serves,
    this.times = const RecipeTimes(),
    this.category,
    this.tags = const [],
    this.background,
    this.prepNotes,
    this.ingredients = const [],
    this.steps = const [],
    this.subsections = const [],
    this.techniques = const [],
    this.images = const RecipeImages(),
    this.notes,
    this.extraction,
  });

  final int schemaVersion;

  /// Globally unique, stable id (e.g. `atk-tv-2023-0857-rich-chocolate-bundt-cake`).
  final String id;
  final String title;
  final String slug;
  final RecipeSource source;

  /// Verbatim yield string (`SERVES 6 TO 8`) — always preserved and displayed.
  final String? servings;

  /// v2: numeric yield parsed from [servings]; null when unparseable.
  final Serves? serves;

  /// v2: prep/cook/total minutes.
  final RecipeTimes times;
  final String? category;

  /// Lowercase tag names.
  final List<String> tags;

  /// "Why this recipe works" prose.
  final String? background;

  /// Headnote under the title.
  final String? prepNotes;
  final List<IngredientGroup> ingredients;
  final List<RecipeStep> steps;
  final List<Subsection> subsections;
  final List<Technique> techniques;
  final RecipeImages images;

  /// Shared recipe note (per-user notes live in the database, not here).
  final String? notes;
  final Extraction? extraction;
}
