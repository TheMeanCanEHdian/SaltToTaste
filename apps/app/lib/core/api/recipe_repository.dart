import 'package:dio/dio.dart';
import 'package:salt_shared/salt_shared.dart';

/// Base URL of the SaltToTaste API.
///
/// Defaults to empty (same-origin) so a production web build served by the
/// API server Just Works. Development, where the Flutter dev server and the
/// API run on different ports, must override it:
/// `--dart-define=SALT_API_BASE=http://localhost:8080`.
const String apiBaseUrl = String.fromEnvironment('SALT_API_BASE');

/// Resolves a server-relative path (e.g. `/images/<src>/<file>.jpg`) to a URL
/// for use in `Image.network` — absolute in dev, origin-relative in
/// production (which the browser resolves against the page origin).
String apiUrl(String path) => '$apiBaseUrl$path';

/// An absolute URL for [path], suitable for `launchUrl` (which needs a scheme
/// even when [apiBaseUrl] is empty).
Uri absoluteApiUrl(String path) => Uri.base.resolve(apiUrl(path));

/// A user-presentable failure from the API layer.
///
/// The message is written for end users (never a raw server string or stack
/// trace); [requestId] (when present) lets the user quote a server log
/// reference in a bug report.
class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.requestId});

  final String message;
  final String? requestId;

  @override
  String toString() => message;
}

/// A full recipe document plus its serving context.
class RecipeDetail {
  const RecipeDetail({
    required this.recipe,
    required this.sourceSlug,
    this.heroImageUrl,
  });

  final Recipe recipe;
  final String sourceSlug;

  /// Server-relative hero URL (`/images/...`) or null.
  final String? heroImageUrl;
}

/// Read access to the recipe API.
class RecipeRepository {
  RecipeRepository({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: apiBaseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
              ),
            );

  final Dio _dio;

  /// One page of recipe cards plus the total count.
  Future<({List<RecipeCard> items, int total})> listRecipes({
    required int page,
    int limit = 48,
  }) {
    return _request('recipes', () async {
      final data = await _getMap('/api/v1/recipes', query: {
        'page': '$page',
        'limit': '$limit',
      });
      final items = [
        for (final item in data['items']! as List<dynamic>)
          RecipeCardMapper.fromMap(item as Map<String, dynamic>),
      ];
      return (items: items, total: (data['total']! as num).toInt());
    });
  }

  /// The full recipe matched by [idOrSlug].
  Future<RecipeDetail> getRecipe(String idOrSlug) {
    return _request('recipe', () async {
      final data = await _getMap(
        '/api/v1/recipes/${Uri.encodeComponent(idOrSlug)}',
      );
      return RecipeDetail(
        recipe: RecipeMapper.fromMap(data['recipe']! as Map<String, dynamic>),
        sourceSlug: data['source_slug']! as String,
        heroImageUrl: data['hero_image_url'] as String?,
      );
    });
  }

  /// The download URL for a recipe's canonical YAML export.
  Uri yamlUrl(String idOrSlug) =>
      absoluteApiUrl('/api/v1/recipes/${Uri.encodeComponent(idOrSlug)}/yaml');

  /// Runs [action], mapping every failure — transport errors from Dio AND
  /// decode/shape errors (a malformed 200 body, a missing key, a wrong type)
  /// — to a [RepositoryException] so callers only ever catch one type and the
  /// UI always reaches an error state instead of hanging.
  Future<T> _request<T>(String what, Future<T> Function() action) async {
    try {
      return await action();
    } on RepositoryException {
      rethrow;
    } on DioException catch (exception) {
      throw _fromDio(exception);
    } catch (_) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _dio.get<dynamic>(path, queryParameters: query);
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
    return data;
  }

  RepositoryException _fromDio(DioException exception) {
    final data = exception.response?.data;
    if (data is Map && data['error'] is Map) {
      final error = (data['error'] as Map).cast<String, dynamic>();
      final code = error['code'];
      final requestId = error['request_id'] as String?;
      final message = switch (code) {
        'not_found' => 'Recipe not found.',
        'validation' when error['message'] is String =>
          error['message'] as String,
        _ => 'Something went wrong on the server. Please try again.',
      };
      return RepositoryException(message, requestId: requestId);
    }
    // No envelope: a transport failure, or a non-API response (proxy/HTML).
    final message = switch (exception.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout =>
        "Couldn't reach the SaltToTaste server. Check that it's running, "
            'then retry.',
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        'The server took too long to respond. Please try again.',
      _ => 'Something went wrong talking to the server. Please try again.',
    };
    return RepositoryException(message);
  }
}
