import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/util/timestamps.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/core/widgets/salt_badge.dart';
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/settings/settings_dialogs.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// API tokens tab: mint (with a one-time reveal), list, revoke. The create
/// form leads; the list follows. Mirrors the server's rules — a 1-60 char
/// name and a cap of [_maxActiveTokens] live tokens per user.
class TokensTab extends StatefulWidget {
  const TokensTab({super.key});

  @override
  State<TokensTab> createState() => _TokensTabState();
}

class _TokensTabState extends State<TokensTab> {
  // Server cap (token_handlers.maxActiveTokensPerUser). Surfaced so the limit
  // is visible before it's hit, not just as an error on submit.
  static const int _maxActiveTokens = 20;
  static const int _maxNameLength = 60;

  final _name = TextEditingController();
  String _scope = 'read';
  bool _busy = false;
  String? _error;

  List<TokenInfo>? _tokens;

  @override
  void initState() {
    super.initState();
    // Rebuild as the name changes so the inline validation + the Create
    // button's enabled state track the field.
    _name.addListener(_onNameChanged);
    _load();
  }

  void _onNameChanged() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  int get _activeCount =>
      (_tokens ?? const <TokenInfo>[]).where((t) => !t.revoked).length;
  bool get _atCap => _tokens != null && _activeCount >= _maxActiveTokens;

  String get _trimmedName => _name.text.trim();
  bool get _nameTooLong => _trimmedName.length > _maxNameLength;
  bool get _canCreate =>
      !_busy && !_atCap && _trimmedName.isNotEmpty && !_nameTooLong;

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final tokens = await context.read<AuthRepository>().listTokens();
      if (mounted) {
        setState(() => _tokens = tokens);
      }
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _error = exception.message);
      }
    }
  }

  Future<void> _create() async {
    if (!_canCreate) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.read<AuthRepository>().createToken(
        name: _trimmedName,
        scope: _scope,
      );
      if (!mounted) {
        return;
      }
      _name.clear();
      await _load();
      if (!mounted) {
        return;
      }
      await showSecretDialog(
        context,
        title: 'Token created',
        body:
            "Copy it now — you won't see it again. Send it as a Bearer token "
            'or PAT from your app or script.',
        value: result.token,
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

  Future<void> _confirmRevoke(TokenInfo token) async {
    final ok = await confirmAction(
      context,
      title: 'Revoke "${token.name}"?',
      message:
          'Anything using this token stops working immediately. This '
          "can't be undone.",
      confirmLabel: 'Revoke',
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    await _revoke(token);
  }

  Future<void> _revoke(TokenInfo token) async {
    try {
      await context.read<AuthRepository>().revokeToken(token.id);
      if (!mounted) {
        return;
      }
      await _load();
    } on RepositoryException catch (exception) {
      if (mounted) {
        setState(() => _error = exception.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: PaneTitle(
                'API Tokens',
                description:
                    'Tokens act as you — the credential for native apps '
                    'and scripts. Revoke any you no longer use.',
              ),
            ),
            if (_tokens != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 8),
                child: Text(
                  '$_activeCount of $_maxActiveTokens active',
                  style: const TextStyle(fontSize: 12, color: SaltColors.muted),
                ),
              ),
          ],
        ),
        _createCard(),
        if (_error != null && _tokens != null) AuthBanner(message: _error!),
        const SizedBox(height: 20),
        if (_tokens == null && _error != null)
          ErrorView(message: _error!, onRetry: _load)
        else if (_tokens == null)
          const LoadingView()
        else if ((_tokens ?? const []).isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No tokens yet.',
              style: TextStyle(color: SaltColors.muted, fontSize: 13.5),
            ),
          )
        else
          for (final token in _tokens ?? const <TokenInfo>[]) _tokenRow(token),
      ],
    );
  }

  Widget _createCard() {
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
            label: 'Token name',
            controller: _name,
            hint: 'e.g. iPhone app',
            helper: _nameTooLong ? null : '1–$_maxNameLength characters',
            error: _nameTooLong
                ? 'Token name must be 1–$_maxNameLength characters.'
                : null,
            onSubmitted: (_) {
              if (_canCreate) {
                _create();
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              // Bottom-align the button to the Scope select's field (the select
              // is taller by its label), not the labelled column.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FSelect<String>(
                    items: const {
                      'read — browse and favorites': 'read',
                      'full — everything my role allows': 'full',
                    },
                    control: FSelectControl.lifted(
                      value: _scope,
                      onChange: (value) =>
                          setState(() => _scope = value ?? 'read'),
                    ),
                    label: const Text('Scope'),
                  ),
                ),
                const SizedBox(width: 12),
                FButton(
                  mainAxisSize: MainAxisSize.min,
                  onPress: _canCreate ? _create : null,
                  child: const Text('Create token'),
                ),
              ],
            ),
          ),
          if (_atCap)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'You have the maximum of $_maxActiveTokens active tokens. '
                'Revoke one to add another.',
                style: TextStyle(fontSize: 12, color: SaltColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  /// A live token shows its last-used time; a revoked one shows "Revoked" plus
  /// a countdown to when the retention prune removes it (when there is one).
  Widget _subtitle(TokenInfo token) {
    const style = TextStyle(fontSize: 12, color: SaltColors.muted);
    if (!token.revoked) {
      return Text(
        'last used ${token.lastUsedAt == null ? 'never' : formatTimestamp(token.lastUsedAt!)}',
        style: style,
      );
    }
    final countdown = _deletesInLabel(token.deletesAt);
    if (countdown == null) {
      return const Text('Revoked', style: style);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Revoked  ·  ', style: style),
        const Icon(FLucideIcons.clock, size: 12, color: SaltColors.muted),
        const SizedBox(width: 4),
        Text(countdown, style: style),
      ],
    );
  }

  /// Humanized time until a revoked token is pruned, or null when there is no
  /// scheduled deletion (retention set to "keep forever").
  static String? _deletesInLabel(String? deletesAtIso) {
    if (deletesAtIso == null) {
      return null;
    }
    final deletesAt = DateTime.tryParse(deletesAtIso);
    if (deletesAt == null) {
      return null;
    }
    final remaining = deletesAt.difference(DateTime.now());
    if (remaining.inMinutes < 1) {
      return 'deletes soon';
    }
    if (remaining.inHours < 1) {
      return 'deletes in ${remaining.inMinutes} min';
    }
    if (remaining.inHours < 24) {
      final h = remaining.inHours;
      return 'deletes in $h ${h == 1 ? 'hour' : 'hours'}';
    }
    final d = remaining.inDays;
    return 'deletes in $d ${d == 1 ? 'day' : 'days'}';
  }

  Widget _tokenRow(TokenInfo token) {
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
                        token.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: token.revoked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SaltBadge(
                      token.scope,
                      tone: token.scope == 'read'
                          ? SaltBadgeTone.info
                          : SaltBadgeTone.warn,
                    ),
                  ],
                ),
                _subtitle(token),
              ],
            ),
          ),
          if (!token.revoked)
            FButton(
              variant: FButtonVariant.destructive,
              size: FButtonSizeVariant.sm,
              mainAxisSize: MainAxisSize.min,
              onPress: () => _confirmRevoke(token),
              child: const Text('Revoke'),
            ),
        ],
      ),
    );
  }
}
