/// Shared plumbing for the cross-package API contract goldens.
///
/// The goldens are committed JSON bodies captured from the REAL server
/// routes (see `test/contract_golden_test.dart`) and re-parsed by the REAL
/// Flutter app models (`apps/app/test/contract_golden_parse_test.dart`).
/// They live under `packages/salt_shared/` so neither side owns the
/// contract; both packages reach them at the same relative path from their
/// own package root, which is the working directory of `dart test` and
/// `flutter test`.
///
/// Regenerate after an INTENTIONAL response-shape change:
///
/// ```sh
/// cd apps/server
/// SALT_CORPUS_DIR="<corpus root>" UPDATE_CONTRACT_GOLDENS=1 \
///   dart test test/contract_golden_test.dart
/// ```
///
/// then review the diff — every changed byte is a change the Flutter app
/// has to agree with.
library;

import 'dart:convert';
import 'dart:io';

/// Directory holding the committed goldens, relative to a package root.
const String contractFixturesDir =
    '../../packages/salt_shared/test/fixtures/contract';

/// The committed golden file for [name] (without the `.json` suffix).
File contractGoldenFile(String name) => File('$contractFixturesDir/$name.json');

/// Goldens whose bodies need NO corpus data: the auth surface, plus
/// everything derived from the real legacy-v0 recipe committed at
/// `apps/server/test/fixtures/legacy-v0/`. These are generated and compared
/// on every run, CI included — which is the point, since a server-side key
/// rename is otherwise invisible to a CI that only re-parses static files.
const List<String> corpusFreeContractGoldenNames = [
  'auth_login_admin',
  'auth_login_must_change',
  'auth_me_admin',
  'auth_me_must_change',
  'auth_change_password',
  'tags_unstyled',
  'tags_styled',
  'recipes_page',
  'recipes_search',
  'recipe_detail',
  'nutrition_matches_uncomputed',
];

/// Goldens that genuinely need the ATK corpus: a real v1 import source (with
/// its `source.yaml` and hero images), a reconciliation scan over it, a
/// nutrition compute whose FDC responses were recorded against those exact
/// ingredient lines, and the bulk-scope counts over that library once one of
/// its computed recipes has gone stale.
const List<String> corpusBackedContractGoldenNames = [
  'import_candidates',
  'import_job',
  'library_last_scan',
  'nutrition',
  'nutrition_matches',
  'nutrition_review',
  'nutrition_bulk_counts',
];

/// Every golden this contract covers. The server test writes/compares all of
/// them; the ungated presence check and the app-side parse test read from the
/// same list, so adding a golden in one place cannot silently leave the other
/// side untested.
const List<String> contractGoldenNames = [
  ...corpusFreeContractGoldenNames,
  ...corpusBackedContractGoldenNames,
];

/// Whether this run should REWRITE the goldens instead of asserting against
/// them (`UPDATE_CONTRACT_GOLDENS=1`).
bool get updateContractGoldens =>
    Platform.environment['UPDATE_CONTRACT_GOLDENS'] == '1';

const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

/// Renders [body] exactly as it is stored on disk: two-space indented JSON
/// in the server's own key order, one trailing newline.
String encodeContractGolden(Object? body) => '${_encoder.convert(body)}\n';

/// Response values that legitimately differ run to run (opaque tokens,
/// timestamps, temp-directory paths, wall-clock durations), mapped to a
/// stable stand-in.
///
/// The stand-in also DECLARES the JSON type the key must carry: a live value
/// of a different runtime type is not redacted but replaced with a marker
/// naming both types, so the golden comparison fails. (Without that, an
/// `elapsed_ms` that turned into a string — or a `started_at` that turned
/// into an epoch int, which `LibraryRepository` casts to `String?` — would
/// pass green.)
///
/// Only the VALUE is replaced — the key stays, so a renamed or dropped key
/// still fails the comparison, which is the whole point of the pin. Nulls
/// are left alone: `"finished_at": null` is a real state the app parses.
const Map<String, Object> contractVolatileFields = {
  'token': '<token>',
  'started_at': '<timestamp>',
  'finished_at': '<timestamp>',
  'computed_at': '<timestamp>',
  'cached_at': '<timestamp>',
  'candidates_cached_at': '<timestamp>',
  'created_at': '<timestamp>',
  'last_seen_at': '<timestamp>',
  'last_active_at': '<timestamp>',
  'import_dir': '<path>',
  'source_path': '<path>',
  'elapsed_ms': 0,
};

/// The stand-in written in place of [value] under [key], or a type-mismatch
/// marker when the live value is not the type the stand-in declares.
Object _contractStandIn(String key, Object value) {
  final standIn = contractVolatileFields[key]!;
  if (value.runtimeType == standIn.runtimeType) {
    return standIn;
  }
  return '<$key: expected ${standIn.runtimeType}, '
      'got ${value.runtimeType}>';
}

/// Replaces every [contractVolatileFields] value inside [value] (recursing
/// through maps and lists) with its stable stand-in.
Object? redactContractVolatiles(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}':
            entry.value != null &&
                contractVolatileFields.containsKey('${entry.key}')
            ? _contractStandIn('${entry.key}', entry.value as Object)
            : redactContractVolatiles(entry.value),
    };
  }
  if (value is List) {
    return [for (final entry in value) redactContractVolatiles(entry)];
  }
  return value;
}
