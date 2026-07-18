import 'package:dio/dio.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/recipe_repository.dart' show apiGuard;

/// A page of buffered server log records plus the buffer's capacity and the
/// distinct logger names (for the source filter).
class LogsPage {
  const LogsPage({
    required this.items,
    required this.capacity,
    required this.loggers,
  });

  final List<LogEntry> items;
  final int capacity;
  final List<String> loggers;
}

/// Reads the admin log viewer's endpoint (`GET /api/v1/admin/logs`).
class LogsRepository {
  LogsRepository(this._dio);

  final Dio _dio;

  /// Recent log records (newest first). [level] shows that bucket and above;
  /// [logger] filters to one source; [query] is a message/request-id substring.
  Future<LogsPage> getLogs({
    String? level,
    String? logger,
    String? query,
    int limit = 300,
  }) {
    return apiGuard(() async {
      final response = await _dio.get<dynamic>(
        '/api/v1/admin/logs',
        queryParameters: {
          'limit': '$limit',
          if (level != null && level.isNotEmpty) 'level': level,
          if (logger != null && logger.isNotEmpty) 'logger': logger,
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        },
      );
      final data = response.data as Map<String, dynamic>;
      LogEntryMapper.ensureInitialized();
      return LogsPage(
        items: [
          for (final item in data['items'] as List<dynamic>)
            LogEntryMapper.fromMap(item as Map<String, dynamic>),
        ],
        capacity: (data['capacity'] as num).toInt(),
        loggers: [
          for (final name in data['loggers'] as List<dynamic>) name as String,
        ],
      );
    });
  }
}
