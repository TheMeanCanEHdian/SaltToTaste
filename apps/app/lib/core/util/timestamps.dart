/// Server-timestamp display helpers (review B18).
///
/// The API's convention is UTC ISO-8601 with a `Z` suffix. Several surfaces
/// once printed those machine strings verbatim ("last used
/// 2026-07-27T14:05:33.123Z") or formatted them while dropping the `Z` —
/// showing the UTC clock as if it were local, hours off for any viewer not
/// on UTC. Everything user-facing goes through here instead: parse, convert
/// to the VIEWER's local zone, format readably.
library;

/// "2026-07-28T03:31:58Z" viewed from UTC-4 → "2026-07-27 23:31:58".
///
/// Unparseable input comes back verbatim — better an odd-looking string
/// than a blank. A zone-less timestamp (old stored log lines predate the
/// UTC fix) parses as local and displays unshifted.
String formatTimestamp(String raw) {
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) {
    return raw;
  }
  final local = parsed.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

/// The clock part only, local ("23:31:58") — for the dense log table.
String formatClock(String raw) {
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) {
    return raw;
  }
  final local = parsed.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
