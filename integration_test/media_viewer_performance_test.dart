import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/benchmark/media_viewer_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/media_viewer.dart';

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

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('open-media-viewer')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('media-viewer')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['media_viewer_open'] = <String, dynamic>{
      'journey': 'open_media_viewer',
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
    await tester.pumpWidget(
      MaterialApp(
        theme: KiteTheme.dark,
        home: MediaViewer(items: fixture.items),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.drag(
          find.byKey(const Key('media-page-view')),
          const Offset(-700, 0),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.text('2 of 3'), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['media_viewer_swipe'] = <String, dynamic>{
      'journey': 'browse_adjacent_media',
      'fixture': 'deterministic_media_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });
}
