import 'dart:typed_data';

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
  const RepositoryException(this.message, {this.code, this.requestId});

  final String message;

  /// The server's stable error code (`validation`, `locked`, ...) when the
  /// failure carried an envelope; null for transport/shape failures.
  final String? code;
  final String? requestId;

  @override
  String toString() => message;
}

/// Runs [action], mapping every failure — Dio transport errors, envelope
/// errors, and decode/shape surprises alike — to a [RepositoryException].
/// The single error funnel shared by all repositories.
Future<T> apiGuard<T>(
  Future<T> Function() action, {
  String notFoundMessage = 'Not found.',
}) async {
  try {
    return await action();
  } on RepositoryException {
    rethrow;
  } on DioException catch (exception) {
    final data = exception.response?.data;
    if (data is Map && data['error'] is Map) {
      final error = (data['error'] as Map).cast<String, dynamic>();
      final code = error['code'];
      final message = switch (code) {
        'not_found' => notFoundMessage,
        'validation' when error['message'] is String =>
          error['message'] as String,
        'forbidden' when error['message'] is String =>
          error['message'] as String,
        _ => 'Something went wrong on the server. Please try again.',
      };
      throw RepositoryException(
        message,
        code: code is String ? code : null,
        requestId: error['request_id'] as String?,
      );
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
    throw RepositoryException(message);
  } catch (_) {
    throw const RepositoryException(
      'The server returned an unexpected response. Please try again.',
    );
  }
}

/// A full recipe document plus its serving context and the caller's
/// personal data (favorite flag, private note).
class RecipeDetail {
  const RecipeDetail({
    required this.recipe,
    required this.sourceSlug,
    this.heroImageUrl,
    this.favorite = false,
    this.note,
  });

  final Recipe recipe;
  final String sourceSlug;

  /// Server-relative hero URL (`/images/...`) or null.
  final String? heroImageUrl;

  /// Whether the signed-in user has favorited this recipe.
  final bool favorite;

  /// The signed-in user's private note, or null.
  final String? note;

  /// Copy with changed personal data. Omitting [note] PRESERVES it (so a
  /// favorite toggle can't wipe the note from view); pass [clearNote] to
  /// actually remove it.
  RecipeDetail copyWith({bool? favorite, String? note, bool clearNote = false}) =>
      RecipeDetail(
        recipe: recipe,
        sourceSlug: sourceSlug,
        heroImageUrl: heroImageUrl,
        favorite: favorite ?? this.favorite,
        note: clearNote ? null : (note ?? this.note),
      );
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

  /// One page of recipe cards plus the total count; [query] runs the
  /// search DSL server-side, [favoritesOnly] narrows to the caller's
  /// favorites.
  Future<({List<RecipeCard> items, int total})> listRecipes({
    required int page,
    int limit = 48,
    String? query,
    bool favoritesOnly = false,
  }) {
    return _request('recipes', () async {
      final data = await _getMap('/api/v1/recipes', query: {
        'page': '$page',
        'limit': '$limit',
        if (query != null && query.trim().isNotEmpty) 'q': query,
        if (favoritesOnly) 'favorites': 'true',
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
      final data = await _getMap('/api/v1/recipes/${_seg(idOrSlug)}');
      return _detailFrom(data);
    });
  }

  /// The download URL for a recipe's canonical YAML export.
  Uri yamlUrl(String idOrSlug) =>
      absoluteApiUrl('/api/v1/recipes/${_seg(idOrSlug)}/yaml');

  // ------------------------------------------------------------------
  // Editing (admin + full scope on the server side).
  // ------------------------------------------------------------------

  /// Creates a recipe from the editor's field map and returns the stored
  /// detail (the server generates id and slug).
  Future<RecipeDetail> createRecipe(Map<String, Object?> fields) {
    return _request('create', () async {
      final response = await _dio.post<dynamic>(
        '/api/v1/recipes',
        data: {'recipe': fields},
      );
      return _detailFrom(_asMap(response.data));
    });
  }

  /// Applies the editor's field map to an existing recipe (merge semantics:
  /// only the keys present are changed).
  Future<RecipeDetail> updateRecipe(
    String idOrSlug,
    Map<String, Object?> fields,
  ) {
    return _request('update', () async {
      final response = await _dio.put<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}',
        data: {'recipe': fields},
      );
      return _detailFrom(_asMap(response.data));
    });
  }

  /// Deletes the recipe (the server takes a backup first).
  Future<void> deleteRecipe(String idOrSlug) {
    return _request('delete', () async {
      await _dio.delete<dynamic>('/api/v1/recipes/${_seg(idOrSlug)}');
    });
  }

  /// Uploads photo [bytes] as the recipe's hero image or a gallery entry.
  Future<RecipeDetail> uploadImage(
    String idOrSlug,
    Uint8List bytes, {
    String role = 'hero',
  }) {
    return _request('upload', () async {
      final response = await _dio.post<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/images',
        queryParameters: {'role': role},
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {Headers.contentLengthHeader: bytes.length},
          contentType: 'application/octet-stream',
          // A 25 MB photo on a slow uplink outlives the default timeouts.
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      return _detailFrom(_asMap(response.data));
    });
  }

  /// Asks the server to download a photo from [url] (SSRF-guarded there).
  Future<RecipeDetail> imageFromUrl(
    String idOrSlug,
    String url, {
    String role = 'hero',
  }) {
    return _request('image-from-url', () async {
      final response = await _dio.post<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/images/from_url',
        data: {'url': url, 'role': role},
        // The server-side download has its own ~30s budget.
        options: Options(receiveTimeout: const Duration(minutes: 1)),
      );
      return _detailFrom(_asMap(response.data));
    });
  }

  // ------------------------------------------------------------------
  // Personal data (any role; read-scope PATs allowed server-side).
  // ------------------------------------------------------------------

  /// Marks or unmarks the recipe as one of the caller's favorites.
  Future<void> setFavorite(String idOrSlug, {required bool favorite}) {
    return _request('favorite', () async {
      final path = '/api/v1/recipes/${_seg(idOrSlug)}/favorite';
      if (favorite) {
        await _dio.put<dynamic>(path);
      } else {
        await _dio.delete<dynamic>(path);
      }
    });
  }

  /// Saves the caller's private note (empty [note] deletes it). Returns the
  /// stored note, or null when cleared.
  Future<String?> setNote(String idOrSlug, String note) {
    return _request('note', () async {
      final response = await _dio.put<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/note',
        data: {'note': note},
      );
      return _asMap(response.data)['note'] as String?;
    });
  }

  RecipeDetail _detailFrom(Map<String, dynamic> data) => RecipeDetail(
        recipe: RecipeMapper.fromMap(data['recipe']! as Map<String, dynamic>),
        sourceSlug: data['source_slug']! as String,
        heroImageUrl: data['hero_image_url'] as String?,
        favorite: data['favorite'] == true,
        note: data['note'] as String?,
      );

  static String _seg(String idOrSlug) => Uri.encodeComponent(idOrSlug);

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
    return data;
  }

  /// [apiGuard] with this repository's not-found wording.
  Future<T> _request<T>(String what, Future<T> Function() action) =>
      apiGuard(action, notFoundMessage: 'Recipe not found.');

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

}
