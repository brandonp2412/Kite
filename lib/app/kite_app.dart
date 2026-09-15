import 'package:flutter/material.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/l10n/generated/app_localizations.dart';
import 'package:signals/signals.dart';

final selectedRoomId = signal('kite');

void selectRoom(String roomId) {
  if (selectedRoomId.value == roomId) return;
  selectedRoomId.value = roomId;
}

class KiteApp extends StatelessWidget {
  const KiteApp({super.key, this.themeMode = ThemeMode.system, this.locale});

  final ThemeMode themeMode;
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: KiteTheme.light,
      darkTheme: KiteTheme.dark,
      themeMode: themeMode,
      themeAnimationCurve: KiteMotion.standardCurve,
      themeAnimationDuration: KiteMotion.resolve(context, KiteMotion.standard),
      home: const HomeScreen(),
    );
  }
}
