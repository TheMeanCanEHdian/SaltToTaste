import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';

/// First-run setup: claim the instance with the code from the server logs
/// and create the administrator account.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
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
    if (_password.text != _confirm.text) {
      setState(() => _error = "Passwords don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthCubit>().completeSetup(
            setupCode: _code.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
          );
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
      title: 'Set up Salt to Taste',
      subtitle: 'Create the administrator account for this server',
      children: [
        AuthField(
          label: 'Setup code',
          controller: _code,
          hint: 'From the server logs, e.g. 7GX4-Q2M9',
          helper: 'Find it with: docker logs salttotaste | grep setup',
          autofocus: true,
        ),
        AuthField(label: 'Username', controller: _username),
        AuthField(
          label: 'Password',
          controller: _password,
          obscure: true,
          helper: 'At least 12 characters',
        ),
        AuthField(
          label: 'Confirm password',
          controller: _confirm,
          obscure: true,
          onSubmitted: (_) => _submit(),
        ),
        AuthSubmitButton(
          label: 'Create admin account',
          busy: _busy,
          onPressed: _submit,
        ),
        if (_error != null) AuthBanner(message: _error!),
      ],
    );
  }
}
