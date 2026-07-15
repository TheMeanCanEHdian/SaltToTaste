import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// Account tab: identity, change password, active sessions.
class AccountTab extends StatefulWidget {
  const AccountTab({super.key});

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  List<SessionInfo>? _sessions;
  String? _sessionsError;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => _sessionsError = null);
    try {
      final sessions = await context.read<AuthRepository>().listSessions();
      if (mounted) {
        setState(() => _sessions = sessions);
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _sessionsError = exception.message);
      }
    }
  }

  Future<void> _changePassword() async {
    if (_password.text != _confirm.text) {
      setState(() {
        _message = "Passwords don't match.";
        _messageIsError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await context.read<AuthCubit>().changePassword(
            currentPassword: _current.text,
            newPassword: _password.text,
          );
      _current.clear();
      _password.clear();
      _confirm.clear();
      setState(() {
        _message = 'Password changed. Other sessions were signed out.';
        _messageIsError = false;
      });
      await _loadSessions();
    } on RepositoryException catch (exception) {
      setState(() {
        _message = exception.message;
        _messageIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signOutSession(SessionInfo session) async {
    try {
      await context.read<AuthRepository>().deleteSession(session.id);
      if (session.current && mounted) {
        await context.read<AuthCubit>().signOut();
        return;
      }
      await _loadSessions();
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _sessionsError = exception.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthCubit>().user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaneTitle(
          'Account',
          description: user == null
              ? null
              : 'Signed in as ${user.username} · ${user.role}',
        ),
        AuthField(
          label: 'Current password',
          controller: _current,
          obscure: true,
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
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SaltColors.maroon,
              ),
              onPressed: _busy ? null : _changePassword,
              child: const Text('Change password'),
            ),
          ),
        ),
        if (_message != null)
          AuthBanner(message: _message!, warning: !_messageIsError),
        const SizedBox(height: 28),
        const Text(
          'Active sessions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_sessionsError != null)
          ErrorView(message: _sessionsError!, onRetry: _loadSessions)
        else if (_sessions == null)
          const LoadingView()
        else
          for (final session in _sessions!)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: SaltColors.hairline),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                session.userAgent ?? 'Unknown device',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                            if (session.current) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F3E4),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'this device',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2C5A1E),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          'Last seen ${session.lastSeenAt ?? 'just now'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: SaltColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _signOutSession(session),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
