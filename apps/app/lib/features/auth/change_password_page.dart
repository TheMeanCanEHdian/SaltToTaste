import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';

/// Forced password change after a temporary password (admin-created account
/// or reset). The router keeps the user here until it succeeds.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
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
      await context.read<AuthCubit>().changePassword(
        newPassword: _password.text,
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
    final username = context.watch<AuthCubit>().user?.username ?? '';
    return AuthCardScaffold(
      title: 'Choose a new password',
      subtitle:
          'Signed in as $username with a temporary password — set your '
          'own to continue',
      children: [
        AuthField(
          label: 'New password',
          controller: _password,
          obscure: true,
          helper: 'At least 12 characters',
          autofocus: true,
        ),
        AuthField(
          label: 'Confirm password',
          controller: _confirm,
          obscure: true,
          onSubmitted: (_) => _submit(),
        ),
        AuthSubmitButton(
          label: 'Set password',
          busy: _busy,
          onPressed: _submit,
        ),
        if (_error != null) AuthBanner(message: _error!),
      ],
    );
  }
}
