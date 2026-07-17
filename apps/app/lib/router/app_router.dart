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

/// Wraps [child] in the app's page transition: a short cross-fade.
///
/// Every route uses this instead of a bare `builder:`, which would take
/// Material 3's default zoom — a big, springy scale that reads as a phone
/// animation and is especially wrong on the wide home → search jump, where
/// most of the frame is unchanged chrome.
///
/// [state] is required for its `pageKey`, which is not optional dressing:
/// `builder:` supplies it for free, and without it every page here would have
/// `key == null`, so `Page.canUpdate` returns true for ANY two pages. The
/// Navigator would then reuse the existing route entry instead of pushing a
/// new one — and a reused entry runs no transition at all. The fade would be
/// dead on exactly the `context.go()` navigations this exists for (home →
/// search among them), while still animating on `context.push()` and so
/// looking fine in a spot check.
///
/// The fade is deliberately quicker than Material's 300ms default: this is a
/// library you page through, so the transition should get out of the way. It
/// is the only motion between pages, so it also has to honour a reduced-motion
/// preference — [MediaQuery.disableAnimationsOf] covers both the OS setting
/// and the browser's `prefers-reduced-motion`.
/// The real [_fadePage], for tests.
///
/// Exported because the alternative — a copy of it in the test file — is
/// exactly how the dead-fade bug survived: the test passed against its own
/// copy while the shipped router had no `key` and ran no transition at all.
/// A test must drive THIS function or it proves nothing.
@visibleForTesting
Page<void> fadePageForTest(GoRouterState state, Widget child) =>
    _fadePage(state, child);

Page<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      name: state.name ?? state.uri.path,
      arguments: state.extra,
      restorationId: state.pageKey.value,
      child: child,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.disableAnimationsOf(context)) {
          return child;
        }
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );

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
        pageBuilder: (context, state) => _fadePage(state, const _SplashPage()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadePage(state, const LoginPage()),
      ),
      GoRoute(
        path: '/setup',
        pageBuilder: (context, state) => _fadePage(state, const SetupPage()),
      ),
      GoRoute(
        path: '/recover',
        pageBuilder: (context, state) => _fadePage(state, const RecoverPage()),
      ),
      GoRoute(
        path: '/change-password',
        pageBuilder: (context, state) =>
            _fadePage(state, const ChangePasswordPage()),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _fadePage(state, const HomePage()),
      ),
      GoRoute(
        path: '/new',
        pageBuilder: (context, state) => _fadePage(state, const EditorPage()),
      ),
      GoRoute(
        path: '/favorites',
        pageBuilder: (context, state) =>
            _fadePage(state, const FavoritesPage()),
      ),
      GoRoute(
        path: '/r/:slug',
        pageBuilder: (context, state) => _fadePage(
          state,
          RecipeDetailPage(slug: state.pathParameters['slug']!),
        ),
      ),
      GoRoute(
        path: '/r/:slug/edit',
        pageBuilder: (context, state) =>
            _fadePage(state, EditorPage(slug: state.pathParameters['slug']!)),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) => _fadePage(
          state,
          SearchPage(query: state.uri.queryParameters['q'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _fadePage(state, const SettingsPage()),
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
