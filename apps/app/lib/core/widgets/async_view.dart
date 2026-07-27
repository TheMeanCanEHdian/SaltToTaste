import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

/// Standard loading spinner, centered.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(48),
      child: CircularProgressIndicator(
        color: SaltColors.maroon,
        semanticsLabel: 'Loading',
      ),
    ),
  );
}

/// Standard friendly error state with a retry action.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              FLucideIcons.utensils,
              size: 40,
              color: SaltColors.rose,
              semanticLabel: 'Something went wrong',
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: SaltColors.ink),
              ),
            ),
            const SizedBox(height: 16),
            FButton(
              mainAxisSize: MainAxisSize.min,
              onPress: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
