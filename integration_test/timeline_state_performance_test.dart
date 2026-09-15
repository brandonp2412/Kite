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
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  testWidgets('typing state update stays within the frame contract', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        timelineController.updateTypingUsers('alice', const <String>['Maya']);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(find.text('Maya is typing…'), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_typing_update'] = <String, dynamic>{
      'journey': 'timeline_typing_update',
      'fixture': 'deterministic_timeline_ephemeral_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('read receipt update stays within the frame contract', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    final target = timelineController.messagesFor('alice').value.last;

    final result = await measureFrames(
      binding: binding,
      action: () async {
        timelineController.updateReadReceipts(
          'alice',
          target.id,
          const <String>['Alice', 'Maya'],
        );
        await tester.pump();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(find.byKey(const Key('read-receipts-alice-99')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_read_receipt_update'] = <String, dynamic>{
      'journey': 'timeline_read_receipt_update',
      'fixture': 'deterministic_timeline_receipts_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('jump to unread stays within the frame contract', (tester) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    final target = timelineController.messagesFor('alice').value.last;
    timelineController.setUnreadMarker('alice', target.id);
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('message-list'));
    await tester.drag(list, const Offset(0, 1100));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.pixels, greaterThan(0));

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('jump-to-unread')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(find.byKey(Key('message-row-${target.id}')), findsOneWidget);
    expect(find.byKey(const Key('timeline-unread-marker')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_jump_to_unread'] = <String, dynamic>{
      'journey': 'timeline_jump_to_unread',
      'fixture': 'deterministic_timeline_unread_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
