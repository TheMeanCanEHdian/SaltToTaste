import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/dio_client.dart';
import 'package:salt_app/core/api/import_repository.dart';
import 'package:salt_app/core/api/library_repository.dart';
import 'package:salt_app/core/api/logs_repository.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/auth/splash_view.dart';
import 'package:salt_app/features/editor/editor_exit_guard.dart';
import 'package:salt_app/features/recipes/list/recipe_layout_cubit.dart';
import 'package:salt_app/features/tags/tag_styles_cubit.dart';
import 'package:salt_app/router/app_router.dart';

/// Whether auth is still resolving — bootstrap in flight, or failed with a
/// retry offered. In both states the shell shows [SplashView] over the router.
bool _isResolving(AuthState state) =>
    state is AuthUnknown || state is AuthBootstrapFailed;

/// Root widget: one shared HTTP client, repositories, the auth cubit, and
/// the maroon-themed Forui/Material shell around the router.
class SaltApp extends StatefulWidget {
  const SaltApp({super.key, this.prefs});

  /// Loaded preferences (list-layout choice). Null if unavailable — the app
  /// then runs with in-memory defaults.
  final SharedPreferences? prefs;

  @override
  State<SaltApp> createState() => _SaltAppState();
}

class _SaltAppState extends State<SaltApp> {
  late final AuthCubit _authCubit;
  late final RecipeRepository _recipeRepository;
  late final AuthRepository _authRepository;
  late final TagsRepository _tagsRepository;
  late final LibraryRepository _libraryRepository;
  late final NutritionRepository _nutritionRepository;
  late final ImportRepository _importRepository;
  late final LogsRepository _logsRepository;
  late final TagStylesCubit _tagStylesCubit;
  final EditorExitGuard _editorExitGuard = EditorExitGuard();
  late final GoRouter _router;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // The 401 interceptor flips the auth state, which redirects to /login.
    final dio = createDio(onUnauthorized: () => _authCubit.sessionExpired());
    _recipeRepository = RecipeRepository(dio: dio);
    _authRepository = AuthRepository(dio);
    _tagsRepository = TagsRepository(dio);
    _libraryRepository = LibraryRepository(dio);
    _nutritionRepository = NutritionRepository(dio);
    _importRepository = ImportRepository(dio);
    _logsRepository = LogsRepository(dio);
    _tagStylesCubit = TagStylesCubit(_tagsRepository);
    _authCubit = AuthCubit(_authRepository)..bootstrap();
    // Chip styles follow the session: load on sign-in, drop on sign-out.
    _authSubscription = _authCubit.stream.listen((state) {
      if (state is AuthSignedIn) {
        _tagStylesCubit.load();
      } else if (state is AuthSignedOut) {
        _tagStylesCubit.clear();
      }
    });
    _router = buildRouter(_authCubit, _editorExitGuard);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _tagStylesCubit.close();
    _authCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final forui = buildForuiTheme();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: _recipeRepository),
        RepositoryProvider.value(value: _authRepository),
        RepositoryProvider.value(value: _tagsRepository),
        RepositoryProvider.value(value: _libraryRepository),
        RepositoryProvider.value(value: _nutritionRepository),
        RepositoryProvider.value(value: _importRepository),
        RepositoryProvider.value(value: _logsRepository),
        RepositoryProvider.value(value: _editorExitGuard),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _authCubit),
          BlocProvider.value(value: _tagStylesCubit),
          // List layout (grid/list), shared across the home, search, and
          // favorites lists and persisted via prefs.
          BlocProvider(create: (_) => RecipeLayoutCubit(widget.prefs)),
        ],
        child: MaterialApp.router(
          title: 'SaltToTaste',
          debugShowCheckedModeBanner: false,
          theme: buildMaterialTheme(forui),
          routerConfig: _router,
          // FToaster hosts showFToast (used by library/recipe/nutrition
          // toasts); it throws without an ancestor, and FScaffold does not
          // provide one — so mount it once here, below FTheme.
          builder: (context, child) => FTheme(
            data: forui,
            child: FToaster(
              // While auth is resolving, paint the splash OVER the router
              // instead of routing to a `/splash` URL. The router child is not
              // mounted until the state is known, so the destination page never
              // builds (or fires requests) mid-bootstrap, and the address bar
              // stays on the loaded URL rather than flashing through /splash.
              child: BlocBuilder<AuthCubit, AuthState>(
                buildWhen: (previous, current) =>
                    _isResolving(previous) != _isResolving(current),
                builder: (context, state) => _isResolving(state)
                    ? const SplashView()
                    : (child ?? const SizedBox.shrink()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
