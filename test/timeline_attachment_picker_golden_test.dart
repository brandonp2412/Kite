import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/timeline/timeline_attachment_widgets.dart';

void main() {
  Future<void> pumpPicker(
    WidgetTester tester, {
    required ThemeMode themeMode,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KiteTheme.light,
        darkTheme: KiteTheme.dark,
        themeMode: themeMode,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RepaintBoundary(
              key: const Key('attachment-picker-golden-surface'),
              child: ComposerAttachmentPickerSheet(onLocationSelected: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('attachment action grid approved baseline - light', (
    tester,
  ) async {
    await pumpPicker(tester, themeMode: ThemeMode.light);
    await expectLater(
      find.byKey(const Key('attachment-picker-golden-surface')),
      matchesGoldenFile('goldens/attachment_picker_light.png'),
    );
  });

  testWidgets('attachment action grid approved baseline - dark', (
    tester,
  ) async {
    await pumpPicker(tester, themeMode: ThemeMode.dark);
    await expectLater(
      find.byKey(const Key('attachment-picker-golden-surface')),
      matchesGoldenFile('goldens/attachment_picker_dark.png'),
    );
  });
}
