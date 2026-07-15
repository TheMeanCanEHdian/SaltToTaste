import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';

final Logger _log = Logger('library');

/// SHA-256 hex digest of [text] — the content-hash format stored in the
/// recipes table and compared during reconciliation.
String contentHashOfText(String text) =>
    sha256.convert(utf8.encode(text)).toString();

/// Absolute path of the canonical YAML export for a recipe.
String exportPathFor(ServerConfig config, String sourceSlug, String recipeId) =>
    '${config.libraryDir}/$sourceSlug/recipes/$recipeId.yaml';

/// Writes [content] to `<path>.tmp` and renames it over [path] so readers
/// never observe a half-written file.
void writeAtomically(String path, String content) {
  File('$path.tmp')
    ..writeAsStringSync(content, flush: true)
    ..renameSync(path);
}

/// Writes the [canonical] YAML for a recipe to its library export path,
/// preserving any unsynced hand edit first.
///
/// [previousHash] is the content hash the database held before this save —
/// i.e. the exact text the server last wrote to disk. When the on-disk file
/// exists but no longer hashes to [previousHash], someone edited it by hand
/// since the last export; the database version wins (it is being saved right
/// now), but the hand-edited text is kept alongside as
/// `<id>.conflict-<timestamp>.yaml` instead of being silently overwritten.
///
/// Returns the path of the conflict file when one was written, else null.
String? exportRecipeYaml({
  required ServerConfig config,
  required String sourceSlug,
  required String recipeId,
  required String canonical,
  String? previousHash,
}) {
  final path = exportPathFor(config, sourceSlug, recipeId);
  final file = File(path);
  file.parent.createSync(recursive: true);

  String? conflictPath;
  if (file.existsSync()) {
    final onDisk = file.readAsStringSync();
    final onDiskHash = contentHashOfText(onDisk);
    if (onDiskHash != previousHash &&
        onDiskHash != contentHashOfText(canonical)) {
      conflictPath = _conflictPathFor(path);
      writeAtomically(conflictPath, onDisk);
      _log.warning(
        'Library file $recipeId.yaml was hand-edited and also changed in the '
        'app; kept the hand edit as ${_basename(conflictPath)}',
      );
    }
  }
  writeAtomically(path, canonical);
  return conflictPath;
}

/// Removes the library export for a recipe (idempotent). Conflict copies are
/// left in place — they are the operator's data.
void deleteExport(ServerConfig config, String sourceSlug, String recipeId) {
  final file = File(exportPathFor(config, sourceSlug, recipeId));
  if (file.existsSync()) {
    file.deleteSync();
  }
}

/// `<dir>/<id>.conflict-<yyyyMMddTHHmmss>[-<n>].yaml` next to the export
/// path. Never reuses an existing path — the whole point of a conflict copy
/// is that a hand edit is never lost, including two conflicts in the same
/// second.
String _conflictPathFor(String exportPath) {
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp('[-:]'), '')
      .split('.')
      .first;
  final base = exportPath.substring(0, exportPath.length - '.yaml'.length);
  var path = '$base.conflict-$stamp.yaml';
  var suffix = 2;
  while (File(path).existsSync()) {
    path = '$base.conflict-$stamp-$suffix.yaml';
    suffix += 1;
  }
  return path;
}

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}
