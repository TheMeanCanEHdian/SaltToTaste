import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';

/// Sign-in card (approved P3 design) with error and lockout banners.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _remember = true;
  bool _busy = false;
  String? _error;
  bool _locked = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _locked = false;
    });
    try {
      await context.read<AuthCubit>().login(
            username: _username.text.trim(),
            password: _password.text,
            remember: _remember,
          );
      // Success: the router redirects off this page via the auth state.
    } on RepositoryException catch (exception) {
      setState(() {
        _error = exception.message;
        _locked = exception.code == 'locked';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = switch (context.watch<AuthCubit>().state) {
      AuthSignedOut(:final notice) => notice,
      _ => null,
    };
    return AuthCardScaffold(
      title: 'Salt to Taste',
      subtitle: 'Sign in to your household recipe library',
      children: [
        if (notice != null && _error == null)
          AuthBanner(message: notice, warning: true),
        AuthField(
          label: 'Username',
          controller: _username,
          autofocus: true,
        ),
        AuthField(
          label: 'Password',
          controller: _password,
          obscure: true,
          onSubmitted: (_) => _submit(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _remember,
                  activeColor: SaltColors.maroon,
                  onChanged: (value) =>
                      setState(() => _remember = value ?? false),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Keep me signed in',
                  style: TextStyle(fontSize: 13, color: SaltColors.muted),
                ),
              ),
              const Text(
                '90 days',
                style: TextStyle(fontSize: 12, color: SaltColors.muted),
              ),
            ],
          ),
        ),
        AuthSubmitButton(label: 'Sign in', busy: _busy, onPressed: _submit),
        if (_error != null) AuthBanner(message: _error!, warning: _locked),
      ],
    );
  }
}
