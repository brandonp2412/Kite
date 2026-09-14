import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/media_viewer_fixture.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/media_viewer.dart';

void main() {
  Future<MediaViewerFixture> pumpViewer(WidgetTester tester) async {
    final fixture = MediaViewerFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: MediaViewer(items: fixture.items),
      ),
    );
    await tester.pump();
    await tester.pump();
    return fixture;
  }

  testWidgets('loads full resolution only for the visible page', (
    tester,
  ) async {
    final fixture = await pumpViewer(tester);

    expect(fixture.loadCounts, <int>[1, 0, 0]);
    expect(find.byKey(const Key('media-thumbnail-fixture-0')), findsOneWidget);
    expect(find.byKey(const Key('media-full-fixture-0')), findsOneWidget);
    expect(find.byKey(const Key('media-full-fixture-1')), findsNothing);

    await tester.drag(
      find.byKey(const Key('media-page-view')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(fixture.loadCounts, <int>[1, 1, 0]);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.byKey(const Key('media-full-fixture-1')), findsOneWidget);
    expect(find.byKey(const Key('media-full-fixture-0')), findsNothing);
  });

  testWidgets('keeps thumbnail mounted while full resolution resolves', (
    tester,
  ) async {
    await pumpViewer(tester);

    expect(find.byKey(const Key('media-thumbnail-fixture-0')), findsOneWidget);
    expect(find.byKey(const Key('media-full-fixture-0')), findsOneWidget);
  });

  testWidgets('formatted caption and image semantics follow current media', (
    tester,
  ) async {
    await pumpViewer(tester);

    final firstCaption = tester.widget<RichText>(
      find.byKey(const Key('media-caption')),
    );
    expect(firstCaption.text.toPlainText(), contains('Auckland harbour'));
    expect(
      tester.getSemantics(find.byKey(const Key('media-page-fixture-0'))).label,
      contains('Harbour at dusk'),
    );

    await tester.drag(
      find.byKey(const Key('media-page-view')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    final secondCaption = tester.widget<RichText>(
      find.byKey(const Key('media-caption')),
    );
    expect(secondCaption.text.toPlainText(), contains('Weekend'));
  });

  testWidgets('single tap hides chrome without removing media', (tester) async {
    await pumpViewer(tester);

    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('media-top-controls')))
          .opacity,
      1,
    );

    await tester.tap(find.byKey(const Key('media-gesture-surface')));
    await tester.pump();

    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('media-top-controls')))
          .opacity,
      0,
    );
    expect(find.byKey(const Key('media-full-fixture-0')), findsOneWidget);
  });
}
