import 'package:dio/dio.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException, apiGuard;

/// One detected source folder inside the server's import directory.
class ImportCandidate {
  const ImportCandidate({
    required this.path,
    required this.kind,
    required this.fileCount,
  });

  factory ImportCandidate.fromJson(Map<String, dynamic> json) =>
      ImportCandidate(
        path: json['path'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
      );

  /// Path relative to the import directory (`.` for the directory itself).
  final String path;

  /// `v1` (Recipe Extraction root) or `legacy` (old SaltToTaste v0 root).
  final String kind;

  /// Number of recipe YAML files found.
  final int fileCount;
}

/// The import directory and the source folders detected inside it.
class ImportCandidates {
  const ImportCandidates({required this.importDir, required this.items});

  factory ImportCandidates.fromJson(Map<String, dynamic> json) =>
      ImportCandidates(
        importDir: json['import_dir'] as String? ?? '',
        items: [
          if (json['items'] is List)
            for (final item in json['items'] as List<dynamic>)
              ImportCandidate.fromJson(item as Map<String, dynamic>),
        ],
      );

  /// Absolute path the server scans (shown so the empty state is truthful).
  final String importDir;
  final List<ImportCandidate> items;
}

/// Bulk-import job progress.
class ImportJob {
  const ImportJob({
    required this.id,
    required this.status,
    required this.total,
    required this.done,
    required this.imported,
    required this.updated,
    required this.skipped,
    required this.failed,
    this.legacy = false,
    this.sourcePath,
    this.log = const [],
  });

  factory ImportJob.fromJson(Map<String, dynamic> json) => ImportJob(
    id: (json['id']! as num).toInt(),
    status: json['status'] as String? ?? '',
    total: (json['total'] as num?)?.toInt() ?? 0,
    done: (json['done'] as num?)?.toInt() ?? 0,
    imported: (json['imported'] as num?)?.toInt() ?? 0,
    updated: (json['updated'] as num?)?.toInt() ?? 0,
    skipped: (json['skipped'] as num?)?.toInt() ?? 0,
    failed: (json['failed'] as num?)?.toInt() ?? 0,
    legacy: json['legacy'] == true,
    sourcePath: json['source_path'] as String?,
    log: [
      if (json['log'] is List)
        for (final entry in json['log'] as List<dynamic>) '$entry',
    ],
  );

  final int id;

  /// `running` | `done` | `failed`.
  final String status;
  final int total;
  final int done;
  final int imported;
  final int updated;
  final int skipped;
  final int failed;

  /// Whether this was a legacy v0 import (drives the kind chip on a
  /// synthetic pinned row when the folder left the candidate list).
  final bool legacy;

  /// The absolute source folder being imported (matches a candidate's
  /// resolved path — the running row is pinned by comparing against it).
  final String? sourcePath;
  final List<String> log;

  bool get running => status == 'running';
}

/// Access to the bulk-import API (admin).
class ImportRepository {
  ImportRepository(this._dio);

  final Dio _dio;

  /// The import directory and the source folders detected inside it.
  Future<ImportCandidates> candidates() {
    return apiGuard(() async {
      final response = await _dio.get<dynamic>('/api/v1/import/candidates');
      return ImportCandidates.fromJson(_asMap(response.data));
    });
  }

  /// Starts a background import of [path] (a candidate's relative path);
  /// returns the job id. `409 conflict` while one is already running.
  Future<int> start(String path) {
    return apiGuard(() async {
      final data = _asMap(
        (await _dio.post<dynamic>('/api/v1/import', data: {'path': path})).data,
      );
      return (data['job_id']! as num).toInt();
    });
  }

  /// Import-job progress.
  Future<ImportJob> job(int id) {
    return apiGuard(() async {
      final response = await _dio.get<dynamic>('/api/v1/import/jobs/$id');
      return ImportJob.fromJson(_asMap(response.data));
    });
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
    return data;
  }
}
