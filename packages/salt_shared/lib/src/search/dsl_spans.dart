/// Cursor-addressable spans over a raw search query.
///
/// The parser throws offsets away: a token knows its text but not where it came
/// from, one word lexeme can emit TWO tokens (`title:chicken` → scope + word),
/// and two lexemes can form ONE term (`title:"chocolate cake"`). None of those
/// shapes can answer "what is the cursor sitting in", which is the only
/// question a search bar's autocomplete asks.
///
/// So this is a second lexer over the same grammar, and it lives beside the
/// first because the two MUST agree — a span rule that disagreed with the
/// tokenizer would splice in text the parser then rejects. `dsl_spans_test.dart`
/// pins them to each other rather than to a hand-written expectation.
library;

/// True for the characters the tokenizer treats as separators.
///
/// Deliberately `trim().isEmpty`, matching the tokenizer exactly: that makes
/// NBSP (U+00A0) and the BOM (U+FEFF) separators, while the zero-width space
/// (U+200B) is an ordinary word character. Pasted queries carry all three.
bool isQueryWhitespace(String ch) => ch.trim().isEmpty;

/// One raw lexeme of a query, with the source range it occupies.
class QuerySpan {
  const QuerySpan({
    required this.start,
    required this.end,
    required this.source,
    required this.quoted,
    required this.closed,
  });

  /// Index of the first character.
  final int start;

  /// Index one past the last character.
  final int end;

  /// The text exactly as written — quotes and backslashes included.
  final String source;

  /// Whether the lexeme opened with a `"`.
  final bool quoted;

  /// Whether a quoted lexeme also closed. Always true for a bare word.
  final bool closed;

  /// Where the lexeme's value starts, skipping an opening quote.
  int get valueStart => quoted ? start + 1 : start;

  /// Where the lexeme's value ends, skipping a closing quote.
  int get valueEnd => quoted && closed ? end - 1 : end;

  @override
  String toString() =>
      'QuerySpan($start, $end, ${quoted ? 'phrase' : 'word'}, $source)';
}

/// Splits [input] into lexemes, mirroring the parser's tokenizer.
///
/// A `"` ends a bare word mid-lexeme (`tag:ice"cream` is two lexemes), so
/// splitting on whitespace alone is wrong.
List<QuerySpan> lexQuerySpans(String input) {
  final spans = <QuerySpan>[];
  var i = 0;
  while (i < input.length) {
    if (isQueryWhitespace(input[i])) {
      i++;
      continue;
    }
    final start = i;
    if (input[i] == '"') {
      var j = i + 1;
      var closed = false;
      while (j < input.length) {
        // `\X` escapes ANY X inside a phrase, not just `\"`.
        if (input[j] == r'\' && j + 1 < input.length) {
          j += 2;
          continue;
        }
        if (input[j] == '"') {
          j++;
          closed = true;
          break;
        }
        j++;
      }
      spans.add(
        QuerySpan(
          start: start,
          end: j,
          source: input.substring(start, j),
          quoted: true,
          closed: closed,
        ),
      );
      i = j;
      continue;
    }
    var j = i;
    while (j < input.length &&
        !isQueryWhitespace(input[j]) &&
        input[j] != '"') {
      j++;
    }
    spans.add(
      QuerySpan(
        start: start,
        end: j,
        source: input.substring(start, j),
        quoted: false,
        closed: true,
      ),
    );
    i = j;
  }
  return spans;
}

/// The lexeme [cursor] is editing, or null when it sits at a fresh position.
///
/// Left-biased (`start < cursor <= end`): a cursor at a lexeme's end is still
/// editing that lexeme, which is where a caret sits after typing it. A cursor
/// at a lexeme's *start* — the far side of a space — is a fresh position
/// instead, so `chicken |soup` offers keywords rather than silently replacing
/// `soup` when a suggestion is taken.
QuerySpan? spanAtCursor(List<QuerySpan> spans, int cursor) {
  for (final span in spans) {
    if (span.start < cursor && cursor <= span.end) {
      return span;
    }
  }
  return null;
}

/// Renders [value] so the parser reads it back verbatim as one term.
///
/// Bare when it can be: a bare word keeps a backslash literally, so quoting
/// `back\slash` would *lose* it (inside a phrase `\X` collapses to X). Quoted
/// otherwise, escaping backslashes BEFORE quotes — the reverse order would
/// re-escape the backslashes the quote-escaping just introduced.
///
/// A value that is empty or outer-whitespace cannot round-trip at all: the
/// parser trims phrase text, so `tag:"  "` is an error, not a search for two
/// spaces. Tag names are trimmed when created, so this cannot arise from the
/// library — it is guarded rather than handled.
String quoteDslValue(String value) {
  assert(
    value.isNotEmpty && value.trim() == value,
    'a value that is empty or outer-whitespace cannot be expressed in the DSL',
  );
  final needsQuotes =
      value.contains('"') || value.split('').any(isQueryWhitespace);
  if (!needsQuotes) {
    return value;
  }
  final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}
