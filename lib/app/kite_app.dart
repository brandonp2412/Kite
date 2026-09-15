import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  const KiteApp({
    super.key,
    this.themeMode = ThemeMode.system,
    this.darkThemeVariant = KiteDarkThemeVariant.standard,
    this.locale,
    this.home,
  });

  final ThemeMode themeMode;
  final KiteDarkThemeVariant darkThemeVariant;
  final Locale? locale;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: KiteTheme.light,
      darkTheme: darkThemeVariant == KiteDarkThemeVariant.trueBlack
          ? KiteTheme.black
          : KiteTheme.dark,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeAnimationCurve: KiteMotion.standardCurve,
      themeAnimationDuration: KiteMotion.resolve(context, KiteMotion.standard),
      builder: (context, child) {
        final theme = Theme.of(context);
        final motionAwareTheme = KiteMotion.prefersReducedMotion(context)
            ? theme.copyWith(
                pageTransitionsTheme: KiteMotion.reducedPageTransitions,
              )
            : theme;
        return Theme(
          data: motionAwareTheme,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: KiteSystemBars.forTheme(theme),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: home ?? const HomeScreen(),
    );
  }
}
