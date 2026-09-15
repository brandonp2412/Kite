import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );

  setUp(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(
        latency: Duration.zero,
      ),
    );
    selectRoom('alice');
    timelineController.sendAttachment(
      'alice',
      const TimelineAttachment(
        id: 'gallery-photo',
        kind: TimelineAttachmentKind.image,
        name: 'gallery.jpg',
        sizeLabel: '2.4 MB · Photo',
      ),
      caption: 'Gallery benchmark',
    );
    timelineController.sendAttachment(
      'alice',
      const TimelineAttachment(
        id: 'gallery-file',
        kind: TimelineAttachmentKind.file,
        name: 'gallery.pdf',
        sizeLabel: '840 KB · PDF',
      ),
    );
    timelineController.sendText('alice', 'Reference https://matrix.org/docs/');
  });

  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(),
    );
    selectRoom('kite');
  });

  testWidgets('shared content open and tab switch stay within frame contract', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('room-content-gallery-action')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('room-content-gallery')), findsOneWidget);
        await tester.tap(find.byKey(const Key('room-content-tab-files')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('room-content-file-kite-local-1')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('room-content-tab-links')));
        await tester.pumpAndSettle();
        expect(find.text('matrix.org'), findsOneWidget);
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['media_gallery'] = <String, dynamic>{
      'journey': 'open_media_gallery_and_switch_tabs',
      'fixture': 'deterministic_shared_content_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });
}
