import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

void main() {
  group('parseSearchInput', () {
    test('a scoped clause becomes a chip and leaves no text', () {
      final parsed = parseSearchInput('tag:dessert');
      expect(parsed.text, '');
      expect(parsed.chips, hasLength(1));
      final chip = parsed.chips.single;
      expect(chip.scopeLabel, 'tag');
      expect(chip.value, 'dessert');
      expect(chip.raw, 'tag:dessert');
      expect(chip.isTag, isTrue);
    });

    test('a bare word stays as free text, not a chip', () {
      final parsed = parseSearchInput('chicken');
      expect(parsed.chips, isEmpty);
      expect(parsed.text, 'chicken');
    });

    test('a quoted phrase stays as free text', () {
      final parsed = parseSearchInput('"chicken soup"');
      expect(parsed.chips, isEmpty);
      expect(parsed.text, '"chicken soup"');
    });

    test('each recognized scope becomes a chip', () {
      for (final scope in ['title', 'ingredient', 'direction', 'note']) {
        final parsed = parseSearchInput('$scope:value');
        expect(parsed.chips.single.scopeLabel, scope);
        expect(parsed.chips.single.value, 'value');
        expect(parsed.chips.single.isTag, isFalse);
      }
    });

    test('a multi-word tag value is a chip whose raw re-quotes', () {
      final parsed = parseSearchInput('tag:"main dish"');
      final chip = parsed.chips.single;
      expect(chip.value, 'main dish');
      expect(chip.raw, 'tag:"main dish"');
    });

    test('a calories comparison becomes a chip showing the operator', () {
      final parsed = parseSearchInput('calories:<400');
      final chip = parsed.chips.single;
      expect(chip.scopeLabel, 'calories');
      expect(chip.value, '< 400');
      expect(chip.raw, 'calories:<400');
      expect(chip.isTag, isFalse);
    });

    test('an exact calories match hides the = operator', () {
      final parsed = parseSearchInput('calories:400');
      final chip = parsed.chips.single;
      expect(chip.value, '400');
      expect(chip.raw, 'calories:400');
    });

    test('calories thresholds drop a spurious .0', () {
      expect(parseSearchInput('calories:>=250').chips.single.value, '>= 250');
      expect(parseSearchInput('calories:<400.5').chips.single.value, '< 400.5');
    });

    test('chips lift out and free text stays, in a mixed query', () {
      final parsed = parseSearchInput('chicken tag:dessert calories:<400');
      expect(parsed.chips.map((c) => c.raw), ['tag:dessert', 'calories:<400']);
      expect(parsed.text, 'chicken');
    });

    test('free text collects even when it trails a chip in the source', () {
      // Chips gather to the front; the bare words stay as the text tail.
      final parsed = parseSearchInput('tag:dessert chicken soup');
      expect(parsed.chips.map((c) => c.raw), ['tag:dessert']);
      expect(parsed.text, 'chicken soup');
    });

    test('a query with `or` is kept whole as text (chips are AND-only)', () {
      final parsed = parseSearchInput('tag:dessert or tag:snack');
      expect(parsed.chips, isEmpty);
      expect(parsed.text, 'tag:dessert or tag:snack');
    });

    test('a malformed query is kept whole as text', () {
      final parsed = parseSearchInput('tag:'); // no value → parse error
      expect(parsed.chips, isEmpty);
      expect(parsed.text, 'tag:');
    });

    test('an unknown prefix is free text, not a chip', () {
      // `cuisine:` is not a recognized scope: it is a general term with a colon.
      final parsed = parseSearchInput('cuisine:thai');
      expect(parsed.chips, isEmpty);
      expect(parsed.text, 'cuisine:thai');
    });

    test('empty / whitespace input yields nothing', () {
      expect(parseSearchInput('').chips, isEmpty);
      expect(parseSearchInput('   ').text, '');
    });

    test('a general phrase that re-lexes as a scope keeps its quotes', () {
      // "title:pork" is a literal-text search, NOT a title filter — re-emitting
      // it bare (`title:pork`) would flip its meaning and chip it.
      final parsed = parseSearchInput('"title:pork"');
      expect(parsed.chips, isEmpty);
      expect(parsed.text, '"title:pork"');
      expect(parseSearchInput(parsed.text).chips, isEmpty, reason: 'stays text');
    });

    test('a general phrase that re-lexes as an operator keeps its quotes', () {
      final parsed = parseSearchInput('"or"');
      expect(parsed.chips, isEmpty);
      expect(parsed.text, '"or"');
      // The serialized form must still parse (a bare `or` would be a dangling
      // operator error).
      expect(parseSearchQuery(parsed.text).errors, isEmpty);
    });

    test('an unknown prefix stays a bare general term (no needless quotes)', () {
      final parsed = parseSearchInput('cuisine:thai');
      expect(parsed.chips, isEmpty);
      expect(parsed.text, 'cuisine:thai');
    });
  });

  group('serializeSearchInput', () {
    test('joins chips then the text tail with single spaces', () {
      final chips = [
        const SearchChip(
          scopeLabel: 'tag',
          value: 'dessert',
          raw: 'tag:dessert',
          isTag: true,
        ),
        const SearchChip(
          scopeLabel: 'calories',
          value: '< 400',
          raw: 'calories:<400',
          isTag: false,
        ),
      ];
      expect(
        serializeSearchInput(chips, 'chicken'),
        'tag:dessert calories:<400 chicken',
      );
    });

    test('no chips is just the text', () {
      expect(serializeSearchInput(const [], 'chicken soup'), 'chicken soup');
    });

    test('no text is just the chips', () {
      final chips = parseSearchInput('tag:dessert').chips;
      expect(serializeSearchInput(chips, '  '), 'tag:dessert');
    });

    test('empty everything is the empty string', () {
      expect(serializeSearchInput(const [], ''), '');
    });
  });

  group('round-trip', () {
    // parse → serialize → parse must be stable, and re-serializing the
    // serialized form must be idempotent, so URL ↔ chips ↔ URL never drifts.
    for (final query in [
      'tag:dessert',
      'title:pork',
      'ingredient:butter',
      'calories:<400',
      'calories:400',
      'tag:"main dish"',
      'tag:dessert calories:<400 chocolate',
      'chicken tag:dessert', // reorders to `tag:dessert chicken`, then stable
      'chicken soup', // pure free text
      'tag:dessert or tag:snack', // or → all text, stable
      'note:"make ahead" tag:quick weeknight',
      '"title:pork"', // a general phrase whose value re-lexes as a scope
      '"tag:x"',
      '"calories:400"',
      '"or"', // a general phrase whose value re-lexes as an operator
      '"and"',
      'cuisine:thai', // unknown prefix stays a general term (bare)
    ]) {
      test('idempotent for: $query', () {
        final first = parseSearchInput(query);
        final serialized = serializeSearchInput(first.chips, first.text);
        final second = parseSearchInput(serialized);
        expect(second.chips, first.chips, reason: 'chips must be stable');
        expect(second.text, first.text, reason: 'text must be stable');
        expect(
          serializeSearchInput(second.chips, second.text),
          serialized,
          reason: 'serialization must be idempotent',
        );
        // The serialized string must itself parse back to the same clauses via
        // the real DSL — no chip may emit text the parser rejects or re-reads
        // differently.
        expect(parseSearchQuery(serialized).errors, isEmpty);
      });
    }
  });

  group('chipForClause', () {
    test('recognizes each single scoped clause', () {
      expect(chipForClause('tag:dessert')?.raw, 'tag:dessert');
      expect(chipForClause('title:pork')?.raw, 'title:pork');
      expect(chipForClause('calories:<400')?.raw, 'calories:<400');
      expect(chipForClause('tag:"main dish"')?.value, 'main dish');
    });

    test('rejects things that are not one scoped clause', () {
      expect(chipForClause('chicken'), isNull); // general word
      expect(chipForClause('"chicken soup"'), isNull); // general phrase
      expect(chipForClause('tag:'), isNull); // partial
      expect(chipForClause('calories:'), isNull); // partial
      expect(chipForClause('and'), isNull); // keyword
      expect(chipForClause('tag:dessert chicken'), isNull); // two terms
      expect(chipForClause('cuisine:thai'), isNull); // unknown scope
    });
  });

  group('trailingChip', () {
    test('finds a completed clause at the end of the text', () {
      final hit = trailingChip('tag:dessert');
      expect(hit?.chip.raw, 'tag:dessert');
      expect(hit?.start, 0);
    });

    test('leaves preceding free text in place', () {
      final hit = trailingChip('chicken tag:dessert');
      expect(hit?.chip.raw, 'tag:dessert');
      expect(hit?.start, 'chicken '.length);
    });

    test('resolves a scoped phrase written with a space after the colon', () {
      final hit = trailingChip('tag: "main dish"');
      expect(hit?.chip.raw, 'tag:"main dish"');
      expect(hit?.start, 0);
    });

    test('resolves a space-separated calories filter (three lexemes)', () {
      final hit = trailingChip('calories: < 400');
      expect(hit?.chip.raw, 'calories:<400');
      expect(hit?.start, 0);
    });

    test('returns null when the trailing token is not a clause', () {
      expect(trailingChip('chicken'), isNull);
      expect(trailingChip('tag:'), isNull);
      expect(trailingChip('chicken soup'), isNull);
      expect(trailingChip(''), isNull);
    });
  });

  group('queryHasOr', () {
    test('detects a bare or connective', () {
      expect(queryHasOr('tag:dessert or tag:snack'), isTrue);
      expect(queryHasOr('a OR b'), isTrue);
    });

    test('ignores or inside a value or a phrase', () {
      expect(queryHasOr('tag:or'), isFalse);
      expect(queryHasOr('"or"'), isFalse);
      expect(queryHasOr('tag:dessert calories:<400'), isFalse);
    });
  });
}
