import 'package:dio/dio.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;

/// The signed-in account as reported by `/auth/me` and `/auth/login`.
class AuthUserInfo {
  const AuthUserInfo({
    required this.id,
    required this.username,
    required this.role,
    required this.mustChangePassword,
  });

  factory AuthUserInfo.fromJson(Map<String, dynamic> json) => AuthUserInfo(
        id: json['id'] as int,
        username: json['username'] as String,
        role: json['role'] as String,
        mustChangePassword: (json['must_change_password'] as bool?) ?? false,
      );

  final int id;
  final String username;
  final String role;
  final bool mustChangePassword;

  bool get isAdmin => role == 'admin';
}

/// A managed account row (admin Users tab).
class UserAccount {
  const UserAccount({
    required this.id,
    required this.username,
    required this.role,
    required this.disabled,
    required this.mustChangePassword,
    this.lastActiveAt,
  });

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        id: json['id'] as int,
        username: json['username'] as String,
        role: json['role'] as String,
        disabled: json['disabled'] as bool,
        mustChangePassword: json['must_change_password'] as bool,
        lastActiveAt: json['last_active_at'] as String?,
      );

  final int id;
  final String username;
  final String role;
  final bool disabled;
  final bool mustChangePassword;
  final String? lastActiveAt;
}

/// One of the caller's sessions (Account tab).
class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.current,
    required this.remember,
    this.createdAt,
    this.lastSeenAt,
    this.userAgent,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
        id: json['id'] as String,
        current: json['current'] as bool,
        remember: json['remember'] as bool,
        createdAt: json['created_at'] as String?,
        lastSeenAt: json['last_seen_at'] as String?,
        userAgent: json['user_agent'] as String?,
      );

  final String id;
  final bool current;
  final bool remember;
  final String? createdAt;
  final String? lastSeenAt;
  final String? userAgent;
}

/// One of the caller's personal access tokens.
class TokenInfo {
  const TokenInfo({
    required this.id,
    required this.name,
    required this.prefix,
    required this.scope,
    required this.revoked,
    this.createdAt,
    this.lastUsedAt,
  });

  factory TokenInfo.fromJson(Map<String, dynamic> json) => TokenInfo(
        id: json['id'] as int,
        name: json['name'] as String,
        prefix: json['prefix'] as String,
        scope: json['scope'] as String,
        revoked: json['revoked'] as bool,
        createdAt: json['created_at'] as String?,
        lastUsedAt: json['last_used_at'] as String?,
      );

  final int id;
  final String name;
  final String prefix;
  final String scope;
  final bool revoked;
  final String? createdAt;
  final String? lastUsedAt;
}

/// Auth and account-management access to the API.
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// Whether this instance has no users yet (first-run setup).
  Future<bool> setupRequired() async {
    final data = await _call(() => _dio.get<dynamic>('/healthz'));
    return data is Map<String, dynamic> && data['setup_required'] == true;
  }

  /// The signed-in user, or null when the session is absent/expired.
  Future<AuthUserInfo?> me() async {
    try {
      return await _guard(() async {
        final data =
            await _call(() => _dio.get<dynamic>('/api/v1/auth/me'));
        return AuthUserInfo.fromJson(
          (data as Map<String, dynamic>)['user'] as Map<String, dynamic>,
        );
      });
    } on RepositoryException catch (exception) {
      if (exception.code == 'unauthorized') {
        return null;
      }
      rethrow;
    }
  }

  Future<AuthUserInfo> setup({
    required String setupCode,
    required String username,
    required String password,
  }) {
    return _guard(() async {
      final data = await _call(
        () => _dio.post<dynamic>('/api/v1/auth/setup', data: {
          'setup_code': setupCode,
          'username': username,
          'password': password,
        }),
      );
      return AuthUserInfo.fromJson(
        (data as Map<String, dynamic>)['user'] as Map<String, dynamic>,
      );
    });
  }

  Future<AuthUserInfo> login({
    required String username,
    required String password,
    required bool remember,
  }) {
    return _guard(() async {
      final data = await _call(
        () => _dio.post<dynamic>('/api/v1/auth/login', data: {
          'username': username,
          'password': password,
          'remember': remember,
        }),
      );
      return AuthUserInfo.fromJson(
        (data as Map<String, dynamic>)['user'] as Map<String, dynamic>,
      );
    });
  }

  Future<void> logout() =>
      _call(() => _dio.post<dynamic>('/api/v1/auth/logout'));

  Future<void> changePassword({
    String? currentPassword,
    required String newPassword,
  }) =>
      _call(
        () => _dio.post<dynamic>('/api/v1/auth/change_password', data: {
          if (currentPassword != null) 'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

  // --- admin: users ---------------------------------------------------------

  Future<List<UserAccount>> listUsers() => _guard(() async {
        final data = await _call(() => _dio.get<dynamic>('/api/v1/users'));
        return _items(data, UserAccount.fromJson);
      });

  /// Creates an account; returns the account and its one-time temp password.
  Future<({UserAccount user, String tempPassword})> createUser({
    required String username,
    required String role,
  }) {
    return _guard(() async {
      final data = await _call(
        () => _dio.post<dynamic>('/api/v1/users', data: {
          'username': username,
          'role': role,
        }),
      ) as Map<String, dynamic>;
      return (
        user: UserAccount.fromJson(data['user'] as Map<String, dynamic>),
        tempPassword: data['temp_password'] as String,
      );
    });
  }

  Future<UserAccount> patchUser(int id, {String? role, bool? disabled}) {
    return _guard(() async {
      final data = await _call(
        () => _dio.patch<dynamic>('/api/v1/users/$id', data: {
          if (role != null) 'role': role,
          if (disabled != null) 'disabled': disabled,
        }),
      ) as Map<String, dynamic>;
      return UserAccount.fromJson(data['user'] as Map<String, dynamic>);
    });
  }

  Future<String> resetPassword(int id) => _guard(() async {
        final data = await _call(
          () => _dio.post<dynamic>('/api/v1/users/$id/reset_password'),
        ) as Map<String, dynamic>;
        return data['temp_password'] as String;
      });

  // --- own sessions & tokens -------------------------------------------------

  Future<List<SessionInfo>> listSessions() => _guard(() async {
        final data =
            await _call(() => _dio.get<dynamic>('/api/v1/sessions'));
        return _items(data, SessionInfo.fromJson);
      });

  Future<void> deleteSession(String id) =>
      _call(() => _dio.delete<dynamic>('/api/v1/sessions/$id'));

  Future<List<TokenInfo>> listTokens() => _guard(() async {
        final data = await _call(() => _dio.get<dynamic>('/api/v1/tokens'));
        return _items(data, TokenInfo.fromJson);
      });

  /// Mints a PAT; the returned token value is shown exactly once.
  Future<({String token, TokenInfo item})> createToken({
    required String name,
    required String scope,
  }) {
    return _guard(() async {
      final data = await _call(
        () => _dio.post<dynamic>('/api/v1/tokens', data: {
          'name': name,
          'scope': scope,
        }),
      ) as Map<String, dynamic>;
      return (
        token: data['token'] as String,
        item: TokenInfo.fromJson(data['item'] as Map<String, dynamic>),
      );
    });
  }

  Future<void> revokeToken(int id) =>
      _call(() => _dio.delete<dynamic>('/api/v1/tokens/$id'));

  // ---------------------------------------------------------------------------

  List<T> _items<T>(
    Object? data,
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      [
        for (final item in (data as Map<String, dynamic>)['items'] as List)
          fromJson(item as Map<String, dynamic>),
      ];

  /// Maps transport and envelope failures to [RepositoryException] with the
  /// server's error code preserved (`locked`, `validation`, `csrf`, ...).
  Future<Object?> _call(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (exception) {
      final body = exception.response?.data;
      if (body is Map && body['error'] is Map) {
        final error = (body['error'] as Map).cast<String, dynamic>();
        throw RepositoryException(
          error['message'] is String
              ? error['message'] as String
              : 'Something went wrong. Please try again.',
          code: error['code'] as String?,
          requestId: error['request_id'] as String?,
        );
      }
      if (exception.response?.statusCode == 401) {
        // A 401 without an envelope (an auth proxy, a stripped body) still
        // means the credential is gone.
        throw const RepositoryException(
          'Sign in to continue.',
          code: 'unauthorized',
        );
      }
      throw const RepositoryException(
        "Couldn't reach the SaltToTaste server. Check that it's running, "
        'then retry.',
      );
    } catch (_) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
  }

  /// Wraps request + response parsing so a malformed 200 body (unexpected
  /// shape, wrong types) surfaces as a [RepositoryException] instead of an
  /// uncaught TypeError that would strand the UI on a spinner.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on RepositoryException {
      rethrow;
    } catch (_) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
  }
}
