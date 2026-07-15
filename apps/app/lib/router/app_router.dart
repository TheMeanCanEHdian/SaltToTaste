import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/auth/change_password_page.dart';
import 'package:salt_app/features/auth/login_page.dart';
import 'package:salt_app/features/auth/setup_page.dart';
import 'package:salt_app/features/recipes/detail/recipe_detail_page.dart';
import 'package:salt_app/features/recipes/list/home_page.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// Re-evaluates router redirects whenever the auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Builds the router; redirects are driven entirely by [authCubit]'s state:
/// splash while unknown, /setup on first run, /login when signed out,
/// /change-password while a temporary password is active.
GoRouter buildRouter(AuthCubit authCubit) {
  const authPaths = {'/login', '/setup', '/change-password', '/splash'};
  return GoRouter(
    refreshListenable: _AuthRefresh(authCubit.stream),
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.uri.path;
      final target = switch (authCubit.state) {
        AuthUnknown() => '/splash',
        AuthSetupRequired() => '/setup',
        AuthSignedOut() => '/login',
        AuthPasswordChangeRequired() => '/change-password',
        AuthSignedIn() => null,
      };
      if (target != null) {
        return path == target ? null : target;
      }
      // Signed in: keep auth pages out of reach.
      return authPaths.contains(path) ? '/' : null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: SaltColors.maroon),
          ),
        ),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/setup', builder: (context, state) => const SetupPage()),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordPage(),
      ),
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/r/:slug',
        builder: (context, state) =>
            RecipeDetailPage(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: const SaltNavBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Page not found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: SaltColors.maroon),
              onPressed: () => context.go('/'),
              child: const Text('Back to recipes'),
            ),
          ],
        ),
      ),
    ),
  );
}
