import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';

/// The maroon top navigation bar: optional back control, logo, search
/// placeholder, menu.
class SaltNavBar extends StatelessWidget implements PreferredSizeWidget {
  const SaltNavBar({super.key, this.showBack = false});

  /// Whether to show a leading back control (used on drill-down pages).
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    return Material(
      color: SaltColors.maroon,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (showBack) ...[
                  IconButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 4),
                ],
                InkWell(
                  onTap: () => context.go('/'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 32,
                      errorBuilder: (_, __, ___) => const Text(
                        'SALT to TASTE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                if (!compact)
                  Expanded(
                    child: Container(
                      height: 38,
                      constraints: const BoxConstraints(maxWidth: 620),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.centerLeft,
                      child: const Text(
                        'Search recipes, ingredients, tags… (coming soon)',
                        style: TextStyle(color: SaltColors.muted, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 12),
                const _AvatarMenu(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Role-aware avatar menu (approved P3 design): username/role header,
/// Settings, Sign out. Members and admins currently share the same entries;
/// admin-only actions (add recipe, import) arrive with their phases.
class _AvatarMenu extends StatelessWidget {
  const _AvatarMenu();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthCubit>().user;
    if (user == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: 'Account menu',
      offset: const Offset(0, 46),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            context.push('/settings');
          case 'signout':
            context.read<AuthCubit>().signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user.username,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SaltColors.ink,
                ),
              ),
              Text(
                user.role,
                style:
                    const TextStyle(fontSize: 12, color: SaltColors.muted),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'settings',
          child: Text('Settings'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'signout',
          child: Text(
            'Sign out',
            style: TextStyle(color: Color(0xFF8A1212)),
          ),
        ),
      ],
      child: CircleAvatar(
        radius: 17,
        backgroundColor: Colors.white,
        child: Text(
          user.username.isEmpty ? '?' : user.username[0].toUpperCase(),
          style: const TextStyle(
            color: SaltColors.maroon,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
