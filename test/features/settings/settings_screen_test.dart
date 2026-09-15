import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/settings/settings_screen.dart';

void main() {
  testWidgets(
    'settings exposes account, preference, security and support entry points',
    (tester) async {
      final opened = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            accountLabel: '@alice:example.org',
            onOpenProfile: () => opened.add('profile'),
            onOpenAccounts: () => opened.add('accounts'),
            onOpenGeneral: () => opened.add('general'),
            onOpenNotifications: () => opened.add('notifications'),
            onOpenPrivacySecurity: () => opened.add('privacy'),
            onOpenSupport: () => opened.add('support'),
          ),
        ),
      );

      expect(find.text('@alice:example.org'), findsOneWidget);
      expect(find.text('Your profile'), findsOneWidget);
      expect(find.text('Accounts & sessions'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Privacy & security'), findsOneWidget);

      for (final entry in <(String, String)>[
        ('settings-profile', 'profile'),
        ('settings-accounts', 'accounts'),
        ('settings-general', 'general'),
        ('settings-notifications', 'notifications'),
        ('settings-privacy-security', 'privacy'),
        ('settings-support', 'support'),
      ]) {
        final finder = find.byKey(Key(entry.$1));
        await tester.scrollUntilVisible(
          finder,
          160,
          scrollable: find.descendant(
            of: find.byKey(const Key('settings-list')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(finder);
        await tester.pump();
        expect(opened.last, entry.$2);
      }
    },
  );

  testWidgets('blank account label does not render an empty profile subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          accountLabel: '   ',
          onOpenProfile: () {},
          onOpenAccounts: () {},
          onOpenGeneral: () {},
          onOpenNotifications: () {},
          onOpenPrivacySecurity: () {},
          onOpenSupport: () {},
        ),
      ),
    );

    final profileTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('settings-profile')),
        matching: find.byType(ListTile),
      ),
    );
    expect(profileTile.subtitle, isNull);
  });
}
