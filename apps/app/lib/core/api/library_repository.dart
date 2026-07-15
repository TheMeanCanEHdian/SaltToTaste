import 'package:dio/dio.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException, absoluteApiUrl, apiGuard;

/// The report of a library reconciliation scan, as the server persists it.
class LibraryScanReport {
  const LibraryScanReport({
    required this.startedAt,
    required this.elapsedMs,
    required this.filesSeen,
    required this.updatedFromDisk,
    required this.added,
    required this.reExported,
    required this.skipped,
    required this.conflictFiles,
  });

  factory LibraryScanReport.fromJson(Map<String, dynamic> json) =>
      LibraryScanReport(
        startedAt: json['started_at'] as String? ?? '',
        elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
        filesSeen: (json['files_seen'] as num?)?.toInt() ?? 0,
        updatedFromDisk: _strings(json['updated_from_disk']),
        added: _strings(json['added']),
        reExported: _strings(json['re_exported']),
        skipped: [
          if (json['skipped'] is List)
            for (final entry in json['skipped'] as List<dynamic>)
              (
                file: (entry as Map<String, dynamic>)['file'] as String? ?? '',
                reason: entry['reason'] as String? ?? '',
              ),
        ],
        conflictFiles: _strings(json['conflict_files']),
      );

  final String startedAt;
  final int elapsedMs;
  final int filesSeen;

  /// Recipe ids whose hand-edited file won and was imported.
  final List<String> updatedFromDisk;

  /// Recipe ids imported from brand-new files.
  final List<String> added;

  /// Recipe ids whose missing export was rewritten from the database.
  final List<String> reExported;

  /// Files that could not be imported, with reasons (database kept).
  final List<({String file, String reason})> skipped;

  /// Outstanding `.conflict-*` copies awaiting operator review.
  final List<String> conflictFiles;

  /// Whether the scan found nothing to do and nothing to warn about.
  bool get clean =>
      updatedFromDisk.isEmpty &&
      added.isEmpty &&
      reExported.isEmpty &&
      skipped.isEmpty &&
      conflictFiles.isEmpty;

  static List<String> _strings(Object? raw) =>
      [if (raw is List) for (final entry in raw) entry.toString()];
}

/// One backup archive on the server.
class BackupItem {
  const BackupItem({
    required this.name,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String name;
  final int sizeBytes;
  final String createdAt;
}

/// Admin access to the library (reconciliation) and backups API.
class LibraryRepository {
  LibraryRepository(this._dio);

  final Dio _dio;

  /// The last scan report, or null before any scan has run.
  Future<LibraryScanReport?> lastScan() {
    return apiGuard(() async {
      final data = _asMap((await _dio.get<dynamic>('/api/v1/library')).data);
      final report = data['last_scan'];
      return report is Map<String, dynamic>
          ? LibraryScanReport.fromJson(report)
          : null;
    });
  }

  /// Runs a reconciliation scan now and returns its report.
  Future<LibraryScanReport> rescan() {
    return apiGuard(() async {
      final data = _asMap(
        (await _dio.post<dynamic>(
          '/api/v1/library/rescan',
          // A large hand-edited library can take a while to reconcile.
          options: Options(receiveTimeout: const Duration(minutes: 5)),
        ))
            .data,
      );
      return LibraryScanReport.fromJson(
        data['last_scan']! as Map<String, dynamic>,
      );
    });
  }

  /// All backups, newest first.
  Future<List<BackupItem>> listBackups() {
    return apiGuard(() async {
      final data = _asMap((await _dio.get<dynamic>('/api/v1/backups')).data);
      return [
        if (data['items'] is List)
          for (final raw in data['items'] as List<dynamic>)
            BackupItem(
              name: (raw as Map<String, dynamic>)['name']! as String,
              sizeBytes: (raw['size_bytes']! as num).toInt(),
              createdAt: raw['created_at']! as String,
            ),
      ];
    });
  }

  /// Creates a backup now; [includeImages] makes it a full copy.
  Future<BackupItem> createBackup({bool includeImages = false}) {
    return apiGuard(() async {
      final data = _asMap(
        (await _dio.post<dynamic>(
          '/api/v1/backups',
          data: {'include_images': includeImages},
          // A full include-photos archive is ~0.5 GB of tar+gzip work.
          options: Options(receiveTimeout: const Duration(minutes: 10)),
        ))
            .data,
      );
      final raw = data['backup']! as Map<String, dynamic>;
      return BackupItem(
        name: raw['name']! as String,
        sizeBytes: (raw['size_bytes']! as num).toInt(),
        createdAt: raw['created_at']! as String,
      );
    });
  }

  /// Deletes the named backup.
  Future<void> deleteBackup(String name) {
    return apiGuard(() async {
      await _dio
          .delete<dynamic>('/api/v1/backups/${Uri.encodeComponent(name)}');
    });
  }

  /// The browser-download URL for a backup archive.
  Uri downloadUrl(String name) =>
      absoluteApiUrl('/api/v1/backups/${Uri.encodeComponent(name)}');

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
    return data;
  }
}
