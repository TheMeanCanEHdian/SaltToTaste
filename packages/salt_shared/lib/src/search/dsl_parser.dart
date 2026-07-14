/// Parser for the SaltToTaste search DSL.
///
/// The DSL supports scoped terms (`title:`, `tag:`, `ingredient:`,
/// `direction:`, `note:`), unscoped (general) terms, a `calories:` numeric
/// filter with comparison operators, double-quoted phrases, and the boolean
/// keywords `and` / `or` (`and` binds tighter). Adjacent terms without an
/// explicit keyword are AND'd together.
///
/// The parser is shared between the server (which compiles the AST to SQLite
/// FTS5) and the Flutter UI (chip rendering / validation), so it is tolerant:
/// malformed input produces a best-effort AST plus human-readable errors
/// rather than throwing.
library;

/// Which recipe field a [TermNode] searches.
///
/// [general] terms have no scope prefix and search across all text fields.
enum SearchScope { general, title, tag, ingredient, direction, note }

/// Comparison operator for a [CaloriesNode] (`calories:<400` etc.).
enum CaloriesOp {
  lt,
  lte,
  gt,
  gte,
  eq;

  /// The operator as written in a query (`<`, `<=`, `>`, `>=`, `=`).
  String get symbol => switch (this) {
        CaloriesOp.lt => '<',
        CaloriesOp.lte => '<=',
        CaloriesOp.gt => '>',
        CaloriesOp.gte => '>=',
        CaloriesOp.eq => '=',
      };
}

/// A node in the parsed search query AST.
sealed class SearchNode {
  const SearchNode();
}

/// A single search term, optionally scoped to one recipe field.
final class TermNode extends SearchNode {
  const TermNode({
    this.scope = SearchScope.general,
    required this.text,
    this.isPhrase = false,
  });

  /// The field this term is restricted to ([SearchScope.general] when the
  /// term had no scope prefix).
  final SearchScope scope;

  /// The term text, trimmed but with inner case preserved
  /// (case-insensitivity is the search engine's job).
  final String text;

  /// Whether the term was written as a double-quoted phrase and must match
  /// as a whole (`"fold in"`), rather than as a single word.
  final bool isPhrase;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TermNode &&
          other.scope == scope &&
          other.text == text &&
          other.isPhrase == isPhrase;

  @override
  int get hashCode => Object.hash(scope, text, isPhrase);

  @override
  String toString() =>
      'Term(${scope.name}:${isPhrase ? '"$text"' : text})';
}

/// A numeric calories filter (`calories:<400`).
final class CaloriesNode extends SearchNode {
  const CaloriesNode({required this.op, required this.value});

  /// The comparison operator ([CaloriesOp.eq] when none was written).
  final CaloriesOp op;

  /// The calories threshold.
  final num value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaloriesNode && other.op == op && other.value == value;

  @override
  int get hashCode => Object.hash(op, value);

  @override
  String toString() => 'Calories(${op.symbol} $value)';
}

/// A conjunction: every child must match.
final class AndNode extends SearchNode {
  const AndNode(this.children);

  /// The conjoined nodes, in query order (always 2+ from the parser).
  final List<SearchNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AndNode && _nodeListEquals(other.children, children);

  @override
  int get hashCode => Object.hash(AndNode, Object.hashAll(children));

  @override
  String toString() => 'And(${children.join(', ')})';
}

/// A disjunction: at least one child must match.
final class OrNode extends SearchNode {
  const OrNode(this.children);

  /// The alternative nodes, in query order (always 2+ from the parser).
  final List<SearchNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrNode && _nodeListEquals(other.children, children);

  @override
  int get hashCode => Object.hash(OrNode, Object.hashAll(children));

  @override
  String toString() => 'Or(${children.join(', ')})';
}

bool _nodeListEquals(List<SearchNode> a, List<SearchNode> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The outcome of [parseSearchQuery]: a best-effort AST plus any errors.
class SearchParseResult {
  const SearchParseResult({this.root, this.errors = const []});

  /// The root of the parsed AST, or `null` when nothing usable was parsed
  /// (empty input, or input that was entirely malformed).
  final SearchNode? root;

  /// Human-readable problems found while parsing. The parser is tolerant:
  /// a non-empty [errors] list does not imply [root] is `null`.
  final List<String> errors;
}

/// Parses a search DSL [input] string into a [SearchParseResult].
///
/// Empty or whitespace-only input yields a `null` root and no errors.
/// Malformed constructs (dangling `and`/`or`, a scope prefix with no term,
/// a non-numeric calories value, an unterminated quote) are reported in
/// [SearchParseResult.errors] while the rest of the query still parses.
SearchParseResult parseSearchQuery(String input) {
  final errors = <String>[];
  final tokens = _tokenize(input, errors);
  final root = _Parser(tokens, errors).parseQuery();
  return SearchParseResult(root: root, errors: errors);
}

// --- Tokenizer -------------------------------------------------------------

enum _TokenKind { word, phrase, and, or, scope, calories }

class _Token {
  const _Token(this.kind, {this.text = '', this.scope});

  final _TokenKind kind;

  /// Word or (unescaped, trimmed) phrase text.
  final String text;

  /// Set for [_TokenKind.scope] tokens.
  final SearchScope? scope;
}

const Map<String, SearchScope> _scopeNames = {
  'title': SearchScope.title,
  'tag': SearchScope.tag,
  'ingredient': SearchScope.ingredient,
  'direction': SearchScope.direction,
  'note': SearchScope.note,
};

bool _isWhitespace(String ch) => ch.trim().isEmpty;

List<_Token> _tokenize(String input, List<String> errors) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < input.length) {
    final ch = input[i];
    if (_isWhitespace(ch)) {
      i++;
      continue;
    }
    if (ch == '"') {
      i = _readPhrase(input, i, tokens, errors);
      continue;
    }
    final start = i;
    while (i < input.length && !_isWhitespace(input[i]) && input[i] != '"') {
      i++;
    }
    _emitWord(input.substring(start, i), tokens);
  }
  return tokens;
}

/// Reads a double-quoted phrase starting at the `"` at [start]; supports
/// backslash escapes (`\"` for a literal quote). Returns the next index.
int _readPhrase(
  String input,
  int start,
  List<_Token> tokens,
  List<String> errors,
) {
  var i = start + 1;
  final buf = StringBuffer();
  var closed = false;
  while (i < input.length) {
    final ch = input[i];
    if (ch == r'\' && i + 1 < input.length) {
      buf.write(input[i + 1]);
      i += 2;
      continue;
    }
    if (ch == '"') {
      closed = true;
      i++;
      break;
    }
    buf.write(ch);
    i++;
  }
  if (!closed) {
    errors.add('Unterminated quoted phrase.');
  }
  tokens.add(_Token(_TokenKind.phrase, text: buf.toString().trim()));
  return i;
}

/// Classifies one whitespace-delimited raw word into tokens: an `and`/`or`
/// keyword, a recognized scope prefix (optionally with the term attached,
/// as in `title:chicken`), a `calories:` filter prefix, or a plain word.
void _emitWord(String raw, List<_Token> tokens) {
  final lower = raw.toLowerCase();
  if (lower == 'and') {
    tokens.add(const _Token(_TokenKind.and));
    return;
  }
  if (lower == 'or') {
    tokens.add(const _Token(_TokenKind.or));
    return;
  }
  final colon = raw.indexOf(':');
  if (colon > 0) {
    final name = raw.substring(0, colon).toLowerCase();
    final rest = raw.substring(colon + 1);
    if (name == 'calories') {
      tokens.add(const _Token(_TokenKind.calories));
      if (rest.isNotEmpty) {
        tokens.add(_Token(_TokenKind.word, text: rest));
      }
      return;
    }
    final scope = _scopeNames[name];
    if (scope != null) {
      tokens.add(_Token(_TokenKind.scope, scope: scope));
      if (rest.isNotEmpty) {
        // The attached term is always plain text — `title:and` searches
        // titles for the word "and", it is not a keyword.
        tokens.add(_Token(_TokenKind.word, text: rest));
      }
      return;
    }
    // Unknown scope (`bogus:x`): a general term containing the colon.
  }
  tokens.add(_Token(_TokenKind.word, text: raw));
}

// --- Parser ----------------------------------------------------------------

/// Precedence-climbing parser over the token stream.
///
/// Grammar (`and` binds tighter than `or`; adjacency means `and`):
/// ```
/// query   := andGroup ( 'or' andGroup )*
/// andGroup:= primary ( 'and'? primary )*
/// primary := scope (word | phrase) | 'calories:' op? number | word | phrase
/// ```
class _Parser {
  _Parser(this.tokens, this.errors);

  final List<_Token> tokens;
  final List<String> errors;
  var _pos = 0;

  _Token? _peek() => _pos < tokens.length ? tokens[_pos] : null;

  _Token _advance() => tokens[_pos++];

  SearchNode? parseQuery() => _parseOr();

  SearchNode? _parseOr() {
    var (node: left, sawOperand: leftSawOperand) = _parseAndGroup();
    while (_peek() != null) {
      // _parseAndGroup only stops at `or` or end of input.
      _advance();
      if (!leftSawOperand) {
        errors.add("'or' has no search term before it.");
      }
      final (node: right, sawOperand: rightSawOperand) = _parseAndGroup();
      if (!rightSawOperand) {
        errors.add("'or' has no search term after it.");
      }
      leftSawOperand = leftSawOperand || rightSawOperand;
      if (right == null) continue;
      if (left == null) {
        left = right;
      } else if (left is OrNode) {
        left = OrNode([...left.children, right]);
      } else {
        left = OrNode([left, right]);
      }
    }
    return left;
  }

  /// Parses a run of primaries joined by adjacency or explicit `and`.
  ///
  /// [sawOperand] reports whether any operand was *attempted* — a malformed
  /// operand (e.g. `calories:cheap`) already produced its own error, so the
  /// surrounding `and`/`or` should not also be reported as dangling.
  ({SearchNode? node, bool sawOperand}) _parseAndGroup() {
    final children = <SearchNode>[];
    var sawOperand = false;
    while (true) {
      final token = _peek();
      if (token == null || token.kind == _TokenKind.or) break;
      if (token.kind == _TokenKind.and) {
        _advance();
        if (!sawOperand) {
          errors.add("'and' has no search term before it.");
        }
        final next = _peek();
        if (next == null ||
            next.kind == _TokenKind.or ||
            next.kind == _TokenKind.and) {
          errors.add("'and' has no search term after it.");
          if (next == null || next.kind == _TokenKind.or) break;
        }
        continue;
      }
      sawOperand = true;
      final node = _parsePrimary();
      if (node != null) children.add(node);
    }
    final node = switch (children.length) {
      0 => null,
      1 => children.first,
      _ => AndNode(children),
    };
    return (node: node, sawOperand: sawOperand);
  }

  /// Parses one term / phrase / scoped term / calories filter. Always
  /// consumes at least one token; returns `null` (with an error recorded)
  /// when the construct is unusable.
  SearchNode? _parsePrimary() {
    final token = _advance();
    switch (token.kind) {
      case _TokenKind.word:
        return TermNode(text: token.text);
      case _TokenKind.phrase:
        return _phraseTerm(SearchScope.general, token.text);
      case _TokenKind.scope:
        return _parseScopedTerm(token.scope!);
      case _TokenKind.calories:
        return _parseCalories();
      case _TokenKind.and:
      case _TokenKind.or:
        // Unreachable: keyword tokens are consumed by the group parsers.
        return null;
    }
  }

  SearchNode? _parseScopedTerm(SearchScope scope) {
    final next = _peek();
    if (next == null ||
        (next.kind != _TokenKind.word && next.kind != _TokenKind.phrase)) {
      errors.add("'${scope.name}:' has no search term.");
      return null;
    }
    _advance();
    if (next.kind == _TokenKind.phrase) {
      return _phraseTerm(scope, next.text);
    }
    return TermNode(scope: scope, text: next.text);
  }

  SearchNode? _phraseTerm(SearchScope scope, String text) {
    if (text.isEmpty) {
      errors.add('Empty quoted phrase.');
      return null;
    }
    return TermNode(scope: scope, text: text, isPhrase: true);
  }

  SearchNode? _parseCalories() {
    final next = _peek();
    if (next == null || next.kind != _TokenKind.word) {
      errors.add("'calories:' needs a number, like 'calories:<400'.");
      return null;
    }
    _advance();
    var text = next.text;
    var op = CaloriesOp.eq;
    if (text.startsWith('<=')) {
      op = CaloriesOp.lte;
      text = text.substring(2);
    } else if (text.startsWith('>=')) {
      op = CaloriesOp.gte;
      text = text.substring(2);
    } else if (text.startsWith('<')) {
      op = CaloriesOp.lt;
      text = text.substring(1);
    } else if (text.startsWith('>')) {
      op = CaloriesOp.gt;
      text = text.substring(1);
    } else if (text.startsWith('=')) {
      text = text.substring(1);
    }
    if (text.isEmpty) {
      // The operator stood alone (`calories: < 400`) — the number is in
      // the next token.
      final valueToken = _peek();
      if (valueToken == null || valueToken.kind != _TokenKind.word) {
        errors.add(
          "'calories:${op.symbol}' needs a number, like "
          "'calories:${op.symbol}400'.",
        );
        return null;
      }
      _advance();
      text = valueToken.text;
    }
    final value = num.tryParse(text);
    if (value == null) {
      errors.add("Invalid calories value '$text' — expected a number.");
      return null;
    }
    return CaloriesNode(op: op, value: value);
  }
}
