import 'package:dio/dio.dart';
import 'package:salt_shared/salt_shared.dart';

/// Base URL of the SaltToTaste API. In development the Flutter dev server and
/// the API run on different ports; in production the app is served
/// same-origin by the API server and this collapses to ''.
const String apiBaseUrl = String.fromEnvironment(
  'SALT_API_BASE',
  defaultValue: 'http://localhost:8080',
);

/// Resolves a server-relative path (e.g. `/images/<src>/<file>.jpg`) to an
/// absolute URL.
String apiUrl(String path) => '$apiBaseUrl$path';

/// A user-presentable failure from the API layer.
///
/// The message is safe to show verbatim; [requestId] (when present) lets the
/// user quote a server log reference in a bug report.
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
  }) async {
    final data = await _get('/api/v1/recipes', query: {
      'page': '$page',
      'limit': '$limit',
    });
    final items = [
      for (final item in data['items'] as List<dynamic>)
        RecipeCardMapper.fromMap(item as Map<String, dynamic>),
    ];
    return (items: items, total: data['total'] as int);
  }

  /// The full recipe matched by [idOrSlug].
  Future<RecipeDetail> getRecipe(String idOrSlug) async {
    final data = await _get('/api/v1/recipes/$idOrSlug');
    return RecipeDetail(
      recipe: RecipeMapper.fromMap(data['recipe'] as Map<String, dynamic>),
      sourceSlug: data['source_slug'] as String,
      heroImageUrl: data['hero_image_url'] as String?,
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: query,
      );
      return response.data!;
    } on DioException catch (exception) {
      throw _asRepositoryException(exception);
    }
  }

  RepositoryException _asRepositoryException(DioException exception) {
    final data = exception.response?.data;
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        final code = error['code'];
        final message = error['message'];
        return RepositoryException(
          code == 'not_found' ? 'Recipe not found.' : '$message',
          requestId: error['request_id'] as String?,
        );
      }
    }
    return const RepositoryException(
      "Couldn't reach the SaltToTaste server. Check that it's running, "
      'then retry.',
    );
  }
}
