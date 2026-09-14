import 'package:flutter/material.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:signals/signals.dart';

final selectedRoomId = signal('kite');

void selectRoom(String roomId) {
  if (selectedRoomId.value == roomId) return;
  selectedRoomId.value = roomId;
}

class KiteApp extends StatelessWidget {
  const KiteApp({super.key, this.themeMode = ThemeMode.system});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kite',
      debugShowCheckedModeBanner: false,
      theme: KiteTheme.light,
      darkTheme: KiteTheme.dark,
      themeMode: themeMode,
      themeAnimationCurve: KiteMotion.standardCurve,
      themeAnimationDuration: KiteMotion.resolve(context, KiteMotion.standard),
      home: const HomeScreen(),
    );
  }
}
