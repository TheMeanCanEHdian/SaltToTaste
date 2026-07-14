import 'dart:io';

import 'package:salt_shared/src/search/dsl_parser.dart';
import 'package:test/test.dart';

// Shared corpus access: the query terms in this suite are derived from real
// corpus recipes (titles, tags, ingredients, direction phrases).
import 'corpus.dart';

void main() {
  group('empty input', () {
    test('empty string yields null root and no errors', () {
      final result = parseSearchQuery('');
      expect(result.root, isNull);
      expect(result.errors, isEmpty);
    });

    test('whitespace-only yields null root and no errors', () {
      final result = parseSearchQuery('   \t  ');
      expect(result.root, isNull);
      expect(result.errors, isEmpty);
    });
  });

  group('bare terms', () {
    test('single word is one general term', () {
      final result = parseSearchQuery('chicken');
      expect(result.errors, isEmpty);
      expect(result.root, const TermNode(text: 'chicken'));
    });

    test('adjacent bare words are AND\'d word-wise', () {
      // "Classic Chicken Noodle Soup" (0002) matches all three words.
      final result = parseSearchQuery('chicken noodle soup');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const AndNode([
          TermNode(text: 'chicken'),
          TermNode(text: 'noodle'),
          TermNode(text: 'soup'),
        ]),
      );
    });

    test('quoted phrase is a single phrase term', () {
      // Real direction text: "fold in" appears in e.g. 0077, 0122, 0288.
      final result = parseSearchQuery('"fold in"');
      expect(result.errors, isEmpty);
      expect(result.root, const TermNode(text: 'fold in', isPhrase: true));
    });

    test('quoted phrase next to a bare word: phrase stays whole', () {
      // "Sweet Potato Soup" (0020).
      final result = parseSearchQuery('"sweet potato" soup');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const AndNode([
          TermNode(text: 'sweet potato', isPhrase: true),
          TermNode(text: 'soup'),
        ]),
      );
    });
  });

  group('scoped terms', () {
    test('title: and ingredient: scopes combined with and', () {
      // Chicken titles (0002…) and ginger ingredients (0015…).
      final result = parseSearchQuery('title:chicken and ingredient:ginger');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const AndNode([
          TermNode(scope: SearchScope.title, text: 'chicken'),
          TermNode(scope: SearchScope.ingredient, text: 'ginger'),
        ]),
      );
    });

    test('scope applies only to the single term that follows', () {
      final result = parseSearchQuery('title:chicken soup');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const AndNode([
          TermNode(scope: SearchScope.title, text: 'chicken'),
          TermNode(text: 'soup'),
        ]),
      );
    });

    test('whitespace is allowed between the scope and its term', () {
      final result = parseSearchQuery('title: chicken');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const TermNode(scope: SearchScope.title, text: 'chicken'),
      );
    });

    test('scoped quoted phrase, attached and detached', () {
      // "fold in" is real direction text; "Dutch oven" appears in steps of
      // 0002, 0006, and many others.
      for (final query in [
        'direction:"fold in"',
        'direction: "fold in"',
      ]) {
        final result = parseSearchQuery(query);
        expect(result.errors, isEmpty, reason: query);
        expect(
          result.root,
          const TermNode(
            scope: SearchScope.direction,
            text: 'fold in',
            isPhrase: true,
          ),
          reason: query,
        );
      }
    });

    test('scope names match case-insensitively, term case is preserved', () {
      final result = parseSearchQuery('Title:Chicken');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const TermNode(scope: SearchScope.title, text: 'Chicken'),
      );

      final tag = parseSearchQuery('TAG:dessert');
      expect(tag.errors, isEmpty);
      expect(tag.root, const TermNode(scope: SearchScope.tag, text: 'dessert'));
    });

    test('all five text scopes are recognized', () {
      const expected = {
        'title': SearchScope.title,
        'tag': SearchScope.tag,
        'ingredient': SearchScope.ingredient,
        'direction': SearchScope.direction,
        'note': SearchScope.note,
      };
      expected.forEach((name, scope) {
        final result = parseSearchQuery('$name:ginger');
        expect(result.errors, isEmpty, reason: name);
        expect(result.root, TermNode(scope: scope, text: 'ginger'),
            reason: name);
      });
    });

    test('unknown scope is a general term containing the colon', () {
      final result = parseSearchQuery('bogus:x');
      expect(result.errors, isEmpty);
      expect(result.root, const TermNode(text: 'bogus:x'));

      final cuisine = parseSearchQuery('cuisine:portuguese');
      expect(cuisine.errors, isEmpty);
      expect(cuisine.root, const TermNode(text: 'cuisine:portuguese'));
    });

    test('a scoped keyword is a term, not an operator', () {
      final result = parseSearchQuery('title:and');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const TermNode(scope: SearchScope.title, text: 'and'),
      );
    });
  });

  group('boolean operators and precedence', () {
    test('or combines two scoped terms', () {
      // 'dessert' is a real corpus tag (0771-new-yorkstyle-crumb-cake).
      final result = parseSearchQuery('tag:dessert or title:cake');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const OrNode([
          TermNode(scope: SearchScope.tag, text: 'dessert'),
          TermNode(scope: SearchScope.title, text: 'cake'),
        ]),
      );
    });

    test('or of scoped phrases: title:"bundt cake" or title:pound', () {
      // 0857-rich-chocolate-bundt-cake and 0861-lemon-pound-cake.
      final result = parseSearchQuery('title:"bundt cake" or title:pound');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const OrNode([
          TermNode(
            scope: SearchScope.title,
            text: 'bundt cake',
            isPhrase: true,
          ),
          TermNode(scope: SearchScope.title, text: 'pound'),
        ]),
      );
    });

    test("'and' binds tighter than 'or': a or b and c", () {
      // Real title words: soups, "Hearty Beef and Vegetable Stew" (0006).
      final result = parseSearchQuery('soup or stew and beef');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const OrNode([
          TermNode(text: 'soup'),
          AndNode([TermNode(text: 'stew'), TermNode(text: 'beef')]),
        ]),
      );
    });

    test('chained operators flatten into one node', () {
      final and3 = parseSearchQuery('chicken and noodle and soup');
      expect(and3.errors, isEmpty);
      expect(
        and3.root,
        const AndNode([
          TermNode(text: 'chicken'),
          TermNode(text: 'noodle'),
          TermNode(text: 'soup'),
        ]),
      );

      final or3 = parseSearchQuery('soup or stew or chili');
      expect(or3.errors, isEmpty);
      expect(
        or3.root,
        const OrNode([
          TermNode(text: 'soup'),
          TermNode(text: 'stew'),
          TermNode(text: 'chili'),
        ]),
      );
    });

    test('keywords are case-insensitive', () {
      final result = parseSearchQuery('tag:dessert OR title:cake AND lemon');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const OrNode([
          TermNode(scope: SearchScope.tag, text: 'dessert'),
          AndNode([
            TermNode(scope: SearchScope.title, text: 'cake'),
            TermNode(text: 'lemon'),
          ]),
        ]),
      );
    });

    test('adjacency and explicit and mix in one group', () {
      final result = parseSearchQuery('sweet potato and soup');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const AndNode([
          TermNode(text: 'sweet'),
          TermNode(text: 'potato'),
          TermNode(text: 'soup'),
        ]),
      );
    });

    test('a quoted keyword is a phrase term, not an operator', () {
      final result = parseSearchQuery('"and"');
      expect(result.errors, isEmpty);
      expect(result.root, const TermNode(text: 'and', isPhrase: true));
    });
  });

  group('calories filter', () {
    test('calories:<400', () {
      final result = parseSearchQuery('calories:<400');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const CaloriesNode(op: CaloriesOp.lt, value: 400),
      );
    });

    test('calories: >= 300 and tag:meal', () {
      final result = parseSearchQuery('calories: >= 300 and tag:meal');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const AndNode([
          CaloriesNode(op: CaloriesOp.gte, value: 300),
          TermNode(scope: SearchScope.tag, text: 'meal'),
        ]),
      );
    });

    test('operator spacing variants all parse the same', () {
      for (final query in [
        'calories:<400',
        'calories: <400',
        'calories:< 400',
        'calories: < 400',
      ]) {
        final result = parseSearchQuery(query);
        expect(result.errors, isEmpty, reason: query);
        expect(
          result.root,
          const CaloriesNode(op: CaloriesOp.lt, value: 400),
          reason: query,
        );
      }
    });

    test('all operators, and eq as the default', () {
      const cases = {
        'calories:<250': CaloriesNode(op: CaloriesOp.lt, value: 250),
        'calories:<=250': CaloriesNode(op: CaloriesOp.lte, value: 250),
        'calories:>600': CaloriesNode(op: CaloriesOp.gt, value: 600),
        'calories:>=600': CaloriesNode(op: CaloriesOp.gte, value: 600),
        'calories:=400': CaloriesNode(op: CaloriesOp.eq, value: 400),
        'calories:400': CaloriesNode(op: CaloriesOp.eq, value: 400),
      };
      cases.forEach((query, expected) {
        final result = parseSearchQuery(query);
        expect(result.errors, isEmpty, reason: query);
        expect(result.root, expected, reason: query);
      });
    });

    test('scope name is case-insensitive for calories too', () {
      final result = parseSearchQuery('Calories:<400');
      expect(result.errors, isEmpty);
      expect(result.root, const CaloriesNode(op: CaloriesOp.lt, value: 400));
    });

    test('non-numeric value is an error, node omitted', () {
      final result = parseSearchQuery('calories:cheap');
      expect(result.root, isNull);
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('cheap'));
    });

    test('dangling operator with no number is an error', () {
      final result = parseSearchQuery('calories:<');
      expect(result.root, isNull);
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('calories'));
    });

    test('bad calories filter does not take down the rest of the query', () {
      final result = parseSearchQuery('calories:cheap and tag:dessert');
      expect(result.errors, hasLength(1));
      expect(
        result.root,
        const TermNode(scope: SearchScope.tag, text: 'dessert'),
      );
    });
  });

  group('error tolerance', () {
    test("dangling trailing 'and'", () {
      final result = parseSearchQuery('chicken and');
      expect(result.root, const TermNode(text: 'chicken'));
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains("'and'"));
    });

    test("dangling trailing 'or'", () {
      final result = parseSearchQuery('cake or');
      expect(result.root, const TermNode(text: 'cake'));
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains("'or'"));
    });

    test("leading 'or'", () {
      final result = parseSearchQuery('or cake');
      expect(result.root, const TermNode(text: 'cake'));
      expect(result.errors, hasLength(1));
    });

    test("bare operator only: 'and'", () {
      final result = parseSearchQuery('and');
      expect(result.root, isNull);
      expect(result.errors, isNotEmpty);
    });

    test("'title:' with no term is an error", () {
      final result = parseSearchQuery('title:');
      expect(result.root, isNull);
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('title'));
    });

    test('empty scope before an operator still parses the rest', () {
      final result = parseSearchQuery('title: or tag:dessert');
      expect(
        result.root,
        const TermNode(scope: SearchScope.tag, text: 'dessert'),
      );
      expect(result.errors, isNotEmpty);
      expect(result.errors.first, contains('title'));
    });

    test('unterminated quote is an error but the phrase is kept', () {
      final result = parseSearchQuery('"sweet potato');
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('quote'));
      expect(result.root, const TermNode(text: 'sweet potato', isPhrase: true));
    });

    test('empty quoted phrase is an error', () {
      final result = parseSearchQuery('""');
      expect(result.root, isNull);
      expect(result.errors, hasLength(1));
    });

    test('multiple problems all reported, best-effort AST returned', () {
      final result = parseSearchQuery('title: and calories:cheap and soup');
      expect(result.root, const TermNode(text: 'soup'));
      expect(result.errors.length, greaterThanOrEqualTo(2));
    });
  });

  group('escaped quotes', () {
    test('backslash-escaped quotes inside a phrase', () {
      // The corpus quotes terms of art like "quick-brine" (smart quotes in
      // the YAML; users type ASCII quotes and escape them).
      final result = parseSearchQuery(r'direction:"\"quick-brine\""');
      expect(result.errors, isEmpty);
      expect(
        result.root,
        const TermNode(
          scope: SearchScope.direction,
          text: '"quick-brine"',
          isPhrase: true,
        ),
      );
    });
  });

  group('corpus grounding (real data)', () {
    final dir = Directory(corpusDir);
    final available = dir.existsSync();

    String read(String name) => corpusFile(name).readAsStringSync().toLowerCase();

    test(
      'query terms used above occur in real corpus recipes',
      () {
        expect(read('0002-classic-chicken-noodle-soup.yaml'),
            contains('title: classic chicken noodle soup'));
        expect(read('0015-carrot-ginger-soup.yaml'), contains('ginger'));
        expect(read('0020-sweet-potato-soup.yaml'),
            contains('title: sweet potato soup'));
        expect(read('0857-rich-chocolate-bundt-cake.yaml'),
            contains('bundt cake'));
        expect(read('0861-lemon-pound-cake.yaml'), contains('pound cake'));
        expect(read('0771-new-yorkstyle-crumb-cake.yaml'),
            contains('- dessert'));
        expect(
            read('0077-skillet-chicken-and-rice-with-peas-and-scallions.yaml'),
            contains('fold in'));
        expect(read('0006-hearty-beef-and-vegetable-stew.yaml'),
            contains('dutch oven'));
      },
      skip: available ? false : 'recipe corpus not present on this machine',
    );
  });
}
