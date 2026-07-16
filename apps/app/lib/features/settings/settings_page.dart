import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/settings/account_tab.dart';
import 'package:salt_app/features/settings/import_tab.dart';
import 'package:salt_app/features/settings/library_tab.dart';
import 'package:salt_app/features/settings/nutrition_tab.dart';
import 'package:salt_app/features/settings/tags_tab.dart';
import 'package:salt_app/features/settings/tokens_tab.dart';
import 'package:salt_app/features/settings/users_tab.dart';

enum SettingsTab { account, users, tokens, tags, library, nutrition, import }

/// Settings shell (approved P3 design): left sidebar on wide screens,
/// horizontal chips on narrow. Members see Account and API tokens; admins
/// also see Users plus placeholders for later server tabs.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsTab _tab = SettingsTab.account;

  static const _futureServerTabs = <String>[];

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthCubit>().user?.isAdmin ?? false;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.detailTwoColumn;
    final content = switch (_tab) {
      SettingsTab.account => const AccountTab(),
      SettingsTab.users => const UsersTab(),
      SettingsTab.tokens => const TokensTab(),
      SettingsTab.tags => const TagsTab(),
      SettingsTab.library => const LibraryTab(),
      SettingsTab.nutrition => const NutritionTab(),
      SettingsTab.import => const ImportTab(),
    };

    return Scaffold(
      appBar: const SaltNavBar(showBack: true),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: SaltColors.hairline),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 230, child: _sidebar(isAdmin)),
                        const VerticalDivider(
                          width: 1,
                          color: SaltColors.hairline,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: content,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _chips(isAdmin),
                        const Divider(height: 1, color: SaltColors.hairline),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(18),
                            child: content,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  List<(SettingsTab, String)> _tabsFor(bool isAdmin) => [
        (SettingsTab.account, 'Account'),
        if (isAdmin) (SettingsTab.users, 'Users'),
        (SettingsTab.tokens, 'API tokens'),
      ];

  /// Server-administration tabs (admins only).
  List<(SettingsTab, String)> _serverTabsFor(bool isAdmin) => [
        if (isAdmin) ...[
          (SettingsTab.tags, 'Tags'),
          (SettingsTab.library, 'Library'),
          (SettingsTab.nutrition, 'Nutrition'),
          (SettingsTab.import, 'Import'),
        ],
      ];

  Widget _sidebar(bool isAdmin) {
    return Container(
      color: const Color(0xFFFDFBF9),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SideGroupLabel('You'),
          for (final (tab, label) in _tabsFor(isAdmin))
            _SideItem(
              label: label,
              active: _tab == tab,
              onTap: () => setState(() => _tab = tab),
            ),
          if (isAdmin) ...[
            const _SideGroupLabel('Server'),
            for (final (tab, label) in _serverTabsFor(isAdmin))
              _SideItem(
                label: label,
                active: _tab == tab,
                onTap: () => setState(() => _tab = tab),
              ),
            for (final label in _futureServerTabs)
              _SideItem(label: label, comingSoon: true),
          ],
        ],
      ),
    );
  }

  Widget _chips(bool isAdmin) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (final (tab, label) in [
            ..._tabsFor(isAdmin),
            ..._serverTabsFor(isAdmin),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _tab == tab,
                selectedColor: SaltColors.chip,
                onSelected: (_) => setState(() => _tab = tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _SideGroupLabel extends StatelessWidget {
  const _SideGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w700,
          color: SaltColors.muted,
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.label,
    this.active = false,
    this.comingSoon = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final bool comingSoon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: comingSoon ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: active
            ? const BoxDecoration(
                color: SaltColors.chip,
                border: Border(
                  right: BorderSide(color: SaltColors.maroon, width: 3),
                ),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: comingSoon
                      ? SaltColors.muted
                      : active
                          ? SaltColors.chipInk
                          : SaltColors.ink,
                ),
              ),
            ),
            if (comingSoon)
              const Text(
                'soon',
                style: TextStyle(fontSize: 11, color: SaltColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shared section heading inside settings panes.
class PaneTitle extends StatelessWidget {
  const PaneTitle(this.title, {super.key, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: SaltColors.maroon,
          ),
        ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              description!,
              style:
                  const TextStyle(fontSize: 13.5, color: SaltColors.muted),
            ),
          ),
        const SizedBox(height: 18),
      ],
    );
  }
}
