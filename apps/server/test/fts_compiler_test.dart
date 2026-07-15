import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/search/fts_compiler.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

CompiledSearch _compile(String query) {
  final result = parseSearchQuery(query);
  expect(result.errors, isEmpty, reason: 'parse errors for "$query"');
  return compileSearch(result.root!);
}

void main() {
  group('compileSearch', () {
    test('scoped terms become column-filtered phrases', () {
      expect(
        _compile('title:chicken and ingredient:ginger').ftsMatch,
        '(title:"chicken" AND ingredients:"ginger")',
      );
    });

    test('general words search all columns; adjacency is AND', () {
      expect(_compile('sweet potato').ftsMatch, '("sweet" AND "potato")');
    });

    test('a scope binds exactly one term (decided semantics)', () {
      // 2026-07-14 user decision: the word after the scoped term is a
      // general term, NOT title-scoped. A parser refactor must not regress
      // this silently.
      expect(
        _compile('title:chicken soup').ftsMatch,
        '(title:"chicken" AND "soup")',
      );
    });

    test('separator-only terms are dropped as noise, not ANDed to nothing',
        () {
      expect(
        _compile('chicken , soup').ftsMatch,
        '("chicken" AND "soup")',
        reason: 'a stray comma token must not zero out the query',
      );
      expect(_compile('mac & cheese').ftsMatch, '("mac" AND "cheese")');
      // A query that is ONLY noise compiles to no match at all (the
      // handler then falls back to the plain listing).
      expect(_compile('&').ftsMatch, isNull);
    });

    test('control characters in a term are rejected as validation', () {
      expect(
        () => _compile('a\u0000b'),
        throwsA(isA<ValidationException>()),
        reason: 'NUL reaches FTS5 as an unterminated string -> opaque 500',
      );
    });

    test('quoted phrases stay single phrases', () {
      expect(_compile('"sweet potato" soup').ftsMatch,
          '("sweet potato" AND "soup")');
      expect(_compile('title:"bundt cake" or title:pound').ftsMatch,
          '(title:"bundt cake" OR title:"pound")');
    });

    test('or/and precedence carries into the match expression', () {
      expect(
        _compile('tag:dessert or title:cake and title:easy').ftsMatch,
        '(tags:"dessert" OR (title:"cake" AND title:"easy"))',
      );
    });

    test('MATCH syntax cannot be injected through terms', () {
      // A hostile term full of FTS operators compiles to a quoted literal.
      final compiled = _compile('title:"NEAR(a b) OR c*"');
      expect(compiled.ftsMatch, 'title:"NEAR(a b) OR c*"');

      // A stray quote splits the term at tokenization; both halves still
      // compile to quoted literals (never raw MATCH syntax).
      final quotes = parseSearchQuery('pa"prika');
      final match = compileSearch(quotes.root!).ftsMatch;
      expect(match, '("pa" AND "prika")');
    });

    test('calories filters collect and force calorie ordering', () {
      final compiled = _compile('calories:<400 and tag:dessert');
      expect(compiled.ftsMatch, 'tags:"dessert"');
      expect(compiled.calories, hasLength(1));
      expect(compiled.calories.single.op, CaloriesOp.lt);
      expect(compiled.calories.single.value, 400);
      expect(compiled.orderByCalories, isTrue);
    });

    test('pure calories query has no MATCH expression', () {
      final compiled = _compile('calories:<=300');
      expect(compiled.ftsMatch, isNull);
      expect(compiled.calories.single.op, CaloriesOp.lte);
    });

    test('calories under OR is rejected as validation', () {
      expect(
        () => _compile('title:cake or calories:<300'),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
