import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/settings/settings_dialogs.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// Users tab (admin): add a user (with a one-time temp password), manage
/// roles/disable, reset passwords. The create form leads; the account list
/// follows. Row actions collapse into a Manage menu, and the consequential
/// ones (reset, disable, role change) confirm first.
class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  // Mirror of the server rule (auth_handlers/user_handlers): 3-32 chars of
  // lowercase letters, digits, underscore, dot, or dash.
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_.-]{3,32}$');

  final _username = TextEditingController();
  String _role = 'member';
  bool _busy = false;
  String? _error;

  List<UserAccount>? _users;

  @override
  void initState() {
    super.initState();
    // Rebuild as the username changes so the inline validation + the Add
    // button's enabled state track the field.
    _username.addListener(_onUsernameChanged);
    _load();
  }

  void _onUsernameChanged() => setState(() {});

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  // The server trims + lowercases before validating, so validate the same
  // normalized value: typing "Alex" is accepted and stored as "alex".
  String get _normalizedUsername => _username.text.trim().toLowerCase();
  bool get _usernameValid => _usernamePattern.hasMatch(_normalizedUsername);

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

  /// Runs a mutation that has no one-time secret to reveal (role, disable),
  /// then refreshes the list.
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

  Future<void> _create() async {
    if (!_usernameValid) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.read<AuthRepository>().createUser(
        username: _username.text.trim(),
        role: _role,
      );
      if (!mounted) {
        return;
      }
      _username.clear();
      await _load();
      if (!mounted) {
        return;
      }
      await showSecretDialog(
        context,
        title: 'Temporary password for ${result.user.username}',
        body:
            "Hand it over now — they'll set their own at first sign-in. "
            "You won't see this again.",
        value: result.tempPassword,
      );
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

  Future<void> _confirmReset(UserAccount user) async {
    final ok = await confirmAction(
      context,
      title: 'Reset password for ${user.username}?',
      message:
          'This signs ${user.username} out everywhere and revokes all of '
          'their API tokens — anything using them stops working until '
          "re-issued. You'll get a new one-time password to hand over.",
      confirmLabel: 'Reset password',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    await _reset(user);
  }

  Future<void> _reset(UserAccount user) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.read<AuthRepository>().resetPassword(user.id);
      if (!mounted) {
        return;
      }
      await _load();
      if (!mounted) {
        return;
      }
      await showSecretDialog(
        context,
        title: 'Temporary password for ${user.username}',
        body:
            "Hand it over now — they'll set their own at first sign-in. "
            "You won't see this again.${revokedTokensNote(result.revokedTokens)}",
        value: result.tempPassword,
      );
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

  Future<void> _confirmRole(UserAccount user) async {
    final toAdmin = user.role != 'admin';
    final ok = await confirmAction(
      context,
      title: toAdmin
          ? 'Make ${user.username} an admin?'
          : 'Make ${user.username} a member?',
      message: toAdmin
          ? 'Admins can edit recipes and manage the server, users, and '
                'tokens.'
          : '${user.username} will lose admin access — editing recipes and '
                'managing the server.',
      confirmLabel: toAdmin ? 'Make admin' : 'Make member',
    );
    if (!ok || !mounted) {
      return;
    }
    await _run(
      () async => context.read<AuthRepository>().patchUser(
        user.id,
        role: toAdmin ? 'admin' : 'member',
      ),
    );
  }

  Future<void> _confirmDisable(UserAccount user) async {
    final ok = await confirmAction(
      context,
      title: 'Disable ${user.username}?',
      message:
          "${user.username} won't be able to sign in until you re-enable the "
          'account.',
      confirmLabel: 'Disable',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    await _setDisabled(user, true);
  }

  Future<void> _setDisabled(UserAccount user, bool disabled) => _run(
    () async =>
        context.read<AuthRepository>().patchUser(user.id, disabled: disabled),
  );

  Future<void> _confirmDelete(UserAccount user) async {
    final ok = await confirmAction(
      context,
      title: 'Delete ${user.username}?',
      message:
          'Permanently removes ${user.username} along with their favorites, '
          "personal notes, API tokens, and sessions. Recipes aren't affected. "
          "This can't be undone — disable the account instead if you might "
          'restore it.',
      confirmLabel: 'Delete account',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    await _run(() async => context.read<AuthRepository>().deleteUser(user.id));
  }

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
        _createCard(),
        // Action errors (e.g. "username already taken") land right under the
        // form that caused them, not at the far bottom of the tab.
        if (_error != null && _users != null) AuthBanner(message: _error!),
        const SizedBox(height: 20),
        if (_users == null && _error != null)
          ErrorView(message: _error!, onRetry: _load)
        else if (_users == null)
          const LoadingView()
        else
          for (final user in _users ?? const <UserAccount>[])
            _userRow(user, selfId),
      ],
    );
  }

  Widget _createCard() {
    final trimmed = _username.text.trim();
    final showError = trimmed.isNotEmpty && !_usernameValid;
    return Container(
      // No top padding: AuthField already insets its label by 14, so
      // EdgeInsets.all(14) here would stack into a gap above the first field.
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
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
            helper: showError
                ? null
                : '3–32 characters · lowercase letters, digits, and . _ - · '
                      'saved lowercase',
            error: showError
                ? 'Use 3–32 lowercase letters, digits, dot, underscore, or '
                      'dash.'
                : null,
            onSubmitted: (_) {
              if (_usernameValid && !_busy) {
                _create();
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              // The Role select carries a label above its field, so bottom-align
              // the button to sit level with the field itself.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FSelect<String>(
                    items: const {
                      'member — browse & favorite': 'member',
                      'admin — full access': 'admin',
                    },
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
                  onPress: (_busy || !_usernameValid) ? null : _create,
                  child: const Text('Add user'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _userRow(UserAccount user, int? selfId) {
    return Container(
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
                    SaltBadge(
                      user.role,
                      tone: user.role == 'admin'
                          ? SaltBadgeTone.brand
                          : SaltBadgeTone.neutral,
                    ),
                    if (user.mustChangePassword) ...[
                      const SizedBox(width: 6),
                      const Tooltip(
                        message: 'Temporary password not yet changed',
                        child: Icon(
                          FLucideIcons.hourglass,
                          size: 15,
                          color: SaltColors.muted,
                        ),
                      ),
                    ],
                    // Disabled accounts also show a strikethrough, but that
                    // reads as nothing to a screen reader — this text carries
                    // the state without relying on style.
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
          if (user.id != selfId) _manageMenu(user),
        ],
      ),
    );
  }

  Widget _manageMenu(UserAccount user) {
    return FPopoverMenu(
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      menuBuilder: (menuContext, controller, _) => [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.key, color: SaltColors.ink),
              title: const Text('Reset password…'),
              onPress: () {
                controller.hide();
                _confirmReset(user);
              },
            ),
            FItem(
              prefix: Icon(
                user.role == 'admin'
                    ? FLucideIcons.arrowDown
                    : FLucideIcons.arrowUp,
                color: SaltColors.ink,
              ),
              title: Text(
                user.role == 'admin' ? 'Make member…' : 'Make admin…',
              ),
              onPress: () {
                controller.hide();
                _confirmRole(user);
              },
            ),
          ],
        ),
        FItemGroup(
          children: [
            if (user.disabled)
              FItem(
                prefix: const Icon(
                  FLucideIcons.circleCheck,
                  color: SaltColors.ink,
                ),
                title: const Text('Enable account'),
                onPress: () {
                  controller.hide();
                  _setDisabled(user, false);
                },
              )
            else
              FItem(
                // Destructive: the theme paints errInk; label it red to match.
                prefix: const Icon(FLucideIcons.ban, color: SaltColors.errInk),
                title: const Text(
                  'Disable account…',
                  style: TextStyle(color: SaltColors.errInk),
                ),
                onPress: () {
                  controller.hide();
                  _confirmDisable(user);
                },
              ),
            FItem(
              prefix: const Icon(FLucideIcons.trash2, color: SaltColors.errInk),
              title: const Text(
                'Delete account…',
                style: TextStyle(color: SaltColors.errInk),
              ),
              onPress: () {
                controller.hide();
                _confirmDelete(user);
              },
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton(
        variant: FButtonVariant.outline,
        size: FButtonSizeVariant.sm,
        mainAxisSize: MainAxisSize.min,
        onPress: _busy ? null : controller.toggle,
        suffix: const Icon(FLucideIcons.chevronDown, size: 16),
        child: const Text('Manage'),
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
