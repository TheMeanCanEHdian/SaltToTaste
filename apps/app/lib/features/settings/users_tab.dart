import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/settings/secret_reveal.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// Users tab (admin): accounts, add user with one-time temp password,
/// role/disable management, password reset.
class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final _username = TextEditingController();
  String _role = 'member';
  bool _busy = false;
  String? _error;
  (String username, String password)? _revealed;

  /// How many API tokens the last reset revoked, or null when [_revealed] came
  /// from creating a user (which revokes nothing).
  int? _revokedTokens;

  List<UserAccount>? _users;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final users = await context.read<AuthRepository>().listUsers();
      if (mounted) {
        setState(() => _users = users);
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _error = exception.message);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) {
        return;
      }
      await _load();
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _error = exception.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create() => _run(() async {
    final username = _username.text.trim();
    final result = await context.read<AuthRepository>().createUser(
      username: username,
      role: _role,
    );
    if (!mounted) {
      return;
    }
    _username.clear();
    setState(() {
      _revealed = (result.user.username, result.tempPassword);
      // A new user has no tokens to revoke; clear any count left by a reset.
      _revokedTokens = null;
    });
  });

  Future<void> _reset(UserAccount user) => _run(() async {
    final result = await context.read<AuthRepository>().resetPassword(user.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _revealed = (user.username, result.tempPassword);
      _revokedTokens = result.revokedTokens;
    });
  });

  @override
  Widget build(BuildContext context) {
    final selfId = context.watch<AuthCubit>().user?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PaneTitle(
          'Users',
          description:
              'Members can browse and favorite recipes. Admins can '
              'edit recipes and manage the server.',
        ),
        if (_users == null && _error != null)
          ErrorView(message: _error!, onRetry: _load)
        else if (_users == null)
          const LoadingView()
        else
          for (final user in _users ?? const <UserAccount>[])
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: SaltColors.hairline)),
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
                                user.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: user.disabled
                                      ? SaltColors.muted
                                      : SaltColors.ink,
                                  decoration: user.disabled
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _RoleBadge(role: user.role),
                            if (user.mustChangePassword) ...[
                              const SizedBox(width: 6),
                              const Tooltip(
                                message: 'Temporary password not yet changed',
                                child: Icon(
                                  Icons.hourglass_bottom,
                                  size: 15,
                                  color: SaltColors.muted,
                                ),
                              ),
                            ],
                            // Disabled accounts also show a strikethrough, but
                            // that reads as nothing to a screen reader — this
                            // text carries the state without relying on style.
                            if (user.disabled) ...[
                              const SizedBox(width: 6),
                              const Text(
                                'disabled',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: SaltColors.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          user.id == selfId
                              ? "that's you"
                              : 'last active ${user.lastActiveAt ?? 'never'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: SaltColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (user.id != selfId) ...[
                    _SmallAction(
                      label: 'Reset password',
                      onTap: _busy ? null : () => _reset(user),
                    ),
                    _SmallAction(
                      label: user.role == 'admin'
                          ? 'Make member'
                          : 'Make admin',
                      onTap: _busy
                          ? null
                          : () => _run(
                              () async =>
                                  context.read<AuthRepository>().patchUser(
                                    user.id,
                                    role: user.role == 'admin'
                                        ? 'member'
                                        : 'admin',
                                  ),
                            ),
                    ),
                    _SmallAction(
                      label: user.disabled ? 'Enable' : 'Disable',
                      danger: !user.disabled,
                      onTap: _busy
                          ? null
                          : () => _run(
                              () async => context
                                  .read<AuthRepository>()
                                  .patchUser(user.id, disabled: !user.disabled),
                            ),
                    ),
                  ],
                ],
              ),
            ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFDFBF9),
            border: Border.all(color: SaltColors.hairline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthField(
                label: 'Username',
                controller: _username,
                hint: 'e.g. alex',
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FSelect<String>(
                        items: const {'member': 'member', 'admin': 'admin'},
                        control: FSelectControl.lifted(
                          value: _role,
                          onChange: (value) =>
                              setState(() => _role = value ?? 'member'),
                        ),
                        label: const Text('Role'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FButton(
                      mainAxisSize: MainAxisSize.min,
                      onPress: _busy ? null : _create,
                      child: const Text('Add user'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_revealed != null)
          SecretReveal(
            title:
                'Temporary password for ${_revealed!.$1} — hand it over '
                "now; they'll set their own at first sign-in."
                '${revokedTokensNote(_revokedTokens)}',
            value: _revealed!.$2,
          ),
        if (_error != null) AuthBanner(message: _error!),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final admin = role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: admin ? SaltColors.maroon : SaltColors.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: admin ? Colors.white : SaltColors.chipInk,
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.label, this.onTap, this.danger = false});

  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: FButton(
        variant: danger ? FButtonVariant.destructive : FButtonVariant.outline,
        size: FButtonSizeVariant.sm,
        mainAxisSize: MainAxisSize.min,
        onPress: onTap,
        child: Text(label),
      ),
    );
  }
}

/// Says what a password reset took away, as well as what it gave.
///
/// A reset signs the user out everywhere, and "everywhere" includes revoking
/// every one of their API tokens — a PAT is its own credential, so a reset
/// that only dropped sessions left an attacker's token frozen rather than
/// gone. That is irreversible, and the admin did not separately ask for it.
/// The server has always reported `revoked_tokens`; the client dropped it, so
/// the first anyone knew was an integration going dark.
///
/// Returns empty for null (a newly created user has no tokens) and for zero —
/// "0 API tokens revoked" is noise on the common path.
String revokedTokensNote(int? revoked) {
  if (revoked == null || revoked == 0) {
    return '';
  }
  final plural = revoked == 1 ? 'API token was' : 'API tokens were';
  return ' Their $revoked $plural revoked too, and anything using them will '
      'need a new one.';
}
