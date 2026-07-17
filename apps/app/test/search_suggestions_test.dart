import 'package:flutter_test/flutter_test.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/features/search/search_suggestions.dart';

/// The search bar's suggestion logic.
///
/// The rule this suite enforces everywhere: a row's [SearchSuggestion.query]
/// is PARSED by the real DSL, not compared to a string I wrote down. A
/// suggestion that produces a query the parser reads differently than the row
/// promised is the whole failure mode — `tag:ice cream` looks right and
/// silently searches for a tag `ice` AND the word `cream`.
TagInfo _tag(String name, int count) =>
    TagInfo(name: name, count: count, style: const TagStyle());

// The dev library and the ATK corpus hold exactly ONE tag ('dessert', 214
// recipes), which cannot exercise ranking, quoting or capping. These are real
// tag SHAPES the editor accepts (1-60 chars, otherwise unconstrained) rather
// than corpus data, because the corpus has no second tag to offer.
final _tags = [
  _tag('dessert', 214),
  _tag('desserts-frozen', 12),
  _tag('ice cream', 9),
  _tag('main', 88),
];

void main() {
  group('keywords', () {
    test('an empty field offers every keyword the parser accepts', () {
      final rows = suggestionsFor(text: '', cursor: 0, tags: _tags);
      expect(
        rows.map((r) => r.label),
        searchKeywords.map((k) => '$k:'),
        reason: 'the offered list must BE the parser list, not a copy of it',
      );
    });

    test('calories: is offered — it is not a SearchScope', () {
      // The trap: a keyword list built from SearchScope.values omits calories
      // entirely and includes `general`, which is not a keyword at all.
      final rows = suggestionsFor(text: '', cursor: 0, tags: _tags);
      expect(rows.map((r) => r.label), contains('calories:'));
      expect(rows.map((r) => r.label), isNot(contains('general:')));
    });

    test('typing narrows to the matching keywords', () {
      final rows = suggestionsFor(text: 't', cursor: 1, tags: _tags);
      expect(rows.map((r) => r.label), ['title:', 'tag:']);
    });

    test('a word that matches no keyword offers nothing', () {
      // Ordinary searching must not be interrupted by a popover.
      expect(suggestionsFor(text: 'chicken', cursor: 7, tags: _tags), isEmpty);
    });

    test('taking a keyword leaves the caret ready for the value', () {
      final row = suggestionsFor(text: 'ta', cursor: 2, tags: _tags).single;
      expect(row.query, 'tag:');
      expect(row.cursor, 4);
    });

    test('a keyword splices into the middle without eating the rest', () {
      final row = suggestionsFor(text: 'ta pie', cursor: 2, tags: _tags).single;
      expect(row.query, 'tag: pie');
      expect(row.cursor, 4);
    });

    test('the caret before a colon still edits the name', () {
      // `ta|g:dessert` — the user is fixing the scope, not the value, so the
      // rows are keywords matching `ta` rather than tag values.
      final rows = suggestionsFor(text: 'tag:dessert', cursor: 2, tags: _tags);
      expect(rows.map((r) => r.label), ['tag:']);
    });

    test('fixing a misspelled scope KEEPS the value it is bound to', () {
      // `titl|:dessert` -> `title:dessert`. Replacing the whole lexeme instead
      // deletes `dessert`, and the scope then binds to whatever word comes
      // next — a well-formed query with a different meaning and no error.
      final rows = suggestionsFor(text: 'titl:dessert', cursor: 4, tags: _tags);
      expect(rows.single.query, 'title:dessert');
      expect(
        parseSearchQuery(rows.single.query).root,
        const TermNode(scope: SearchScope.title, text: 'dessert'),
      );
    });

    test('fixing a scope does not swallow the FOLLOWING term', () {
      // The one that makes it dangerous: `soup` silently became title-scoped
      // and `dessert` vanished, with an empty error list.
      final rows = suggestionsFor(
        text: 'chicken titl:dessert soup',
        cursor: 12,
        tags: _tags,
      );
      expect(rows.single.query, 'chicken title:dessert soup');
      final parsed = parseSearchQuery(rows.single.query);
      expect(parsed.errors, isEmpty);
      expect(
        parsed.root,
        const AndNode([
          TermNode(text: 'chicken'),
          TermNode(scope: SearchScope.title, text: 'dessert'),
          TermNode(text: 'soup'),
        ]),
      );
    });
  });

  group('tag values', () {
    test('after tag: every searchable tag is offered', () {
      final rows = suggestionsFor(text: 'tag:', cursor: 4, tags: _tags);
      expect(rows.map((r) => r.label), [
        'dessert',
        'desserts-frozen',
        'ice cream',
        'main',
      ]);
    });

    test('an exact match sorts above tags that merely contain it', () {
      // The tie-break must do the WORK, not ride on the alphabet: `dessert`
      // sorts before `desserts-frozen` anyway, so a test using only those two
      // passes with the ranking deleted entirely. `baked-dessert` sorts FIRST
      // alphabetically, so only real ranking puts the exact hit on top.
      final rows = suggestionsFor(
        text: 'tag:dessert',
        cursor: 11,
        tags: [_tag('baked-dessert', 30), ..._tags],
      );
      expect(rows.first.label, 'dessert');
    });

    test('a prefix match sorts above a mere substring match', () {
      // Same trap one rank down: `almond-des` contains `des` but does not
      // start with it, and sorts first alphabetically.
      final rows = suggestionsFor(
        text: 'tag:des',
        cursor: 7,
        tags: [_tag('almond-des', 4), _tag('desserts-frozen', 12)],
      );
      expect(rows.map((r) => r.label), ['desserts-frozen', 'almond-des']);
    });

    test('the row says how many recipes carry the tag', () {
      final rows = suggestionsFor(text: 'tag:main', cursor: 8, tags: _tags);
      expect(rows.single.detail, '88 recipes');
    });

    test('a tag with a space is QUOTED, and the parser agrees', () {
      final row = suggestionsFor(
        text: 'tag:ice',
        cursor: 7,
        tags: _tags,
      ).single;
      expect(row.query, 'tag:"ice cream" ');
      // The assertion that matters: what does the PARSER think this means?
      final parsed = parseSearchQuery(row.query);
      expect(parsed.errors, isEmpty);
      expect(
        parsed.root,
        const TermNode(
          scope: SearchScope.tag,
          text: 'ice cream',
          isPhrase: true,
        ),
        reason: 'unquoted this is Term(tag:ice) AND Term(general:cream)',
      );
    });

    test('a tag that would match the whole library is never offered', () {
      // `&` is a legal tag (validation is length-only), but `tag:"&"` compiles
      // to no FTS match and returns EVERY recipe. A row that silently means
      // "everything" is worse than no row.
      final rows = suggestionsFor(
        text: 'tag:',
        cursor: 4,
        tags: [..._tags, _tag('&', 3)],
      );
      expect(rows.map((r) => r.label), isNot(contains('&')));
    });

    test('every offered tag round-trips through the parser', () {
      final rows = suggestionsFor(text: 'tag:', cursor: 4, tags: _tags);
      for (final row in rows) {
        final parsed = parseSearchQuery(row.query);
        expect(parsed.errors, isEmpty, reason: row.query);
        expect(
          parsed.root,
          isA<TermNode>()
              .having((t) => t.scope, 'scope', SearchScope.tag)
              .having((t) => t.text, 'text', row.label),
          reason: '<${row.query}> must mean exactly the tag <${row.label}>',
        );
      }
    });

    test('a tag splices in beside other terms', () {
      final rows = suggestionsFor(
        text: 'chicken tag:mai fast',
        cursor: 15,
        tags: _tags,
      );
      expect(rows.single.query, 'chicken tag:main fast');
      final parsed = parseSearchQuery(rows.single.query);
      expect(parsed.errors, isEmpty);
    });

    test('the list is capped', () {
      final many = [for (var i = 0; i < 40; i++) _tag('tag-$i', i)];
      expect(
        suggestionsFor(text: 'tag:', cursor: 4, tags: many, limit: 8),
        hasLength(8),
      );
    });
  });

  group('positions with nothing to say', () {
    test('free-text scopes offer nothing', () {
      for (final scope in ['title', 'ingredient', 'direction', 'note']) {
        final text = '$scope:choc';
        expect(
          suggestionsFor(text: text, cursor: text.length, tags: _tags),
          isEmpty,
          reason: '$scope: takes free text — there is nothing to complete',
        );
      }
    });

    test('calories: offers nothing — a number cannot be completed', () {
      expect(
        suggestionsFor(text: 'calories:<4', cursor: 11, tags: _tags),
        isEmpty,
      );
    });

    test('a quoted phrase is completed only when tag: scopes it', () {
      // `tag: "ice` -> tag values; `title:"choc` -> nothing.
      expect(
        suggestionsFor(text: 'tag:"ice', cursor: 8, tags: _tags),
        isNotEmpty,
      );
      expect(
        suggestionsFor(text: 'title:"ice', cursor: 10, tags: _tags),
        isEmpty,
      );
      expect(suggestionsFor(text: '"ice', cursor: 4, tags: _tags), isEmpty);
    });

    test('a quoted tag value replaces the whole phrase', () {
      final row = suggestionsFor(
        text: 'tag:"ice',
        cursor: 8,
        tags: _tags,
      ).single;
      expect(row.query, 'tag:"ice cream" ');
      expect(parseSearchQuery(row.query).errors, isEmpty);
    });
  });

  group('the caret is respected, not assumed to be at the end', () {
    test('a caret mid-query completes THAT token, not the last one', () {
      // Caret after `mai`, with a later term. Completing the trailing token
      // instead would rewrite `fast`.
      final rows = suggestionsFor(text: 'tag:mai fast', cursor: 7, tags: _tags);
      expect(rows.single.query, 'tag:main fast');
    });

    test('an out-of-range caret is clamped rather than crashing', () {
      expect(
        () => suggestionsFor(text: 'tag:', cursor: 99, tags: _tags),
        returnsNormally,
      );
      expect(
        () => suggestionsFor(text: 'tag:', cursor: -5, tags: _tags),
        returnsNormally,
      );
    });
  });
}
