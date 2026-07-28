import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/util/timestamps.dart';

/// Server timestamps must display in the VIEWER's local zone (review B18) —
/// they were once shown verbatim (machine strings) or with the `Z` stripped
/// (UTC clock passed off as local). Synthesized inputs: wire timestamps
/// cannot come from the recipe corpus.
void main() {
  test('a UTC wire timestamp renders as the local clock', () {
    const wire = '2026-07-28T03:31:58.123Z';
    final local = DateTime.parse(wire).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    expect(
      formatTimestamp(wire),
      '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}',
    );
    expect(
      formatClock(wire),
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}',
    );
    // The raw machine string must never reach the screen.
    expect(formatTimestamp(wire), isNot(contains('T')));
    expect(formatTimestamp(wire), isNot(contains('Z')));
  });

  test('unparseable input comes back verbatim, never blank', () {
    expect(formatTimestamp('not a time'), 'not a time');
    expect(formatClock('not a time'), 'not a time');
  });
}
