import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/media_viewer_fixture.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/media_viewer.dart';

void main() {
  Future<MediaViewerFixture> pumpViewer(
    WidgetTester tester, {
    MediaViewerActionHandler? onSave,
    MediaViewerActionHandler? onShare,
  }) async {
    final fixture = MediaViewerFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.light,
        home: MediaViewer(
          items: fixture.items,
          onSave: onSave,
          onShare: onShare,
        ),
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
    expect(
      tester.getSemantics(find.byKey(const Key('media-page-fixture-1'))).label,
      contains('2 of 3'),
    );
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

  testWidgets('full resolution fades over the retained thumbnail', (
    tester,
  ) async {
    await pumpViewer(tester);

    final fullResolution = find.byKey(const Key('media-full-fixture-0'));
    final opacityFinder = find.descendant(
      of: fullResolution,
      matching: find.byType(Opacity),
    );

    expect(find.byKey(const Key('media-thumbnail-fixture-0')), findsOneWidget);
    expect(tester.widget<Opacity>(opacityFinder).opacity, 0);

    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.widget<Opacity>(opacityFinder).opacity,
      inExclusiveRange(0, 1),
    );
    expect(find.byKey(const Key('media-thumbnail-fixture-0')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(opacityFinder).opacity, 1);
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

  testWidgets('save and share actions target the currently visible media', (
    tester,
  ) async {
    final savedIds = <String>[];
    final sharedIds = <String>[];
    await pumpViewer(
      tester,
      onSave: (item) async => savedIds.add(item.id),
      onShare: (item) async => sharedIds.add(item.id),
    );

    expect(find.byKey(const Key('media-save')), findsOneWidget);
    expect(find.byKey(const Key('media-share')), findsOneWidget);

    await tester.tap(find.byKey(const Key('media-save')));
    await tester.pump();
    expect(savedIds, <String>['fixture-0']);

    await tester.drag(
      find.byKey(const Key('media-page-view')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('media-share')));
    await tester.pump();

    expect(sharedIds, <String>['fixture-1']);
  });

  testWidgets('media action progress is stable and de-duplicates taps', (
    tester,
  ) async {
    final completer = Completer<void>();
    var saveCalls = 0;
    await pumpViewer(
      tester,
      onSave: (item) {
        saveCalls++;
        return completer.future;
      },
      onShare: (item) async {},
    );

    final save = find.byKey(const Key('media-save'));
    final saveRect = tester.getRect(save);
    await tester.tap(save);
    await tester.pump();

    expect(saveCalls, 1);
    expect(find.byKey(const Key('media-action-progress')), findsOneWidget);
    expect(tester.getRect(save), saveRect);

    await tester.tap(save);
    await tester.pump();
    expect(saveCalls, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('media-action-progress')), findsNothing);
    expect(find.text('Media saved'), findsOneWidget);
    expect(tester.getRect(save), saveRect);
  });

  testWidgets('media action failure is surfaced without leaving viewer', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      onSave: (item) async => throw StateError('fixture failure'),
    );

    await tester.tap(find.byKey(const Key('media-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('media-viewer')), findsOneWidget);
    expect(find.text('Could not save media'), findsOneWidget);
    expect(find.byKey(const Key('media-action-progress')), findsNothing);
  });

  testWidgets('cancelled media action leaves viewer open without a snackbar', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      onSave: (_) async => throw const MediaViewerActionCancelled(),
    );

    await tester.tap(find.byKey(const Key('media-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('media-viewer')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('media-action-progress')), findsNothing);
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

  testWidgets('arrow keys browse media without wrapping past either edge', (
    tester,
  ) async {
    final fixture = await pumpViewer(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('media-full-fixture-1')), findsOneWidget);
    expect(fixture.loadCounts, <int>[1, 1, 0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('media-full-fixture-0')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('media-full-fixture-0')), findsOneWidget);
  });

  testWidgets('media controls expose labelled 48dp accessibility targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpViewer(tester, onSave: (_) async {}, onShare: (_) async {});

    for (final entry in <Key, String>{
      const Key('media-close'): 'Close media viewer',
      const Key('media-save'): 'Save media',
      const Key('media-share'): 'Share media',
    }.entries) {
      final targetFinder = find.byKey(entry.key);
      final size = tester.getSize(targetFinder);
      final node = tester.getSemantics(targetFinder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(node.label, contains(entry.value));
    }

    semantics.dispose();
  });
}
