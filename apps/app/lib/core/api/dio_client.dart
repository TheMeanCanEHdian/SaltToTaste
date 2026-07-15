import 'package:dio/dio.dart';

import 'package:salt_app/core/api/dio_config_io.dart'
    if (dart.library.js_interop) 'package:salt_app/core/api/dio_config_web.dart';
import 'package:salt_app/core/api/recipe_repository.dart';

/// Builds the app-wide [Dio]: session-cookie credentials on web, the
/// anti-CSRF header on every request, and [onUnauthorized] fired whenever
/// the server answers 401 (an expired/revoked session) so the auth state
/// can flip to signed-out.
Dio createDio({void Function()? onUnauthorized}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'X-Requested-With': 'SaltToTaste'},
    ),
  );
  configurePlatform(dio);
  if (onUnauthorized != null) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            onUnauthorized();
          }
          handler.next(error);
        },
      ),
    );
  }
  return dio;
}
