import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/l10n/generated/app_localizations.dart';
import 'package:kite/l10n/kite_local_formats.dart';

void main() {
  test('generated localization handles message plurals', () {
    final l10n = lookupAppLocalizations(const Locale('en', 'NZ'));

    expect(l10n.messageCount(0), 'No messages');
    expect(l10n.messageCount(1), '1 message');
    expect(l10n.messageCount(42), '42 messages');
    expect(l10n.unreadThreadRepliesLabel(1), '1 unread thread reply');
    expect(l10n.unreadThreadRepliesLabel(42), '42 unread thread replies');
  });

  testWidgets('Kite exposes translated UI strings and plural rules', (
    tester,
  ) async {
    selectRoom('kite');
    threadController.reset();
    threadController.updateRoomUnreadThreadCount(
      roomId: 'alice',
      unreadThreadCount: 2,
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const KiteApp(themeMode: ThemeMode.light, locale: Locale('de')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nachricht'), findsOneWidget);
    final context = tester.element(find.byType(HomeScreen));
    final l10n = AppLocalizations.of(context);
    expect(l10n.roomCount(0), 'Keine Räume');
    expect(l10n.roomCount(1), '1 Raum');
    expect(l10n.roomCount(12), '12 Räume');
    expect(l10n.unreadThreadRepliesLabel(1), '1 ungelesene Thread-Antwort');
    expect(l10n.unreadThreadRepliesLabel(2), '2 ungelesene Thread-Antworten');

    final semantics = tester.getSemantics(find.byKey(const Key('room-alice')));
    expect(
      semantics.getSemanticsData().label,
      contains('2 ungelesene Thread-Antworten'),
    );
  });

  testWidgets('date time and number formatting follow the active locale', (
    tester,
  ) async {
    final values = <String, List<String>>{};

    Future<void> capture(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final instant = DateTime(2026, 4, 7, 21, 5);
              values[locale.languageCode] = <String>[
                KiteLocalFormats.shortDate(context, instant),
                KiteLocalFormats.shortTime(context, instant),
                KiteLocalFormats.decimal(context, 1234.5),
              ];
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await capture(const Locale('en'));
    await capture(const Locale('de'));

    expect(values['en'], isNot(values['de']));
    expect(values['en']![2], '1,234.5');
    expect(values['de']![2], '1.234,5');
  });

  testWidgets('time formatting respects the platform 24-hour preference', (
    tester,
  ) async {
    late String formatted;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(alwaysUse24HourFormat: true),
          child: Builder(
            builder: (context) {
              formatted = KiteLocalFormats.shortTime(
                context,
                DateTime(2026, 4, 7, 21, 5),
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(formatted, '21:05');
  });
}
