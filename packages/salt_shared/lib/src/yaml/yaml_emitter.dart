/// A minimal block-style YAML emitter for recipe documents.
///
/// Output follows the corpus conventions: two-space nested mappings, block
/// sequences aligned with their parent key, inline `[]`/`{}` for empty
/// collections, literal block scalars (`|-`/`|`) for multi-line strings, and
/// single quotes for strings that would otherwise read as another YAML type
/// (`'12'`, `'9781954210110'`, `'Chapter 23: A Piece of Cake'`).
library;

/// Characters that may not start a plain (unquoted) YAML scalar.
///
/// Deliberately conservative: some of these are legal in specific positions,
/// but quoting is always safe.
const String _leadingIndicators = '-?:,[]{}#&*!|>\'"%@`';

/// Words the YAML 1.1/1.2 resolvers may read as null, bool, or a special
/// float instead of a string.
const Set<String> _reservedWords = {
  '', '~', 'null', 'Null', 'NULL', //
  'true', 'True', 'TRUE', 'false', 'False', 'FALSE',
  'yes', 'Yes', 'YES', 'no', 'No', 'NO',
  'on', 'On', 'ON', 'off', 'Off', 'OFF',
  'y', 'Y', 'n', 'N',
  '.inf', '.Inf', '.INF', '-.inf', '-.Inf', '-.INF',
  '+.inf', '+.Inf', '+.INF', '.nan', '.NaN', '.NAN',
};

/// Matches strings a YAML parser would resolve as an integer or float.
final RegExp _numberLike = RegExp(
  r'^[-+]?(\.[0-9]+|[0-9][0-9_]*(\.[0-9]*)?)([eE][-+]?[0-9]+)?$',
);

/// Matches hex/octal/binary integer spellings (`0x1A`, `0o17`, `0b101`).
final RegExp _radixIntLike = RegExp(r'^[-+]?0[xob][0-9a-fA-F_]+$');

/// Matches strings PyYAML's YAML 1.1 resolver reads as a timestamp
/// (`2026-06-30`, `2001-12-14 21:59:43.10 -5`, `2001-12-14t21:59:43Z`).
/// package:yaml (1.2) keeps these as strings, but the corpus tooling reads
/// our output with PyYAML, so they must be quoted.
final RegExp _timestampLike = RegExp(
  r'^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}([Tt ].*)?$',
);

/// Matches strings PyYAML's YAML 1.1 resolver reads as a sexagesimal
/// (base-60) int or float (`1:30` → 90, `1:30:00.5`).
final RegExp _sexagesimalLike = RegExp(
  r'^[-+]?[0-9][0-9_]*(:[0-9]+)+(\.[0-9_]*)?$',
);

/// Renders [node] as a complete YAML document ending in a newline.
///
/// Supported node types are `Map` (keys are stringified), `List`, `String`,
/// `int`, `double`, `bool`, and `null`; anything else throws [ArgumentError].
/// The document is block-style throughout, matching the recipe corpus
/// convention, and always parses back (via `package:yaml`) to equal values.
String emitYamlDocument(Object? node) {
  final buffer = StringBuffer();
  if (node is Map && node.isNotEmpty) {
    _writeMap(buffer, node, 0, '');
  } else if (node is List && node.isNotEmpty) {
    _writeList(buffer, node, 0);
  } else if (node is Map) {
    buffer.writeln('{}');
  } else if (node is List) {
    buffer.writeln('[]');
  } else {
    buffer.writeln(_scalar(node, 0));
  }
  return buffer.toString();
}

/// Writes the entries of [map] at [indent]. The first entry is prefixed with
/// [firstPrefix] (a `'- '` sequence marker when the map is a list item);
/// subsequent entries use plain indentation.
void _writeMap(
  StringBuffer out,
  Map<Object?, Object?> map,
  int indent,
  String firstPrefix,
) {
  final defaultPrefix = ' ' * indent;
  var prefix = firstPrefix.isEmpty ? defaultPrefix : firstPrefix;
  for (final MapEntry<Object?, Object?> entry in map.entries) {
    final key = _key(entry.key);
    final value = entry.value;
    if (value is Map) {
      if (value.isEmpty) {
        out.writeln('$prefix$key: {}');
      } else {
        out.writeln('$prefix$key:');
        _writeMap(out, value, indent + 2, '');
      }
    } else if (value is List) {
      if (value.isEmpty) {
        out.writeln('$prefix$key: []');
      } else {
        // Corpus convention: sequences sit at the same indent as their key.
        out.writeln('$prefix$key:');
        _writeList(out, value, indent);
      }
    } else {
      out.writeln('$prefix$key: ${_scalar(value, indent + 2)}');
    }
    prefix = defaultPrefix;
  }
}

/// Writes the items of [list] as a block sequence at [indent].
void _writeList(StringBuffer out, List<Object?> list, int indent) {
  final pad = ' ' * indent;
  for (final item in list) {
    if (item is Map) {
      if (item.isEmpty) {
        out.writeln('$pad- {}');
      } else {
        _writeMap(out, item, indent + 2, '$pad- ');
      }
    } else if (item is List) {
      if (item.isEmpty) {
        out.writeln('$pad- []');
      } else {
        out.writeln('$pad-');
        _writeList(out, item, indent + 2);
      }
    } else {
      out.writeln('$pad- ${_scalar(item, indent + 2)}');
    }
  }
}

/// Renders a mapping key, which must be a single-line scalar.
String _key(Object? key) {
  final rendered = _scalar(key, 0);
  if (rendered.contains('\n')) {
    throw ArgumentError('YAML mapping keys must be single-line: $key');
  }
  return rendered;
}

/// Renders a scalar [value]. Multi-line strings return a literal block scalar
/// whose continuation lines are indented by [indent] spaces.
String _scalar(Object? value, int indent) {
  if (value == null) return 'null';
  if (value is double && !value.isFinite) {
    if (value.isNaN) return '.nan';
    return value.isNegative ? '-.inf' : '.inf';
  }
  if (value is bool || value is int || value is double) {
    return value.toString();
  }
  if (value is String) return _string(value, indent);
  throw ArgumentError(
    'Unsupported YAML scalar type ${value.runtimeType}: $value',
  );
}

/// Renders a string in the safest readable style: plain when unambiguous,
/// literal block for clean multi-line text, single-quoted otherwise, and
/// double-quoted (escaped) as the fallback for control characters or
/// unrepresentable multi-line shapes.
String _string(String text, int indent) {
  if (text.contains('\n')) return _multiline(text, indent);
  if (_isPlainSafe(text)) return text;
  if (!_hasControlChars(text)) {
    return "'${text.replaceAll("'", "''")}'";
  }
  return _doubleQuoted(text);
}

/// Renders a multi-line string as a literal block scalar (`|-` when the text
/// has no trailing newline, `|` when it has exactly one), falling back to a
/// double-quoted scalar for shapes literal style cannot represent exactly
/// (leading/trailing whitespace on lines, multiple trailing newlines,
/// control characters).
String _multiline(String text, int indent) {
  var end = text.length;
  while (end > 0 && text.codeUnitAt(end - 1) == 0x0A) {
    end--;
  }
  final trailingNewlines = text.length - end;
  final body = text.substring(0, end);
  final lines = body.split('\n');
  final blockSafe = trailingNewlines <= 1 &&
      body.isNotEmpty &&
      lines.first.isNotEmpty &&
      !lines.first.startsWith(' ') &&
      lines.every(
        (line) =>
            !_hasControlChars(line) &&
            line == line.trimRight() &&
            !line.startsWith('\t'),
      );
  if (!blockSafe) return _doubleQuoted(text);

  final pad = ' ' * indent;
  final buffer = StringBuffer(trailingNewlines == 0 ? '|-' : '|');
  for (final line in lines) {
    buffer.write('\n');
    if (line.isNotEmpty) buffer.write('$pad$line');
  }
  return buffer.toString();
}

/// Whether [text] can be emitted as a plain (unquoted) single-line scalar
/// without changing its type or content on re-parse.
bool _isPlainSafe(String text) {
  if (text.isEmpty) return false;
  if (_hasControlChars(text)) return false;
  if (text.trim() != text) return false;
  if (_leadingIndicators.contains(text[0])) return false;
  if (text.endsWith(':')) return false;
  if (text.contains(': ') || text.contains(' #')) return false;
  if (_reservedWords.contains(text)) return false;
  if (_numberLike.hasMatch(text) || _radixIntLike.hasMatch(text)) return false;
  if (_timestampLike.hasMatch(text)) return false;
  if (_sexagesimalLike.hasMatch(text)) return false;
  return true;
}

/// Whether [text] contains control characters that must force double-quoted
/// style: C0 (other than newline), DEL, C1 (including U+0085 NEL, which
/// YAML 1.1 parsers treat as a line break), or the Unicode line/paragraph
/// separators U+2028/U+2029.
bool _hasControlChars(String text) {
  for (final unit in text.codeUnits) {
    if ((unit < 0x20 && unit != 0x0A) ||
        (unit >= 0x7F && unit <= 0x9F) ||
        unit == 0x2028 ||
        unit == 0x2029) {
      return true;
    }
  }
  return false;
}

/// Renders [text] as a double-quoted scalar with YAML escapes.
String _doubleQuoted(String text) {
  final buffer = StringBuffer('"');
  for (final rune in text.runes) {
    switch (rune) {
      case 0x5C:
        buffer.write(r'\\');
      case 0x22:
        buffer.write(r'\"');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
          final hex = rune.toRadixString(16).padLeft(2, '0').toUpperCase();
          buffer.write('\\x$hex');
        } else if (rune == 0x2028 || rune == 0x2029) {
          final hex = rune.toRadixString(16).padLeft(4, '0').toUpperCase();
          buffer.write('\\u$hex');
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}
