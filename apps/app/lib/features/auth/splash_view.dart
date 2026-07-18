import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';

/// The boot gate shown while auth is still resolving.
///
/// Rendered ABOVE the router (in the app shell's `builder`), not as a `/splash`
/// route, so the browser URL is left untouched while bootstrap runs — a refresh
/// on `/settings` stays on `/settings` instead of flashing through a `/splash`
/// address and back. It shows a spinner while [AuthUnknown] and the failure +
/// retry when bootstrap couldn't reach the server (so users aren't dumped onto
/// a login form that can't succeed, and unclaimed instances aren't hidden from
/// setup).
class SplashView extends StatelessWidget {
  const SplashView({super.key});

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
                FButton(
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => context.read<AuthCubit>().bootstrap(),
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
