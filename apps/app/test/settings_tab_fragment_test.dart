import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/features/settings/settings_page.dart';

/// The `/settings#<tab>` fragment → tab mapping (anchor-link deep-linking).
void main() {
  test('a known admin fragment selects that tab for an admin', () {
    expect(
      settingsTabForFragment('tags', isAdmin: true),
      SettingsTab.tags,
    );
    expect(
      settingsTabForFragment('logs', isAdmin: true),
      SettingsTab.logs,
    );
  });

  test('a member-visible fragment works for a member', () {
    expect(
      settingsTabForFragment('tokens', isAdmin: false),
      SettingsTab.tokens,
    );
  });

  test('an admin-only fragment falls back to Account for a member', () {
    // A member cannot open the server tabs; the URL must not smuggle them in.
    for (final admin in ['users', 'tags', 'library', 'nutrition', 'logs']) {
      expect(
        settingsTabForFragment(admin, isAdmin: false),
        SettingsTab.account,
        reason: '#$admin is admin-only',
      );
    }
  });

  test('an empty or unknown fragment falls back to Account', () {
    expect(settingsTabForFragment('', isAdmin: true), SettingsTab.account);
    expect(
      settingsTabForFragment('not-a-tab', isAdmin: true),
      SettingsTab.account,
    );
  });
}
