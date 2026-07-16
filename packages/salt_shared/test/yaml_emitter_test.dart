import 'package:salt_shared/src/yaml/yaml_emitter.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'corpus.dart';

/// Deep-converts YamlMap/YamlList to plain Dart collections for comparison.
Object? _plain(Object? node) {
  if (node is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> e in node.entries)
        e.key.toString(): _plain(e.value),
    };
  }
  if (node is List) {
    return <Object?>[for (final Object? item in node) _plain(item)];
  }
  return node;
}

bool _deepEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final Object? key in a.keys) {
      if (!b.containsKey(key) || !_deepEqual(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Asserts that [value] survives emit -> package:yaml parse unchanged.
void expectRoundTrip(Object? value) {
  final emitted = emitYamlDocument({'v': value});
  final Object? reparsed = _plain(loadYaml(emitted));
  expect(
    _deepEqual(reparsed, {'v': value}),
    isTrue,
    reason: 'round-trip changed value.\nemitted:\n$emitted\ngot: $reparsed',
  );
}

void main() {
  group('scalar quoting', () {
    test('strings that look like other YAML types stay strings', () {
      for (final tricky in [
        '12',
        '9781954210110',
        '1.5',
        '-3',
        '+7',
        '0x1A',
        '0o17',
        '0b101',
        'null',
        'Null',
        '~',
        'true',
        'False',
        'yes',
        'NO',
        'on',
        'Off',
        'y',
        'N',
        '.inf',
        '-.Inf',
        '.nan',
        '',
        ' leading',
        'trailing ',
        '- dash',
        '? question',
        ': colon',
        '#hash-adjacent nope # comment',
        'Chapter 23: A Piece of Cake',
        'ends with colon:',
        'flow, indicators',
        '[brackets]',
        '{braces}',
      ]) {
        expectRoundTrip(tricky);
      }
    });

    test('PyYAML 1.1 date and sexagesimal forms are quoted', () {
      // package:yaml keeps these as strings either way; the quotes exist so
      // PyYAML (which resolves dates and base-60 ints) also reads strings.
      for (final tricky in [
        '2026-06-30',
        '2001-12-14 21:59:43.10 -5',
        '2001-12-14t21:59:43Z',
        '1:30',
        '1:30:00',
        '-1:20.5',
      ]) {
        expectRoundTrip(tricky);
        final emitted = emitYamlDocument({'v': tricky});
        expect(
          emitted.trim(),
          "v: '$tricky'",
          reason: '$tricky must be quoted for PyYAML compatibility',
        );
      }
    });

    test('unicode passes through verbatim', () {
      for (final text in ['½ cup', 'crème brûlée', 'let’s cook', '2001–2023']) {
        expectRoundTrip(text);
        expect(emitYamlDocument({'v': text}), contains(text));
      }
    });

    test('control characters force escaped double-quoted style', () {
      for (final (text, control, escape) in [
        ('foo\u0085bar', 0x85, r'\x85'), // NEL: a line break to YAML 1.1
        ('foo\u2028bar', 0x2028, r'\u2028'),
        ('foo\u2029bar', 0x2029, r'\u2029'),
        ('bell\u0007', 0x07, r'\x07'),
        ('c1\u009Fend', 0x9F, r'\x9F'),
      ]) {
        expectRoundTrip(text);
        final emitted = emitYamlDocument({'v': text});
        expect(
          emitted,
          contains(escape),
          reason: 'control char ($escape case) must be escaped, not raw',
        );
        expect(
          emitted.runes.contains(control),
          isFalse,
          reason:
              'raw control character U+'
              '${control.toRadixString(16)} leaked into output',
        );
      }
    });

    test('non-finite doubles use YAML spellings and round-trip as doubles', () {
      expect(emitYamlDocument({'v': double.infinity}).trim(), 'v: .inf');
      expect(
        emitYamlDocument({'v': double.negativeInfinity}).trim(),
        'v: -.inf',
      );
      expect(emitYamlDocument({'v': double.nan}).trim(), 'v: .nan');

      final YamlMap inf =
          loadYaml(emitYamlDocument({'v': double.infinity})) as YamlMap;
      expect(inf['v'], double.infinity);
      final YamlMap nan =
          loadYaml(emitYamlDocument({'v': double.nan})) as YamlMap;
      expect((nan['v'] as double).isNaN, isTrue);
    });
  });

  group('multi-line strings', () {
    test('literal blocks round-trip, including blank interior lines', () {
      expectRoundTrip('one\ntwo');
      expectRoundTrip('paragraph one.\n\nparagraph two.');
      expectRoundTrip('ends with newline\n');
      expectRoundTrip('two trailing\n\n');
      expectRoundTrip('\nleading newline');
      expectRoundTrip('line with trailing space \nnext');
    });
  });

  group('document shapes (public API)', () {
    test('nested collections round-trip', () {
      final doc = {
        'list_of_lists': [
          ['a', 'b'],
          <Object?>[],
        ],
        'list_of_maps': [
          {'k': 'v'},
          <String, Object?>{},
        ],
        'empty_map': <String, Object?>{},
        'empty_list': <Object?>[],
        'nested': {
          'deep': {
            'items': [1, 2.5, true, null, 'six'],
          },
        },
      };
      final Object? reparsed = _plain(loadYaml(emitYamlDocument(doc)));
      expect(
        _deepEqual(reparsed, doc),
        isTrue,
        reason: 'emitted:\n${emitYamlDocument(doc)}\ngot: $reparsed',
      );
    });

    test('non-map roots round-trip', () {
      for (final Object? root in [
        ['a', 'b', 3],
        'bare scalar',
        42,
        null,
        <String, Object?>{},
        <Object?>[],
      ]) {
        final Object? reparsed = _plain(loadYaml(emitYamlDocument(root)));
        expect(_deepEqual(reparsed, root), isTrue, reason: 'root: $root');
      }
    });
  });

  group('corpus grounding (real data)', skip: skipIfNoCorpus, () {
    test('real corpus documents survive parse -> emit -> parse', () {
      for (final name in [
        '0857-rich-chocolate-bundt-cake.yaml',
        '0020-sweet-potato-soup.yaml',
        '0038-foolproof-vinaigrette.yaml',
      ]) {
        final Object? original = _plain(
          loadYaml(corpusFile(name).readAsStringSync()),
        );
        final Object? reparsed = _plain(loadYaml(emitYamlDocument(original)));
        expect(_deepEqual(reparsed, original), isTrue, reason: name);
      }
    });
  });
}
