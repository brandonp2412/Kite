import 'package:flutter/material.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:signals/signals.dart';

final selectedRoomId = signal('kite');

void selectRoom(String roomId) {
  if (selectedRoomId.value == roomId) return;
  selectedRoomId.value = roomId;
}

class KiteApp extends StatelessWidget {
  const KiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kite',
      debugShowCheckedModeBanner: false,
      theme: KiteTheme.light,
      darkTheme: KiteTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
