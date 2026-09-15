import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/timeline/timeline_link_preview.dart';

void main() {
  final preview = TimelineLinkPreviewData(
    uri: Uri.parse('https://element.io/help/get-started'),
    title: 'element.io',
    description: 'help › get-started',
  );

  for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    final name = themeMode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('timeline link preview $name reference render', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 180);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: KiteTheme.light,
          darkTheme: KiteTheme.dark,
          themeMode: themeMode,
          home: Scaffold(
            body: Center(
              child: TimelineLinkPreviewCard(preview: preview, onOpen: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('timeline-link-preview')),
        matchesGoldenFile('goldens/timeline_link_preview_$name.png'),
      );
    });
  }
}
