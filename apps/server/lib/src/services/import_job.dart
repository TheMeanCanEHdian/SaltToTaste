import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/services/backup_service.dart';
import 'package:salt_server/src/services/import_service.dart';
import 'package:salt_server/src/services/legacy_import.dart';

final Logger _log = Logger('import');

bool _importRunning = false;

/// Whether a bulk import is currently in flight (only one at a time — the
/// job owns heavy write transactions).
bool get importJobRunning => _importRunning;

/// One detected source folder inside the import directory.
class ImportCandidate {
  /// Builds a candidate from its parts.
  const ImportCandidate({
    required this.path,
    required this.kind,
    required this.fileCount,
  });

  /// Path relative to the import directory ('.' for the directory itself).
  final String path;

  /// `v1` (Recipe Extraction root) or `legacy` (old SaltToTaste v0 root).
  final String kind;

  /// Number of recipe YAML files found.
  final int fileCount;

  /// JSON-ready form.
  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind,
    'file_count': fileCount,
  };
}

int _yamlCount(Directory dir, {required bool includeYml}) => dir
    .listSync()
    .whereType<File>()
    .where(
      (file) =>
          file.path.endsWith('.yaml') ||
          (includeYml && file.path.endsWith('.yml')),
    )
    .length;

ImportCandidate? _classify(Directory root, String relative) {
  try {
    final recipes = Directory('${root.path}/recipes');
    if (recipes.existsSync()) {
      // Count exactly what the v1 importer will read (.yaml only) — the
      // shown count and the job total must agree.
      final count = _yamlCount(recipes, includeYml: false);
      if (count > 0) {
        return ImportCandidate(path: relative, kind: 'v1', fileCount: count);
      }
    }
    if (looksLikeLegacyRoot(root.path)) {
      return ImportCandidate(
        path: relative,
        kind: 'legacy',
        fileCount: _yamlCount(
          Directory('${root.path}/_recipes'),
          includeYml: true,
        ),
      );
    }
    // An unreadable child (root-owned 700 dir in a read-only mount) must
    // not brick the whole candidates listing — skip it.
  } on FileSystemException {
    return null;
  }
  return null;
}

/// Scans the import directory (itself plus direct children) for source
/// roots the importer understands.
List<ImportCandidate> importCandidates(ServerConfig config) {
  final importDir = Directory(config.importDir);
  if (!importDir.existsSync()) {
    return const [];
  }
  final candidates = <ImportCandidate>[
    ?_classify(importDir, '.'),
  ];
  final List<Directory> children;
  try {
    children = importDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  } on FileSystemException {
    return candidates; // Unreadable import dir: no children to offer.
  }
  for (final child in children) {
    final name = child.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
      orElse: () => '',
    );
    final candidate = _classify(child, name);
    if (candidate != null) {
      candidates.add(candidate);
    }
  }
  return candidates;
}

/// Resolves a client-supplied [path] (relative to the import directory, or
/// absolute) and asserts it canonicalizes INSIDE the import directory —
/// the admin-configured allowlist root. Throws [ValidationException]
/// otherwise.
String resolveImportPath(ServerConfig config, String path) {
  // No character-class filtering: the real corpus root name contains
  // spaces. Canonical containment below is the security boundary.
  if (path.isEmpty) {
    throw const ValidationException("'path' must be a folder name.");
  }
  final base = path.startsWith('/') ? path : '${config.importDir}/$path';
  // Lexical containment BEFORE any filesystem access: an outside path is
  // rejected without touching the disk, so the error messages below can
  // never act as an existence oracle for arbitrary host paths.
  if (!_lexicallyInside(base, config.importDir)) {
    throw const ValidationException(
      'Only folders inside the import directory can be imported.',
    );
  }
  final String canonical;
  final String canonicalRoot;
  try {
    canonical = Directory(base).resolveSymbolicLinksSync();
    canonicalRoot = Directory(config.importDir).resolveSymbolicLinksSync();
  } on FileSystemException {
    throw const ValidationException(
      'That folder does not exist inside the import directory.',
    );
  }
  if (canonical != canonicalRoot && !canonical.startsWith('$canonicalRoot/')) {
    // Containment is the security boundary: no probing outside the
    // allowlist root, whatever the input looks like.
    throw const ValidationException(
      'Only folders inside the import directory can be imported.',
    );
  }
  return canonical;
}

/// Whether [path], after folding `.`/`..` segments lexically, sits at or
/// under [root]. No filesystem access.
bool _lexicallyInside(String path, String root) {
  List<String> fold(String value) {
    final out = <String>[];
    for (final segment in value.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (out.isEmpty) {
          return const [];
        }
        out.removeLast();
      } else {
        out.add(segment);
      }
    }
    return out;
  }

  final target = fold(path);
  final base = fold(root);
  if (target.length < base.length) {
    return false;
  }
  for (var i = 0; i < base.length; i++) {
    if (target[i] != base[i]) {
      return false;
    }
  }
  return true;
}

/// Starts a background import of [path] (already resolved by
/// [resolveImportPath]); returns the job id, or null when an import is
/// already running.
///
/// The work runs in [Isolate.run] with its own database connection (WAL
/// allows the concurrent writer; interactive requests keep their latency),
/// updating the `import_jobs` row as it goes. Failures land in the job —
/// silent partial failure is prohibited.
int? startImportJob(
  SaltDatabase db,
  ServerConfig config, {
  required String path,
}) {
  if (_importRunning) {
    return null;
  }
  final legacy = looksLikeLegacyRoot(path);
  // Changed source files overwrite hand-tuned recipes and their exported
  // YAML directly, so the documented safety net must actually exist: one
  // backup before any of that starts (review B10 — API.md promised this
  // and nothing took it).
  createBackup(db: db, config: config, trigger: 'before-import');
  final jobId = db.createImportJob(sourcePath: path, legacy: legacy);
  _importRunning = true;
  unawaited(
    _run(
      db,
      config,
      jobId: jobId,
      path: path,
      legacy: legacy,
    ).whenComplete(() => _importRunning = false),
  );
  return jobId;
}

Future<void> _run(
  SaltDatabase db,
  ServerConfig config, {
  required int jobId,
  required String path,
  required bool legacy,
}) async {
  try {
    await Isolate.run(
      () => _importInIsolate(
        config: config,
        jobId: jobId,
        path: path,
        legacy: legacy,
      ),
    );
    _log.info('Import job $jobId finished');
    // The isolate records its own failure when it can; this is the
    // backstop for errors before/outside it (spawn failure, DB open).
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    _log.severe('Import job $jobId crashed', error, stackTrace);
    db.finishImportJob(
      jobId,
      status: 'failed',
      total: 0,
      done: 0,
      imported: 0,
      updated: 0,
      skipped: 0,
      failed: 0,
      logJson: jsonEncode(['import crashed: $error']),
    );
  }
}

/// Isolate entry: opens its own connection, runs the importer with
/// throttled progress writes, records the terminal summary.
void _importInIsolate({
  required ServerConfig config,
  required int jobId,
  required String path,
  required bool legacy,
}) {
  final db = SaltDatabase.open(config.dbPath);
  try {
    var lastWritten = DateTime.now();
    void onProgress(int done, int total) {
      final now = DateTime.now();
      if (done == total ||
          now.difference(lastWritten) > const Duration(milliseconds: 400)) {
        lastWritten = now;
        db.updateImportJobProgress(jobId, done: done, total: total);
      }
    }

    final ImportSummary summary;
    try {
      summary = legacy
          ? importLegacyRoot(
              sourceRootPath: path,
              db: db,
              config: config,
              onProgress: onProgress,
            )
          : importSourceRoot(
              sourceRootPath: path,
              db: db,
              config: config,
              onProgress: onProgress,
            );
      // Whatever the importer throws must become a failed JOB, visible to
      // the polling UI — not a silent isolate death.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      db.finishImportJob(
        jobId,
        status: 'failed',
        total: 0,
        done: 0,
        imported: 0,
        updated: 0,
        skipped: 0,
        failed: 0,
        logJson: jsonEncode(['$error']),
      );
      return;
    }
    // Cap the persisted log: a huge legacy import can emit warnings per
    // file, and the polling UI re-downloads the whole array.
    const logCap = 500;
    final overflow = summary.warnings.length - logCap;
    final overflowNote =
        '… and $overflow more warning(s); see the server log for the '
        'full list';
    final warnings = summary.warnings.length <= logCap
        ? summary.warnings
        : [...summary.warnings.take(logCap), overflowNote];
    db.finishImportJob(
      jobId,
      status: 'done',
      total: summary.total,
      done: summary.total,
      imported: summary.imported,
      updated: summary.updated,
      skipped: summary.skipped,
      failed: summary.failed,
      logJson: jsonEncode(warnings),
    );
  } finally {
    db.dispose();
  }
}
