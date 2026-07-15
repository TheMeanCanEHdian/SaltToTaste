import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/dio_client.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/router/app_router.dart';

/// Root widget: one shared HTTP client, repositories, the auth cubit, and
/// the maroon-themed Forui/Material shell around the router.
class SaltApp extends StatefulWidget {
  const SaltApp({super.key});

  @override
  State<SaltApp> createState() => _SaltAppState();
}

class _SaltAppState extends State<SaltApp> {
  late final AuthCubit _authCubit;
  late final RecipeRepository _recipeRepository;
  late final AuthRepository _authRepository;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // The 401 interceptor flips the auth state, which redirects to /login.
    final dio = createDio(onUnauthorized: () => _authCubit.sessionExpired());
    _recipeRepository = RecipeRepository(dio: dio);
    _authRepository = AuthRepository(dio);
    _authCubit = AuthCubit(_authRepository)..bootstrap();
    _router = buildRouter(_authCubit);
  }

  @override
  void dispose() {
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
      ],
      child: BlocProvider.value(
        value: _authCubit,
        child: MaterialApp.router(
          title: 'SaltToTaste',
          debugShowCheckedModeBanner: false,
          theme: buildMaterialTheme(forui),
          routerConfig: _router,
          builder: (context, child) =>
              FTheme(data: forui, child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
