import 'package:dio/dio.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show absoluteApiUrl, apiGuard;

/// A page of persisted server log records plus the distinct logger names
/// present in the store (for the source filter).
class LogsPage {
  const LogsPage({required this.items, required this.loggers});

  final List<LogEntry> items;
  final List<String> loggers;
}

/// Reads the admin log viewer's endpoint (`GET /api/v1/admin/logs`).
class LogsRepository {
  LogsRepository(this._dio);

  final Dio _dio;

  /// Recent log records (newest first). [level] shows that bucket and above;
  /// [logger] filters to one source; [query] is a message/request-id substring.
  ///
  /// [fullScan] asks the server to search the WHOLE history (off its serving
  /// isolate) instead of only a recent tail — used when a filter is active, so
  /// matches older than the tail window are found; the recurring Live poll of
  /// an unfiltered view leaves it false to stay cheap.
  Future<LogsPage> getLogs({
    String? level,
    String? logger,
    String? query,
    int limit = 300,
    bool fullScan = false,
  }) {
    return apiGuard(() async {
      final response = await _dio.get<dynamic>(
        '/api/v1/admin/logs',
        queryParameters: {
          'limit': '$limit',
          if (level != null && level.isNotEmpty) 'level': level,
          if (logger != null && logger.isNotEmpty) 'logger': logger,
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
          if (fullScan) 'scan': 'full',
        },
      );
      final data = response.data as Map<String, dynamic>;
      LogEntryMapper.ensureInitialized();
      return LogsPage(
        items: [
          for (final item in data['items'] as List<dynamic>)
            LogEntryMapper.fromMap(item as Map<String, dynamic>),
        ],
        loggers: [
          for (final name in data['loggers'] as List<dynamic>) name as String,
        ],
      );
    });
  }

  /// Absolute URL of the log export (`GET /api/v1/admin/logs/export`) with the
  /// active filters, for `launchUrl`. The server streams the full matching log
  /// (no row cap) as a text file via `Content-Disposition`.
  Uri downloadUrl({String? level, String? logger, String? query}) {
    final params = <String, String>{
      if (level != null && level.isNotEmpty) 'level': level,
      if (logger != null && logger.isNotEmpty) 'logger': logger,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    };
    final suffix = params.isEmpty
        ? ''
        : '?${Uri(queryParameters: params).query}';
    return absoluteApiUrl('/api/v1/admin/logs/export$suffix');
  }
}
