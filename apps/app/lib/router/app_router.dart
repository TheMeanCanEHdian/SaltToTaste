import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/auth/change_password_page.dart';
import 'package:salt_app/features/auth/login_page.dart';
import 'package:salt_app/features/auth/recover_page.dart';
import 'package:salt_app/features/auth/setup_page.dart';
import 'package:salt_app/features/editor/editor_page.dart';
import 'package:salt_app/features/recipes/detail/recipe_detail_page.dart';
import 'package:salt_app/features/recipes/list/favorites_page.dart';
import 'package:salt_app/features/recipes/list/home_page.dart';
import 'package:salt_app/features/search/search_page.dart';
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
        child: CircularProgressIndicator(
          color: SaltColors.maroon,
          semanticsLabel: 'Loading',
        ),
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
/// is active. `/recover` is the one exception: it is an escape hatch for when
/// nobody can sign in, so a signed-out user who asks for it is left there
/// instead of being bounced to /login.
///
/// The originally requested location survives the auth dance: a cold deep
/// link (e.g. a shared `/r/<slug>`) is stashed while the state resolves and
/// restored once signed in.
GoRouter buildRouter(AuthCubit authCubit) {
  const authPaths = {
    '/login',
    '/setup',
    '/recover',
    '/change-password',
    '/splash',
  };
  String? pendingLocation;
  return GoRouter(
    refreshListenable: _AuthRefresh(authCubit.stream),
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.uri.path;
      // Recovery must stay reachable while signed out — that is its entire
      // purpose. (Bootstrap-unknown/failed still wins: the code can't be
      // redeemed against a server we can't reach.)
      if (path == '/recover' && authCubit.state is AuthSignedOut) {
        return null;
      }
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
      // Editor routes are admin-only (the server enforces regardless; this
      // just keeps members off a form that could never save).
      final editing = path == '/new' || path.endsWith('/edit');
      if (editing && !(authCubit.user?.isAdmin ?? false)) {
        return '/';
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
        path: '/recover',
        builder: (context, state) => const RecoverPage(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordPage(),
      ),
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(path: '/new', builder: (context, state) => const EditorPage()),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const FavoritesPage(),
      ),
      GoRoute(
        path: '/r/:slug',
        builder: (context, state) =>
            RecipeDetailPage(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/r/:slug/edit',
        builder: (context, state) =>
            EditorPage(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) =>
            SearchPage(query: state.uri.queryParameters['q'] ?? ''),
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
            Semantics(
              header: true,
              child: const Text(
                'Page not found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: SaltColors.maroon),
              onPressed: () => context.go('/'),
              child: const Text('Back to recipes'),
            ),
          ],
        ),
      ),
    ),
  );
}
