import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';

/// Account recovery: redeem the single-use code printed by the server-side
/// CLI to re-enable an administrator account and set a new password. Reachable
/// while signed out — it exists precisely for when nobody can sign in.
class RecoverPage extends StatefulWidget {
  const RecoverPage({super.key});

  @override
  State<RecoverPage> createState() => _RecoverPageState();
}

class _RecoverPageState extends State<RecoverPage> {
  final _code = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = "Passwords don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthCubit>().recover(
        recoveryCode: _code.text.trim(),
        username: _username.text.trim(),
        newPassword: _password.text,
      );
      // Success: the router redirects off this page via the auth state.
    } on RepositoryException catch (exception) {
      setState(() => _error = exception.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthCardScaffold(
      title: 'Recover admin access',
      subtitle:
          'Run the recovery tool on the server host: it prints a code that is '
          'good once, for 15 minutes. Being able to run it is the proof you '
          'own this server.',
      children: [
        // A single banner slot at the top, matching the login card.
        if (_error != null) AuthBanner(message: _error!),
        AuthField(
          label: 'Recovery code',
          controller: _code,
          hint: 'e.g. 7GX4-Q2M9',
          // The tool prints to its own stdout, so the code appears in the
          // terminal you run it from — it is NOT in the server's logs, and
          // `docker logs` will never show it.
          helper:
              'Docker: docker exec <container> /app/recover\n'
              'From source: dart run salt_server:recover',
          autofocus: true,
        ),
        AuthField(
          label: 'Username',
          controller: _username,
          helper: 'The admin account to restore, or a new one',
        ),
        AuthField(
          label: 'New password',
          controller: _password,
          obscure: true,
          helper: 'At least 12 characters',
        ),
        AuthField(
          label: 'Confirm new password',
          controller: _confirm,
          obscure: true,
          onSubmitted: (_) => _submit(),
        ),
        AuthSubmitButton(
          label: 'Restore admin access',
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
