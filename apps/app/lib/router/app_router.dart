import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

/// Splash while auth resolves; shows the failure + retry when bootstrap
/// couldn't reach the server (so users aren't dumped onto a login form that
/// can't succeed, and unclaimed instances aren't hidden from setup).
class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthCubit>().state;
    if (state is AuthBootstrapFailed) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 42, color: SaltColors.rose),
                const SizedBox(height: 12),
                Text(
                  state.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: SaltColors.maroon,
                  ),
                  onPressed: () => context.read<AuthCubit>().bootstrap(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: SaltColors.maroon),
      ),
    );
  }
}

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
/// splash while unknown (or bootstrap-failed, with retry), /setup on first
/// run, /login when signed out, /change-password while a temporary password
/// is active.
///
/// The originally requested location survives the auth dance: a cold deep
/// link (e.g. a shared `/r/<slug>`) is stashed while the state resolves and
/// restored once signed in.
GoRouter buildRouter(AuthCubit authCubit) {
  const authPaths = {'/login', '/setup', '/change-password', '/splash'};
  String? pendingLocation;
  return GoRouter(
    refreshListenable: _AuthRefresh(authCubit.stream),
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.uri.path;
      final target = switch (authCubit.state) {
        AuthUnknown() || AuthBootstrapFailed() => '/splash',
        AuthSetupRequired() => '/setup',
        AuthSignedOut() => '/login',
        AuthPasswordChangeRequired() => '/change-password',
        AuthSignedIn() => null,
      };
      if (target != null) {
        // Remember where the user was headed before parking them.
        if (!authPaths.contains(path)) {
          pendingLocation = state.uri.toString();
        }
        return path == target ? null : target;
      }
      // Signed in: restore the stashed destination, keep auth pages away.
      final destination = pendingLocation;
      if (destination != null && !authPaths.contains(path)) {
        pendingLocation = null;
      }
      if (authPaths.contains(path)) {
        pendingLocation = null;
        return destination ?? '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashPage(),
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
