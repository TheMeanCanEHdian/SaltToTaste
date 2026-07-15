import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;

/// Authentication state, driving the router's redirects.
sealed class AuthState {
  const AuthState();
}

/// Bootstrap in flight — show the splash.
final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// The instance has no users yet — show first-run setup.
final class AuthSetupRequired extends AuthState {
  const AuthSetupRequired();
}

/// Bootstrap couldn't reach the server — show a retry screen rather than a
/// login form whose submissions would also fail (and which would hide the
/// setup screen from an actually-unclaimed instance).
final class AuthBootstrapFailed extends AuthState {
  const AuthBootstrapFailed(this.message);

  final String message;
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.notice});

  /// Optional friendly reason shown on the login page (e.g. after signing
  /// out or when a session expired).
  final String? notice;
}

/// Signed in but the account must set a new password first.
final class AuthPasswordChangeRequired extends AuthState {
  const AuthPasswordChangeRequired(this.user);

  final AuthUserInfo user;
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);

  final AuthUserInfo user;
}

/// Owns the session lifecycle: bootstrap, sign-in/out, forced password
/// change, and reacting to 401s from anywhere in the app.
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repository) : super(const AuthUnknown());

  final AuthRepository _repository;

  AuthUserInfo? get user => switch (state) {
        AuthSignedIn(:final user) => user,
        AuthPasswordChangeRequired(:final user) => user,
        _ => null,
      };

  /// Determines the initial state: setup screen, login, or a live session.
  Future<void> bootstrap() async {
    emit(const AuthUnknown());
    try {
      if (await _repository.setupRequired()) {
        emit(const AuthSetupRequired());
        return;
      }
      final user = await _repository.me();
      _emitForUser(user);
    } on RepositoryException catch (exception) {
      emit(AuthBootstrapFailed(exception.message));
    } catch (_) {
      emit(
        const AuthBootstrapFailed(
          'Something went wrong starting the app. Please retry.',
        ),
      );
    }
  }

  /// Called by the HTTP layer on any 401: the session is gone.
  void sessionExpired() {
    if (state is AuthSignedIn || state is AuthPasswordChangeRequired) {
      emit(const AuthSignedOut(notice: 'Your session expired. Sign in again.'));
    }
  }

  Future<void> completeSetup({
    required String setupCode,
    required String username,
    required String password,
  }) async {
    final user = await _repository.setup(
      setupCode: setupCode,
      username: username,
      password: password,
    );
    _emitForUser(user);
  }

  Future<void> login({
    required String username,
    required String password,
    required bool remember,
  }) async {
    final user = await _repository.login(
      username: username,
      password: password,
      remember: remember,
    );
    _emitForUser(user);
  }

  Future<void> changePassword({
    String? currentPassword,
    required String newPassword,
  }) async {
    await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    final current = user;
    if (current != null) {
      emit(
        AuthSignedIn(
          AuthUserInfo(
            id: current.id,
            username: current.username,
            role: current.role,
            mustChangePassword: false,
          ),
        ),
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _repository.logout();
    } on RepositoryException {
      // The session may already be gone; signing out locally regardless.
    }
    emit(const AuthSignedOut(notice: 'Signed out.'));
  }

  void _emitForUser(AuthUserInfo? user) {
    if (user == null) {
      emit(const AuthSignedOut());
    } else if (user.mustChangePassword) {
      emit(AuthPasswordChangeRequired(user));
    } else {
      emit(AuthSignedIn(user));
    }
  }
}
