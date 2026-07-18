import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

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
    if (_busy) {
      return;
    }
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
      // Band only — no title/subtitle: the brand banner replaces the mark +
      // heading + subtitle on the sign-in card.
      header: const AuthBrandHeader(),
      children: [
        // A single banner slot at the top — the login error and the
        // signed-out notice share the same position (error takes priority).
        if (_error != null)
          AuthBanner(message: _error!, warning: _locked)
        else if (notice != null)
          AuthBanner(message: notice, warning: true),
        AuthField(label: 'Username', controller: _username, autofocus: true),
        AuthField(
          label: 'Password',
          controller: _password,
          obscure: true,
          onSubmitted: (_) => _submit(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          // Forui has no checkbox-tile, so rebuild the single labelled control
          // by hand: a full-width (≥48px) tap target toggles the FCheckbox, and
          // the merged Semantics node (checked state + label text) keeps the
          // screen-reader announcement "Keep me signed in, 90 days, checkbox".
          child: MergeSemantics(
            child: Semantics(
              checked: _remember,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _remember = !_remember),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: FCheckbox(
                          value: _remember,
                          onChange: (value) =>
                              setState(() => _remember = value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Keep me signed in',
                          style: TextStyle(
                            fontSize: 13,
                            color: SaltColors.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '90 days',
                        style: TextStyle(fontSize: 12, color: SaltColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AuthSubmitButton(label: 'Sign in', busy: _busy, onPressed: _submit),
      ],
    );
  }
}
