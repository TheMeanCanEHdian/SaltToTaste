import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart'
    show RepositoryException;
import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/async_view.dart';
import 'package:salt_app/features/auth/auth_card.dart';
import 'package:salt_app/features/settings/secret_reveal.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// API tokens tab: list, mint (with one-time reveal), revoke.
class TokensTab extends StatefulWidget {
  const TokensTab({super.key});

  @override
  State<TokensTab> createState() => _TokensTabState();
}

class _TokensTabState extends State<TokensTab> {
  final _name = TextEditingController();
  String _scope = 'read';
  bool _busy = false;
  String? _error;
  String? _revealedToken;

  List<TokenInfo>? _tokens;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

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
    setState(() {
      _busy = true;
      _error = null;
      _revealedToken = null;
    });
    try {
      final result = await context.read<AuthRepository>().createToken(
        name: _name.text.trim(),
        scope: _scope,
      );
      if (!mounted) {
        return;
      }
      _name.clear();
      setState(() => _revealedToken = result.token);
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
        const PaneTitle(
          'API tokens',
          description:
              'Tokens act as you — the credential for native apps '
              'and scripts. Revoke any you no longer use.',
        ),
        if (_tokens == null && _error != null)
          ErrorView(message: _error!, onRetry: _load)
        else if (_tokens == null)
          const LoadingView()
        else ...[
          for (final token in _tokens ?? const <TokenInfo>[])
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
                            _ScopeBadge(scope: token.scope),
                          ],
                        ),
                        Text(
                          token.revoked
                              ? 'Revoked'
                              : 'stt_pat_${token.prefix}…  ·  last used '
                                    '${token.lastUsedAt ?? 'never'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: SaltColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!token.revoked)
                    FButton(
                      variant: FButtonVariant.destructive,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () => _revoke(token),
                      child: const Text('Revoke'),
                    ),
                ],
              ),
            ),
          if ((_tokens ?? const []).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No tokens yet.',
                style: TextStyle(color: SaltColors.muted, fontSize: 13.5),
              ),
            ),
        ],
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
                label: 'Token name',
                controller: _name,
                hint: 'e.g. iPhone app',
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  // Bottom-align the button to the Scope select's field (the
                  // select is taller by its label), not the labelled column.
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
                      onPress: _busy ? null : _create,
                      child: const Text('Create token'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_revealedToken != null)
          SecretReveal(
            title: "Token created — copy it now. You won't see it again.",
            value: _revealedToken!,
          ),
        if (_error != null) AuthBanner(message: _error!),
      ],
    );
  }
}

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final read = scope == 'read';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: read ? const Color(0xFFECE9F7) : const Color(0xFFFDF1E2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        scope,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: read ? const Color(0xFF4B3D8F) : const Color(0xFF8A5A12),
        ),
      ),
    );
  }
}
