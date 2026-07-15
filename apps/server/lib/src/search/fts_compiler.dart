import 'package:salt_server/src/exceptions.dart';
import 'package:salt_shared/salt_shared.dart';

/// A search AST compiled for execution against SQLite.
class CompiledSearch {
  /// Creates a compiled search from its [ftsMatch] and [calories] parts.
  const CompiledSearch({
    this.ftsMatch,
    this.calories = const [],
  });

  /// The FTS5 `MATCH` expression covering every text term, or null when the
  /// query holds no text terms (pure calories filter).
  final String? ftsMatch;

  /// Calories constraints, ANDed with the text match. Non-empty also means
  /// results are ordered by calories (ascending), preserving the old app's
  /// contract for calorie queries.
  final List<CaloriesNode> calories;

  /// Whether results should be ordered by calories per serving (ascending).
  bool get orderByCalories => calories.isNotEmpty;
}

/// Maps DSL scopes to `recipe_fts` columns; general terms search every
/// column (title, category, tags, ingredients, directions, notes,
/// background, prep_notes).
const Map<SearchScope, String?> _scopeColumns = {
  SearchScope.general: null,
  SearchScope.title: 'title',
  SearchScope.tag: 'tags',
  SearchScope.ingredient: 'ingredients',
  SearchScope.direction: 'directions',
  SearchScope.note: 'notes',
};

/// Compiles a parsed search [root] into a [CompiledSearch].
///
/// Text nodes become one FTS5 boolean expression — every term is emitted as
/// a quoted phrase (never raw user input), with a `{column}:` filter for
/// scoped terms. Calories nodes may only be combined with AND: they are a
/// numeric filter over a different table, so `x or calories:<300` has no
/// well-defined FTS meaning and is rejected as validation.
CompiledSearch compileSearch(SearchNode root) {
  final calories = <CaloriesNode>[];
  final match = _compileNode(root, calories, underOr: false);
  return CompiledSearch(ftsMatch: match, calories: calories);
}

String? _compileNode(
  SearchNode node,
  List<CaloriesNode> calories, {
  required bool underOr,
}) {
  switch (node) {
    case TermNode():
      return _term(node);
    case CaloriesNode():
      if (underOr) {
        throw const ValidationException(
          "A calories filter can't be combined with \"or\".",
        );
      }
      calories.add(node);
      return null;
    case AndNode(:final children):
      final parts = [
        for (final child in children)
          _compileNode(child, calories, underOr: underOr),
      ].whereType<String>().toList();
      return _join(parts, 'AND');
    case OrNode(:final children):
      final parts = [
        for (final child in children)
          _compileNode(child, calories, underOr: true),
      ].whereType<String>().toList();
      return _join(parts, 'OR');
  }
}

String? _join(List<String> parts, String op) {
  if (parts.isEmpty) {
    return null;
  }
  if (parts.length == 1) {
    return parts.first;
  }
  return '(${parts.join(' $op ')})';
}

/// One term as a column-filtered FTS5 phrase. Quoting the term as an FTS
/// string literal (with internal quotes doubled) means user input can never
/// inject MATCH syntax.
String _term(TermNode node) {
  final phrase = node.text.replaceAll('"', '""');
  final column = _scopeColumns[node.scope];
  return column == null ? '"$phrase"' : '$column:"$phrase"';
}
