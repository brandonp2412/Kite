import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/matrix/matrix_models.dart';

import 'performance_benchmark_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets(
    'incremental Matrix timeline update has zero late Flutter frames',
    (tester) async {
      addTearDown(() {
        timelineController.reset(sendPort: DeterministicTimelineSendPort());
        selectRoom('kite');
      });
      selectRoom('alice');
      timelineController.reset(
        sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
      );
      final initial = <MatrixTimelineEvent>[
        for (var index = 0; index < 100; index++) _event(index),
      ];
      timelineController.applyMatrixEvents(
        'alice',
        initial,
        currentUserId: '@me:example.org',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: KiteTheme.light,
          home: const MediaQuery(
            data: MediaQueryData(size: Size(1200, 800)),
            child: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final anchor = find.byKey(const Key(r'message-bubble-$matrix-60'));
      await tester.scrollUntilVisible(
        anchor,
        240,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('message-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final before = tester.getRect(anchor);

      final result = await measureFrames(
        binding: binding,
        action: () async {
          timelineController.applyMatrixEvents('alice', <MatrixTimelineEvent>[
            ...initial,
            _event(100),
          ], currentUserId: '@me:example.org');
          await tester.pump();
        },
        enforceTotalSpan: enforceTotalSpan,
      );

      expect(tester.getRect(anchor), before);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['matrix_timeline_sync_update'] = <String, dynamic>{
        'journey': 'matrix_timeline_sync_update',
        'fixture': 'deterministic_100_matrix_messages_v1',
        ...result,
        'result': 'PASS',
      };
    },
  );
}

MatrixTimelineEvent _event(int index) {
  return MatrixTimelineEvent(
    eventId: '\$matrix-$index',
    roomId: 'alice',
    senderId: '@alice:example.org',
    type: 'm.room.message',
    originServerTimestamp: DateTime.utc(
      2026,
      9,
      16,
      10,
    ).add(Duration(seconds: index)),
    streamPosition: index,
    content: <String, Object?>{
      'msgtype': 'm.text',
      'body': 'Synced timeline message $index with stable geometry.',
    },
  );
}
