import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

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
                Tooltip(
                  message: 'Menu — coming soon',
                  child: IconButton(
                    onPressed: null,
                    icon: const Icon(Icons.menu, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
