/// Turns a search-DSL query string into an ordered list of dismissible "chips"
/// (the recognized scoped clauses — `tag:dessert`, `title:pork`,
/// `calories:<400`) plus the trailing free text, and back again.
///
/// This is the one piece the search *field* needs that the DSL did not already
/// provide: the parser (`parseSearchQuery`) yields an AST but no way back to a
/// query string, and the node `toString()`s are debug reprs, not valid DSL. The
/// chip UI is display sugar over the existing grammar — it never extends it — so
/// everything here round-trips through `parseSearchQuery` / `quoteDslValue` and
/// serializes to exactly the plain string the URL, the API, and the results
/// pill already expect.
///
/// Chips are AND-only. The grammar has `or` (and no negation or grouping), but a
/// flat row of chips cannot express a grouped disjunction, so any query carrying
/// an `or` connective is kept whole as free text rather than silently changing
/// its meaning — see [queryHasOr].
library;

import 'dsl_parser.dart';
import 'dsl_spans.dart';

/// A recognized scoped clause, rendered as a chip in the search field.
///
/// [raw] is the canonical DSL text this chip serializes to (`tag:"main dish"`,
/// `calories:<400`); [value] is the human-facing value shown after the scope
/// label (`main dish`, `< 400`). [isTag] flags the `tag:` scope so the UI can
/// tint just those chips.
class SearchChip {
  const SearchChip({
    required this.scopeLabel,
    required this.value,
    required this.raw,
    required this.isTag,
  });

  /// The scope keyword shown as the chip's prefix (`tag`, `title`, `calories`).
  final String scopeLabel;

  /// The display value after the label (`dessert`, `main dish`, `< 400`).
  final String value;

  /// The canonical DSL fragment this chip serializes to.
  final String raw;

  /// Whether this is a `tag:` chip (the only scope the UI tints).
  final bool isTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchChip &&
          other.scopeLabel == scopeLabel &&
          other.value == value &&
          other.raw == raw &&
          other.isTag == isTag;

  @override
  int get hashCode => Object.hash(scopeLabel, value, raw, isTag);

  @override
  String toString() => 'SearchChip($raw)';
}

/// A query split into its leading chips and the trailing free text.
class ParsedSearchInput {
  const ParsedSearchInput(this.chips, this.text);

  /// The scoped clauses, in query order, lifted out as chips.
  final List<SearchChip> chips;

  /// Everything that is not a chip (bare words, quoted phrases), joined by a
  /// single space — what stays editable in the field's text tail.
  final String text;
}

/// Whether [query] contains a standalone `or` connective.
///
/// Only a bare `or` lexeme counts: `tag:or` is one lexeme (a term whose value is
/// "or"), and `"or"` is a quoted phrase — neither is the operator. A query with
/// an `or` is not chip-representable (chips are AND-only), so the field keeps it
/// as plain text.
bool queryHasOr(String query) => lexQuerySpans(query).any(
  (span) => !span.quoted && span.source.toLowerCase() == 'or',
);

/// Splits [query] into leading chips + trailing free text.
///
/// A query is chipped only when it is a pure conjunction of recognized clauses
/// and free terms. If it carries an `or`, or the parser reports any problem, the
/// whole (trimmed) query is returned as [ParsedSearchInput.text] with no chips —
/// safer to edit malformed or disjunctive input as raw text than to chip it.
ParsedSearchInput parseSearchInput(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const ParsedSearchInput([], '');
  }
  if (queryHasOr(trimmed)) {
    return ParsedSearchInput(const [], trimmed);
  }
  final result = parseSearchQuery(trimmed);
  final root = result.root;
  if (root == null || result.errors.isNotEmpty) {
    return ParsedSearchInput(const [], trimmed);
  }
  // A pure conjunction is either a single primary or a flat AndNode of them —
  // the grammar never nests a junction inside an AndNode (`and` binds tighter
  // than `or`, so an `or` always surfaces as the root, already handled above).
  final nodes = root is AndNode ? root.children : [root];
  final chips = <SearchChip>[];
  final textParts = <String>[];
  for (final node in nodes) {
    final chip = chipForNode(node);
    if (chip != null) {
      chips.add(chip);
    } else if (node is TermNode) {
      // A general (unscoped) term stays as free text, re-emitted so it lexes
      // back to the same general term.
      textParts.add(_generalTermSource(node.text));
    } else {
      // Anything else (an unexpected junction) — keep the whole query as text.
      return ParsedSearchInput(const [], trimmed);
    }
  }
  return ParsedSearchInput(chips, textParts.join(' '));
}

/// Serializes [chips] followed by the trailing [text] into one DSL query
/// string. Chips are space-joined (implicit AND); [text] is appended verbatim
/// (it is already valid DSL the user typed).
String serializeSearchInput(List<SearchChip> chips, String text) {
  final parts = [for (final chip in chips) chip.raw];
  final tail = text.trim();
  if (tail.isNotEmpty) {
    parts.add(tail);
  }
  return parts.join(' ');
}

/// The canonical form of [query] as the chip field would round-trip it (chips
/// lifted to the front, free text trailing). Idempotent, so it is the string to
/// compare a freshly-serialized field against when deciding whether a resubmit
/// is the same query already on screen (refresh) or a new one (navigate).
String canonicalSearchQuery(String query) {
  final parsed = parseSearchInput(query);
  return serializeSearchInput(parsed.chips, parsed.text);
}

/// The chip for a single [clause] (`tag:dessert`, `calories:<400`,
/// `tag:"main dish"`), or null when [clause] is not exactly one recognized
/// scoped/calories clause (a bare word, a quoted phrase, a partial `tag:`, an
/// `and`/`or`, or more than one term).
SearchChip? chipForClause(String clause) {
  final result = parseSearchQuery(clause.trim());
  if (result.errors.isNotEmpty || result.root == null) {
    return null;
  }
  return chipForNode(result.root!);
}

/// The trailing scoped/calories clause to convert into a chip at a commit point
/// (a just-typed space, or Enter), with the index in [textBeforeCaret] where
/// that clause begins — or null when the trailing text is not a single
/// completable clause.
///
/// Considers up to the last three lexemes, so a space-separated `calories: <
/// 400` or a scoped phrase `tag: "main dish"` still resolves as one clause. Only
/// one of the lengths can ever form a single clause (a complete `scope:value` is
/// one lexeme; a `scope:`-then-phrase is two; a spaced calories filter is
/// three), so the longest match that parses is the answer.
({SearchChip chip, int start})? trailingChip(String textBeforeCaret) {
  final spans = lexQuerySpans(textBeforeCaret);
  if (spans.isEmpty) {
    return null;
  }
  ({SearchChip chip, int start})? best;
  for (var take = 1; take <= 3 && take <= spans.length; take++) {
    final startSpan = spans[spans.length - take];
    final chip = chipForClause(textBeforeCaret.substring(startSpan.start));
    if (chip != null) {
      best = (chip: chip, start: startSpan.start);
    }
  }
  return best;
}

/// The chip for a single AST [node] — a scoped [TermNode] or a [CaloriesNode] —
/// or null for a general term or a junction.
SearchChip? chipForNode(SearchNode node) {
  if (node is TermNode && node.scope != SearchScope.general) {
    return SearchChip(
      scopeLabel: node.scope.name,
      value: node.text,
      raw: '${node.scope.name}:${quoteDslValue(node.text)}',
      isTag: node.scope == SearchScope.tag,
    );
  }
  if (node is CaloriesNode) {
    final number = _formatNum(node.value);
    final isEq = node.op == CaloriesOp.eq;
    return SearchChip(
      scopeLabel: caloriesKeyword,
      // `= 400` reads oddly for the no-operator default, so an exact match
      // shows just the number; comparisons show the operator.
      value: isEq ? number : '${node.op.symbol} $number',
      raw: 'calories:${isEq ? '' : node.op.symbol}$number',
      isTag: false,
    );
  }
  return null;
}

/// Formats a calories threshold without a spurious `.0` on whole numbers.
String _formatNum(num value) {
  if (value is int || value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// Serializes a general (unscoped) term so it re-lexes as the SAME general
/// term. [quoteDslValue] quotes only for embedded whitespace or a `"`, but a
/// bare token can also be re-read as a boolean operator (`and`/`or`) or, with a
/// recognized prefix, as a scoped/calories clause (`title:pork`,
/// `calories:400`) — a general phrase like `"title:pork"` must therefore be
/// re-quoted, or the round-trip silently turns a literal-text search into a
/// field filter. (An unknown prefix like `cuisine:thai` stays a general term
/// bare, so it does not need quoting.)
String _generalTermSource(String text) {
  final lower = text.toLowerCase();
  final colon = text.indexOf(':');
  final reLexesAsScope =
      colon > 0 &&
      searchKeywords.contains(text.substring(0, colon).toLowerCase());
  if (lower == 'and' || lower == 'or' || reLexesAsScope) {
    return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
  return quoteDslValue(text);
}
