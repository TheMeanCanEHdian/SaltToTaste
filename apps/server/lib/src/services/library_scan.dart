import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:yaml/yaml.dart' show loadYaml;

final Logger _log = Logger('library');

/// Settings-table key holding the JSON of the last [ScanReport].
const String lastScanSettingKey = 'library.last_scan';

/// The exact file-name shape `exportRecipeYaml` gives conflict copies.
final RegExp _conflictCopyName = RegExp(
  r'\.conflict-\d{8}T\d{6}(-\d+)?\.yaml$',
);

/// Outcome of one library reconciliation scan.
///
/// The scan makes the database and the exported YAML library agree again
/// after hand edits: a cleanly edited file wins (it is imported and
/// re-exported in canonical form), a malformed file loses (the database
/// version stays and the problem is reported), and a missing export is
/// re-materialized from the database. Save-time conflicts are handled at
/// save time (`exportRecipeYaml` keeps the hand edit as a `.conflict-*`
/// copy); the scan lists any such copies still on disk so the UI can
/// surface them.
class ScanReport {
  /// Creates an empty report; [scanLibrary] fills it in.
  ScanReport({required this.startedAt});

  /// When the scan started (UTC).
  final DateTime startedAt;

  /// Wall-clock duration.
  int elapsedMs = 0;

  /// YAML files considered.
  int filesSeen = 0;

  /// Recipe ids whose file was hand-edited and imported (file won).
  final List<String> updatedFromDisk = [];

  /// Recipe ids imported from files that had no database row yet.
  final List<String> added = [];

  /// Recipe ids whose export file was missing and rewritten from the
  /// database.
  final List<String> reExported = [];

  /// Files that could not be imported, with the reason (malformed YAML,
  /// id mismatch, ...). The database version stays authoritative.
  final List<({String file, String reason})> skipped = [];

  /// `.conflict-*.yaml` copies present in the library — hand edits that
  /// lost to an in-app save and await operator review.
  final List<String> conflictFiles = [];

  /// JSON shape stored in settings and returned by the library endpoints.
  Map<String, Object?> toJson() => {
    'started_at': startedAt.toIso8601String(),
    'elapsed_ms': elapsedMs,
    'files_seen': filesSeen,
    'updated_from_disk': updatedFromDisk,
    'added': added,
    're_exported': reExported,
    'skipped': [
      for (final entry in skipped) {'file': entry.file, 'reason': entry.reason},
    ],
    'conflict_files': conflictFiles,
  };

  /// One-line log summary.
  @override
  String toString() =>
      '$filesSeen file(s): ${updatedFromDisk.length} updated from disk, '
      '${added.length} added, ${reExported.length} re-exported, '
      '${skipped.length} skipped, ${conflictFiles.length} conflict file(s)';
}

/// Reconciles the YAML library under `config.libraryDir` with the database
/// and persists the report (see [ScanReport] for the rules).
ScanReport scanLibrary({
  required SaltDatabase db,
  required ServerConfig config,
}) {
  final report = ScanReport(startedAt: DateTime.now().toUtc());
  final stopwatch = Stopwatch()..start();
  final root = Directory(config.libraryDir);

  final seenIds = <String>{};
  if (root.existsSync()) {
    final sourceDirs = root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final sourceDir in sourceDirs) {
      _scanSourceDir(db, report, sourceDir, seenIds);
    }
  }

  // Self-heal: re-export any recipe whose library file disappeared.
  for (final row in db.listRecipeHashes()) {
    if (seenIds.contains(row.id)) {
      continue;
    }
    final found = db.recipeByIdOrSlug(row.id);
    if (found == null) {
      continue;
    }
    exportRecipeYaml(
      config: config,
      sourceSlug: row.sourceSlug,
      recipeId: row.id,
      canonical: RecipeYamlCodec.encode(found.recipe),
      previousHash: row.contentHash,
    );
    report.reExported.add(row.id);
  }

  report.elapsedMs = stopwatch.elapsedMilliseconds;
  db.setSetting(lastScanSettingKey, jsonEncode(report.toJson()));
  _log.info('Library scan: $report');
  return report;
}

/// The last persisted scan report as JSON, or null before the first scan.
Map<String, Object?>? lastScanReport(SaltDatabase db) {
  final raw = db.getSetting(lastScanSettingKey);
  if (raw == null) {
    return null;
  }
  return jsonDecode(raw) as Map<String, Object?>;
}

void _scanSourceDir(
  SaltDatabase db,
  ScanReport report,
  Directory sourceDir,
  Set<String> seenIds,
) {
  final sourceSlug = _basename(sourceDir.path);
  final recipesDir = Directory('${sourceDir.path}/recipes');
  if (!recipesDir.existsSync()) {
    return;
  }
  var sourceRowEnsured = false;
  final files =
      recipesDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final fileName = _basename(file.path);
    // Only the exact shape exportRecipeYaml generates counts as a conflict
    // copy — a substring test would misclassify a recipe whose *id* happens
    // to contain ".conflict-" forever.
    if (_conflictCopyName.hasMatch(fileName)) {
      report.conflictFiles.add('$sourceSlug/recipes/$fileName');
      continue;
    }
    if (fileName.endsWith('.tmp')) {
      continue;
    }
    report.filesSeen += 1;
    final id = fileName.substring(0, fileName.length - '.yaml'.length);
    if (!isSafeRecipeId(id)) {
      report.skipped.add(
        (file: '$sourceSlug/recipes/$fileName', reason: 'unsafe file name'),
      );
      continue;
    }
    if (!seenIds.add(id)) {
      // The same recipe id in two source directories would make the copies
      // fight over the database row on every scan — refuse the later one.
      report.skipped.add(
        (
          file: '$sourceSlug/recipes/$fileName',
          reason:
              'duplicate id "$id" — already scanned in another '
              'source directory',
        ),
      );
      continue;
    }

    final text = file.readAsStringSync();
    final storedHash = db.contentHashOf(id);
    if (storedHash != null && contentHashOfText(text) == storedHash) {
      continue; // In sync — the overwhelmingly common case.
    }

    // New or hand-edited file: the file wins if it decodes cleanly.
    final Recipe recipe;
    try {
      final decoded = RecipeYamlCodec.decode(text);
      recipe = decoded.recipe;
    } on Exception catch (error) {
      report.skipped.add(
        (
          file: '$sourceSlug/recipes/$fileName',
          reason: 'not importable: ${_firstLine(error)}',
        ),
      );
      continue;
    }
    if (recipe.id != id) {
      report.skipped.add(
        (
          file: '$sourceSlug/recipes/$fileName',
          reason: 'document id "${recipe.id}" does not match the file name',
        ),
      );
      continue;
    }

    if (!sourceRowEnsured) {
      _ensureSourceRow(db, sourceDir, sourceSlug);
      sourceRowEnsured = true;
    }
    // Resolve slug collisions BEFORE encoding, so the normalized file, the
    // content hash, and the stored document all carry the same slug.
    final stored = recipe.copyWith(
      slug: db.availableSlug(recipe.slug, ownerId: recipe.id),
    );
    final canonical = RecipeYamlCodec.encode(stored);
    db.upsertRecipe(
      stored,
      sourceSlug: sourceSlug,
      contentHash: contentHashOfText(canonical),
    );
    // Normalize the hand edit back to canonical form (idempotent when the
    // edit already was canonical).
    if (canonical != text) {
      writeAtomically(file.path, canonical);
    }
    (storedHash == null ? report.added : report.updatedFromDisk).add(id);
  }
}

/// Guarantees the sources row a scanned recipe references exists, taking
/// identity from the directory's `source.yaml` when present. An existing
/// row is left untouched — the scan must not overwrite a real source name
/// with directory-derived fallback identity.
void _ensureSourceRow(
  SaltDatabase db,
  Directory sourceDir,
  String sourceSlug,
) {
  if (db.sourceExists(sourceSlug)) {
    return;
  }
  var name = sourceSlug;
  var type = 'manual';
  final meta = <String, Object?>{};
  final sourceYaml = File('${sourceDir.path}/source.yaml');
  if (sourceYaml.existsSync()) {
    try {
      final doc = yamlToPlain(loadYaml(sourceYaml.readAsStringSync()));
      if (doc is Map<String, Object?>) {
        name = (doc['name']?.toString().trim()).orWhenEmpty(name);
        type = (doc['type']?.toString().trim()).orWhenEmpty(type);
        for (final entry in doc.entries) {
          if (entry.key != 'name' && entry.key != 'type') {
            meta[entry.key] = entry.value;
          }
        }
      }
    } on Exception {
      // A broken source.yaml falls back to directory-name identity.
    }
  }
  db.upsertSource(slug: sourceSlug, name: name, type: type, meta: meta);
}

extension on String? {
  String orWhenEmpty(String fallback) {
    final value = this;
    return (value == null || value.isEmpty) ? fallback : value;
  }
}

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

String _firstLine(Object error) => '$error'.split('\n').first;
