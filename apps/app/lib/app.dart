import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/router/app_router.dart';

/// Root widget: repository provider + maroon-themed Forui/Material shell.
class SaltApp extends StatelessWidget {
  const SaltApp({super.key});

  @override
  Widget build(BuildContext context) {
    final forui = buildForuiTheme();
    return RepositoryProvider(
      create: (_) => RecipeRepository(),
      child: MaterialApp.router(
        title: 'SaltToTaste',
        debugShowCheckedModeBanner: false,
        theme: buildMaterialTheme(forui),
        routerConfig: appRouter,
        builder: (context, child) =>
            FTheme(data: forui, child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
