import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/l10n/generated/app_localizations.dart';
import 'package:kite/l10n/kite_locale_format.dart';

void main() {
  test('generated localization handles plurals', () {
    final l10n = lookupAppLocalizations(const Locale('en', 'NZ'));

    expect(l10n.messageCount(0), 'No messages');
    expect(l10n.messageCount(1), '1 message');
    expect(l10n.messageCount(42), '42 messages');
  });

  testWidgets('Kite installs generated localization delegates', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const KiteApp(themeMode: ThemeMode.light, locale: Locale('en', 'NZ')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsOneWidget);
    final context = tester.element(find.text('Chats'));
    expect(Localizations.localeOf(context), const Locale('en', 'NZ'));
    expect(AppLocalizations.of(context).appTitle, 'Kite');
  });

  testWidgets('date, time, and numbers use the active Flutter locale', (
    tester,
  ) async {
    final values = <String>[];

    Future<void> capture(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Builder(
            builder: (context) {
              final date = DateTime(2026, 9, 15, 13, 5);
              values.add(
                <String>[
                  KiteLocaleFormat.date(context, date),
                  KiteLocaleFormat.time(context, date),
                  KiteLocaleFormat.integer(context, 12345),
                ].join('|'),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await capture(const Locale('en'));
    await capture(const Locale('en', 'NZ'));

    expect(values, hasLength(2));
    expect(values[0], isNot(values[1]));
    expect(values[1], contains('12,345'));
  });
}
