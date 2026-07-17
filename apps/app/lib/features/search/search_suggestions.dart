import 'package:flutter/foundation.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/tags_repository.dart';

/// One row the search bar can offer, already resolved to the query it would
/// produce.
///
/// [query] is the WHOLE field text after the row is taken, not the fragment
/// being inserted. That is deliberate: it keeps the splice — which has to know
/// the token's range and the DSL's quoting rules — out of the widget, where it
/// could only be tested by driving a popover.
@immutable
class SearchSuggestion {
  const SearchSuggestion({
    required this.label,
    required this.detail,
    required this.query,
    required this.cursor,
  });

  /// What the row shows.
  final String label;

  /// The muted half of the row: what the keyword does, or a tag's recipe
  /// count.
  final String detail;

  /// The field's full text once taken.
  final String query;

  /// Where the caret lands afterwards — after `tag:` so the value can be
  /// typed, or past the trailing space of a finished term.
  final int cursor;

  @override
  bool operator ==(Object other) =>
      other is SearchSuggestion &&
      other.label == label &&
      other.detail == detail &&
      other.query == query &&
      other.cursor == cursor;

  @override
  int get hashCode => Object.hash(label, detail, query, cursor);

  @override
  String toString() => 'SearchSuggestion($label -> $query @$cursor)';
}

/// What each keyword does, in the user's terms rather than the parser's.
const Map<String, String> _keywordHelp = {
  'title': 'in the recipe name',
  'tag': 'carries a tag',
  'ingredient': 'in the ingredients',
  'direction': 'in the steps',
  'note': 'in the recipe notes',
  'calories': 'per serving, e.g. calories:<400',
};

/// Whether [name] can be searched for at all.
///
/// A tag is only validated for length (1–60 chars), so `&` is a legal tag —
/// but `tag:"&"` compiles to no FTS match and the search then returns the
/// ENTIRE library. A row that silently means "everything" is worse than no
/// row, so a tag with no letter or digit is never offered.
bool _isSearchable(String name) =>
    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(name);

/// The rows to offer for [text] with the caret at [cursor].
///
/// Cursor-aware rather than end-of-string, because `tag:des| pie` and
/// `tag:des pie|` want completely different rows. (The caret can still go
/// stale for one beat: Flutter's RawAutocomplete only re-runs this when the
/// TEXT changes, so moving the caret without typing leaves the previous rows
/// up until the next keystroke. That is a wart, not a correctness bug — the
/// row it offers still splices at the position it was computed for.)
List<SearchSuggestion> suggestionsFor({
  required String text,
  required int cursor,
  required List<TagInfo> tags,
  int limit = 8,
}) {
  final caret = cursor.clamp(0, text.length);
  final span = spanAtCursor(lexQuerySpans(text), caret);

  // A fresh position: nothing is being edited, so offer the vocabulary.
  if (span == null) {
    return _keywordRows(
      typed: '',
      text: text,
      start: caret,
      end: caret,
      limit: limit,
    );
  }

  if (span.quoted) {
    // A phrase is a value. It is scoped only by the lexeme before it, and
    // only `tag:` has anything to complete.
    if (_phraseScope(text, span) != 'tag') {
      return const [];
    }
    final valueEnd = caret.clamp(span.valueStart, span.valueEnd);
    return _tagRows(
      typed: text.substring(span.valueStart, valueEnd),
      tags: tags,
      text: text,
      start: span.start,
      end: span.end,
      // The `tag:` prefix is its own lexeme here and is already in the text —
      // only the phrase is being replaced. Re-inserting the scope would give
      // `tag:tag:"ice cream"`.
      scopePrefix: '',
      limit: limit,
    );
  }

  final colon = span.source.indexOf(':');
  // `colon == 0` is a leading colon, which the parser reads as a general word,
  // not a scope.
  if (colon <= 0 || caret <= span.start + colon) {
    // Still typing the name — either it has no colon yet, or the caret is
    // before the one it has.
    return _keywordRows(
      typed: text.substring(span.start, caret),
      text: text,
      start: span.start,
      end: span.end,
      limit: limit,
    );
  }

  if (span.source.substring(0, colon).toLowerCase() != 'tag') {
    // title/ingredient/direction/note take free text and calories takes a
    // number; none is completable. An unrecognised name is a general term.
    return const [];
  }
  return _tagRows(
    typed: text.substring(span.start + colon + 1, caret),
    tags: tags,
    text: text,
    start: span.start,
    end: span.end,
    limit: limit,
  );
}

/// The scope a quoted [span] is bound by, or null when it stands alone.
///
/// A phrase is scoped when the lexeme immediately before it is exactly a
/// scope prefix (`tag:`), since that is the only shape that leaves the scope
/// looking for a term. `tag: "ice cream"` with a space works, which is why
/// this looks at the previous LEXEME rather than the character before.
String? _phraseScope(String text, QuerySpan span) {
  final before = lexQuerySpans(text.substring(0, span.start));
  if (before.isEmpty) {
    return null;
  }
  final previous = before.last.source.toLowerCase();
  if (!previous.endsWith(':')) {
    return null;
  }
  final name = previous.substring(0, previous.length - 1);
  return searchKeywords.contains(name) ? name : null;
}

List<SearchSuggestion> _keywordRows({
  required String typed,
  required String text,
  required int start,
  required int end,
  required int limit,
}) {
  final prefix = typed.toLowerCase();
  return [
    for (final keyword in searchKeywords)
      if (keyword.startsWith(prefix))
        _row(
          label: '$keyword:',
          detail: _keywordHelp[keyword] ?? '',
          text: text,
          start: start,
          end: end,
          // No trailing space: the value comes next, and the caret lands
          // right after the colon ready for it.
          insert: '$keyword:',
        ),
  ].take(limit).toList();
}

List<SearchSuggestion> _tagRows({
  required String typed,
  required List<TagInfo> tags,
  required String text,
  required int start,
  required int end,
  required int limit,
  String scopePrefix = 'tag:',
}) {
  final needle = typed.toLowerCase();
  final matches =
      tags
          .where((tag) => _isSearchable(tag.name))
          .where((tag) => tag.name.toLowerCase().contains(needle))
          .toList()
        // An exact hit first, then prefixes, then the rest — the same order the
        // editor's tag field uses, so `des` does not bury `dessert` under a
        // longer tag that merely contains it.
        ..sort((a, b) {
          final rank = _rank(a.name, needle).compareTo(_rank(b.name, needle));
          return rank != 0 ? rank : a.name.compareTo(b.name);
        });
  return [
    for (final tag in matches.take(limit))
      _row(
        label: tag.name,
        detail: '${tag.count} recipe${tag.count == 1 ? '' : 's'}',
        text: text,
        start: start,
        end: end,
        // quoteDslValue is what keeps `tag:ice cream` from silently becoming
        // two terms, one of them an unscoped `cream`.
        insert: '$scopePrefix${quoteDslValue(tag.name)}',
        trailingSpace: true,
      ),
  ];
}

int _rank(String name, String needle) {
  final lower = name.toLowerCase();
  if (lower == needle) return 0;
  if (lower.startsWith(needle)) return 1;
  return 2;
}

SearchSuggestion _row({
  required String label,
  required String detail,
  required String text,
  required int start,
  required int end,
  required String insert,
  bool trailingSpace = false,
}) {
  final tail = text.substring(end);
  final space = trailingSpace && !tail.startsWith(' ') ? ' ' : '';
  final body = '$insert$space';
  return SearchSuggestion(
    label: label,
    detail: detail,
    query: '${text.substring(0, start)}$body$tail',
    cursor: start + body.length,
  );
}
