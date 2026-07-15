import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/recipes/detail/recipe_detail_page.dart';
import 'package:salt_app/features/recipes/list/home_page.dart';

/// Application routes: `/` (grid) and `/r/:slug` (detail).
final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(
      path: '/r/:slug',
      builder: (context, state) =>
          RecipeDetailPage(slug: state.pathParameters['slug']!),
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
            style: FilledButton.styleFrom(backgroundColor: SaltColors.maroon),
            onPressed: () => context.go('/'),
            child: const Text('Back to recipes'),
          ),
        ],
      ),
    ),
  ),
);
