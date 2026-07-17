import 'package:salt_shared/src/search/dsl_parser.dart';
import 'package:salt_shared/src/search/dsl_spans.dart';
import 'package:test/test.dart';

// The span lexer exists to mirror the parser's tokenizer, so almost nothing
// here asserts against a hand-written expectation: it asserts against
// `parseSearchQuery` itself. A test that agreed with me but not with the
// parser would be worth nothing — the whole point is that a spliced
// suggestion must parse back to the term the user picked.
import 'corpus.dart';

void main() {
  group('lexQuerySpans mirrors the tokenizer', () {
    test('spans cover every non-whitespace character, in order', () {
      const input = '  title:"chocolate cake"  tag:dessert  ';
      final spans = lexQuerySpans(input);
      // `title:` and the phrase are SEPARATE lexemes even with no space
      // between them — the scope prefix is a word that a `"` terminates.
      // That is the tokenizer's shape, and the span lexer must share it.
      expect(spans.map((s) => s.source), [
        'title:',
        '"chocolate cake"',
        'tag:dessert',
      ]);
      for (final span in spans) {
        expect(span.source, input.substring(span.start, span.end));
      }
    });

    test('a quote ends a bare word, exactly as the tokenizer does', () {
      // The tokenizer stops a word at `"`, so `tag:ice"cream` is two lexemes
      // and two terms. Splitting on whitespace alone would call it one.
      final result = parseSearchQuery('tag:ice"cream');
      expect(result.root, isA<AndNode>());
      final spans = lexQuerySpans('tag:ice"cream');
      expect(spans.map((s) => s.source), ['tag:ice', '"cream']);
      expect(spans.last.quoted, isTrue);
      expect(spans.last.closed, isFalse);
    });

    test('an escaped quote does not close a phrase', () {
      final spans = lexQuerySpans(r'title:"say \"hi\"" tag:dessert');
      expect(spans.map((s) => s.source), [
        'title:',
        r'"say \"hi\""',
        'tag:dessert',
      ]);
    });

    test('NBSP separates but a zero-width space does not', () {
      // `_isWhitespace` is `trim().isEmpty`, so this is the tokenizer's own
      // rule; a pasted query carries both characters.
      expect(lexQuerySpans('a b').map((s) => s.source), ['a', 'b']);
      expect(lexQuerySpans('a​b').map((s) => s.source), ['a​b']);
    });

    test('an unterminated phrase runs to the end', () {
      final spans = lexQuerySpans('title:"chocolate cake');
      expect(spans.map((s) => s.source), ['title:', '"chocolate cake']);
      expect(spans.last.closed, isFalse);
      expect(spans.last.valueEnd, spans.last.end);
    });
  });

  group('spanAtCursor', () {
    const input = 'title:"chocolate cake"';
    final spans = lexQuerySpans(input);

    test('a cursor inside a phrase is inside ONE lexeme', () {
      // The failure this guards: treating the phrase as two words would offer
      // a completion for `cake` and splice it inside the quotes.
      expect(spanAtCursor(spans, 12)!.source, '"chocolate cake"');
    });

    test('a cursor at a lexeme end still edits that lexeme', () {
      expect(spanAtCursor(spans, 6)!.source, 'title:');
    });

    test('a cursor at the very start is a fresh position', () {
      expect(spanAtCursor(spans, 0), isNull);
    });

    test('a cursor after a space is a fresh position, not the next word', () {
      // Left-bias: `chicken |soup` offers keywords rather than replacing soup.
      final s = lexQuerySpans('chicken soup');
      expect(spanAtCursor(s, 8), isNull);
      expect(spanAtCursor(s, 9)!.source, 'soup');
    });
  });

  group('quoteDslValue round-trips through the real parser', () {
    // The property that matters: whatever we splice in must parse back to the
    // exact value the user picked. Anything less means a suggestion silently
    // searches for something other than what it said.
    void expectRoundTrip(String value) {
      final query = 'tag:${quoteDslValue(value)}';
      final result = parseSearchQuery(query);
      expect(
        result.errors,
        isEmpty,
        reason: 'query <$query> from value <$value> did not parse cleanly',
      );
      expect(
        result.root,
        TermNode(scope: SearchScope.tag, text: value, isPhrase: value.contains(' ')),
        reason: 'value <$value> did not survive <$query>',
      );
    }

    test('the corpus tag round-trips', () {
      expectRoundTrip('dessert');
    });

    test('a value with a space must be quoted to stay one term', () {
      // Unquoted, this is the silent failure: two terms, one of them general.
      expect(parseSearchQuery('tag:ice cream').root, isA<AndNode>());
      expectRoundTrip('ice cream');
    });

    test('quotes and backslashes survive', () {
      expectRoundTrip('say "hi"');
      expectRoundTrip('a b\\c');
      expectRoundTrip('a "b\\c"');
    });

    test('a bare backslash is NOT quoted, because quoting would eat it', () {
      // Inside a phrase `\X` collapses to X, so `tag:"back\slash"` searches
      // for `backslash`. Bare keeps it.
      expect(quoteDslValue(r'back\slash'), r'back\slash');
      expectRoundTrip(r'back\slash');
    });

    test(
      'every real corpus title round-trips as a scoped phrase',
      () {
        // 1,198 real titles: apostrophes, commas, parentheses, quotes,
        // accents. Tag names are almost unconstrained (1-60 chars) but the
        // corpus holds only one, so real titles are the honest source of
        // hostile-but-valid strings for the escaper.
        final titles = decodeCorpus()
            .results
            .values
            .map((r) => r.recipe.title)
            .where((t) => t.trim() == t && t.isNotEmpty)
            .toSet();
        expect(titles.length, greaterThan(1000));
        for (final title in titles) {
          final query = 'title:${quoteDslValue(title)}';
          final result = parseSearchQuery(query);
          expect(result.errors, isEmpty, reason: 'title <$title> -> <$query>');
          final root = result.root;
          expect(root, isA<TermNode>(), reason: 'title <$title> -> <$query>');
          expect(
            (root! as TermNode).text,
            title,
            reason: 'title <$title> did not survive <$query>',
          );
        }
      },
      skip: skipIfNoCorpus,
    );
  });
}
