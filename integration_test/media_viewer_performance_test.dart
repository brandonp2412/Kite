import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/media_viewer_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );

  testWidgets('opening full-screen media stays within the frame contract', (
    tester,
  ) async {
    final fixture = MediaViewerFixture();
    final first = fixture.items.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                key: const Key('open-media-viewer'),
                onTap: () =>
                    Navigator.of(context)
                        .push(MediaViewerRoute(items: fixture.items)),
                child: SizedBox(
                  width: 180,
                  height: 135,
                  child: Hero(
                    tag: first.heroTag,
                    child: first.thumbnailBuilder(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const iterations = 3;
    final result = await measureFrames(
      binding: binding,
      action: () async {
        for (var index = 0; index < iterations; index++) {
          await tester.tap(find.byKey(const Key('open-media-viewer')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('media-viewer')), findsOneWidget);
          await tester.tap(find.byKey(const Key('media-close')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('media-viewer')), findsNothing);
        }
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['media_viewer_open'] = <String, dynamic>{
      'journey': 'open_media_viewer',
      'fixture': 'deterministic_media_v1',
      'iterations': iterations,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('flick-to-dismiss stays within the frame contract', (
    tester,
  ) async {
    final fixture = MediaViewerFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-media-for-dismiss'),
                onPressed: () =>
                    Navigator.of(context)
                        .push(MediaViewerRoute(items: fixture.items)),
                child: const Text('Open media'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-media-for-dismiss')));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.drag(
          find.byKey(const Key('media-gesture-surface')),
          const Offset(0, 220),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('media-viewer')), findsNothing);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['media_viewer_dismiss'] = <String, dynamic>{
      'journey': 'dismiss_media_viewer',
      'fixture': 'deterministic_media_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('adjacent-media swipe stays within the frame contract', (
    tester,
  ) async {
    final fixture = MediaViewerFixture();
    var currentIndex = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: MediaViewer(
          items: fixture.items,
          onIndexChanged: (index) => currentIndex = index,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.fling(
          find.byKey(const Key('media-page-view')),
          const Offset(-520, 0),
          1200,
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(currentIndex, 1);
    expect(fixture.loadCounts[1], 1);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['media_viewer_swipe'] = <String, dynamic>{
      'journey': 'browse_adjacent_media',
      'fixture': 'deterministic_media_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('timeline media open stays within the frame contract', (
    tester,
  ) async {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(
        latency: Duration.zero,
      ),
    );
    addTearDown(() {
      timelineController.reset(
        sendPort: DeterministicTimelineSendPort(),
        attachmentSendPort: const DeterministicTimelineAttachmentSendPort(),
      );
      selectRoom('kite');
    });
    selectRoom('alice');
    final message = timelineController.sendAttachment(
      'alice',
      const TimelineAttachment(
        id: 'benchmark-viewer-image',
        kind: TimelineAttachmentKind.image,
        name: 'benchmark.jpg',
        sizeLabel: '2.8 MB · Photo',
      ),
      caption: 'Timeline media benchmark',
    );

    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(
          find.byKey(Key('message-attachment-open-${message.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('media-viewer')), findsOneWidget);
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_media_viewer_open'] = <String, dynamic>{
      'journey': 'timeline_media_viewer_open',
      'fixture': 'deterministic_timeline_media_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });
}
