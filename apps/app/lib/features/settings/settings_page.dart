import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_nav_bar.dart';
import 'package:salt_app/features/auth/auth_cubit.dart';
import 'package:salt_app/features/settings/account_tab.dart';
import 'package:salt_app/features/settings/import_tab.dart';
import 'package:salt_app/features/settings/library_tab.dart';
import 'package:salt_app/features/settings/logs_tab.dart';
import 'package:salt_app/features/settings/nutrition_tab.dart';
import 'package:salt_app/features/settings/tags_tab.dart';
import 'package:salt_app/features/settings/tokens_tab.dart';
import 'package:salt_app/features/settings/users_tab.dart';

enum SettingsTab {
  account,
  users,
  tokens,
  tags,
  library,
  nutrition,
  import,
  logs,
}

/// Tabs a non-admin (member) may see; everything else is admin-only.
const Set<SettingsTab> _memberTabs = {SettingsTab.account, SettingsTab.tokens};

/// The tab a `/settings#<fragment>` URL selects, restricted to what [isAdmin]
/// can see. An unrecognised fragment — including an admin-only tab requested by
/// a member — falls back to [SettingsTab.account].
SettingsTab settingsTabForFragment(String fragment, {required bool isAdmin}) {
  for (final tab in SettingsTab.values) {
    if (tab.name == fragment) {
      return isAdmin || _memberTabs.contains(tab) ? tab : SettingsTab.account;
    }
  }
  return SettingsTab.account;
}

/// Cross-fades the settings pane when the tab changes, matching the page
/// transition (`_fadePage`: 180/140ms, easeOut). [contentKey] must differ per
/// tab so [AnimatedSwitcher] treats each pane as a new child; it skips its FIRST
/// child, so opening settings doesn't double-fade over the page's own fade.
/// [reduceMotion] (the OS/browser preference) collapses it to an instant swap.
///
/// Top-level and reused by [SettingsPage.build] AND its test on purpose: the
/// test must drive THIS builder, not a copy — a copy is exactly how the page
/// fade once shipped dead (see router_transition_test).
Widget settingsTabTransition({
  required bool reduceMotion,
  required Key contentKey,
  required Widget child,
}) {
  return AnimatedSwitcher(
    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
    reverseDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 140),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeOut,
    // Stack the panes top-left (they are top-aligned content); the default
    // AnimatedSwitcher layout centres, which would make a shorter/taller pane
    // hop during the fade.
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topLeft,
      children: [...previous, if (current != null) current],
    ),
    child: KeyedSubtree(key: contentKey, child: child),
  );
}

/// Settings shell (approved P3 design): left sidebar on wide screens,
/// horizontal chips on narrow. Members see Account and API tokens; admins
/// also see Users plus placeholders for later server tabs.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.tab = ''});

  /// The URL fragment that selects the active tab (`/settings#tags`). Empty or
  /// unrecognised — including an admin-only tab requested by a member — falls
  /// back to Account.
  final String tab;

  static const _futureServerTabs = <String>[];

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthCubit>().user?.isAdmin ?? false;
    final wide =
        MediaQuery.sizeOf(context).width >= Breakpoints.detailTwoColumn;
    // The active tab is derived from the URL fragment, restricted to the tabs
    // this role can actually see; anything else falls back to Account.
    final active = settingsTabForFragment(tab, isAdmin: isAdmin);
    final content = switch (active) {
      SettingsTab.account => const AccountTab(),
      SettingsTab.users => const UsersTab(),
      SettingsTab.tokens => const TokensTab(),
      SettingsTab.tags => const TagsTab(),
      SettingsTab.library => const LibraryTab(),
      SettingsTab.nutrition => const NutritionTab(),
      SettingsTab.import => const ImportTab(),
      SettingsTab.logs => const LogsTab(),
    };
    // Cross-fade the pane when the tab changes, matching the page transition.
    final tabView = settingsTabTransition(
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      contentKey: ValueKey(active),
      child: content,
    );

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
                borderRadius: BorderRadius.circular(16),
              ),
              // Foreground border so the sidebar's fill can't cover the
              // outline at the left corners (see the same fix in logs_tab).
              foregroundDecoration: BoxDecoration(
                border: Border.all(color: SaltColors.hairline),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 230,
                          child: _sidebar(context, isAdmin, active),
                        ),
                        const VerticalDivider(
                          width: 1,
                          color: SaltColors.hairline,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: tabView,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _chips(context, isAdmin, active),
                        const Divider(height: 1, color: SaltColors.hairline),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(18),
                            child: tabView,
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

  /// Selects [tab] by updating the URL fragment. `replace` reuses the settings
  /// page in place (no transition, state kept), and [Router.neglect] makes the
  /// URL change a browser history REPLACE rather than a push — so cycling
  /// through tabs doesn't pile up history entries, and a single browser Back
  /// still leaves settings — while each tab stays linkable (`/settings#tags`).
  void _select(BuildContext context, SettingsTab tab) =>
      Router.neglect(context, () => context.replace('/settings#${tab.name}'));

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
      (SettingsTab.logs, 'Logs'),
    ],
  ];

  Widget _sidebar(BuildContext context, bool isAdmin, SettingsTab active) {
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
              active: active == tab,
              onTap: () => _select(context, tab),
            ),
          if (isAdmin) ...[
            const _SideGroupLabel('Server'),
            for (final (tab, label) in _serverTabsFor(isAdmin))
              _SideItem(
                label: label,
                active: active == tab,
                onTap: () => _select(context, tab),
              ),
            for (final label in _futureServerTabs)
              _SideItem(label: label, comingSoon: true),
          ],
        ],
      ),
    );
  }

  Widget _chips(BuildContext context, bool isAdmin, SettingsTab active) {
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
                selected: active == tab,
                selectedColor: SaltColors.chip,
                onSelected: (_) => _select(context, tab),
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
    return Semantics(
      button: !comingSoon,
      selected: active,
      child: InkWell(
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
      ),
    );
  }
}

/// Shared section heading inside settings panes.
class PaneTitle extends StatelessWidget {
  const PaneTitle(this.title, {super.key, this.description, this.trailing});

  final String title;
  final String? description;

  /// Optional compact icon action shown just after the title (e.g. a download
  /// button), so a pane with an action still gets the shared heading style
  /// instead of rolling its own. It renders at its natural size but occupies
  /// only the title's height in layout (see [build]).
  final Widget? trailing;

  /// The title text's line height. The trailing action is boxed to this so a
  /// themed icon button (taller than the title) can't make the heading — and
  /// the pane below it — sit lower than the tabs without an action. Measured:
  /// without the box an FButton.icon adds ~8px.
  static const double _titleHeight = 20;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: SaltColors.maroon,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trailing == null)
          heading
        else
          Row(
            children: [
              heading,
              const SizedBox(width: 6),
              // Render the action full size but keep its LAYOUT height equal to
              // the title's, so it never inflates the heading row.
              SizedBox(
                width: 30,
                height: _titleHeight,
                child: OverflowBox(
                  maxHeight: double.infinity,
                  child: trailing,
                ),
              ),
            ],
          ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              description!,
              style: const TextStyle(fontSize: 13.5, color: SaltColors.muted),
            ),
          ),
        const SizedBox(height: 18),
      ],
    );
  }
}
