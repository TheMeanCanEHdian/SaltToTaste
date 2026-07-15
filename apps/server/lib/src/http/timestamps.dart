/// Normalizes a stored timestamp to UTC ISO-8601 with a `Z` suffix for API
/// responses.
///
/// The database holds two spellings: DAL-written values are already
/// ISO-8601 UTC (`2026-07-15T14:03:22.123Z`), while `DEFAULT
/// (datetime('now'))` columns are SQLite's space-separated UTC form
/// (`2026-07-15 14:03:22`, no zone). docs/API.md promises ISO-8601, so the
/// SQLite form gains its `T` separator and `Z` here; null passes through.
String? isoUtc(String? stored) {
  if (stored == null) {
    return null;
  }
  if (stored.contains('T')) {
    return stored;
  }
  return '${stored.replaceFirst(' ', 'T')}Z';
}
