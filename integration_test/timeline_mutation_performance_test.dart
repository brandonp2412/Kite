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

  testWidgets('new-message insertion has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final initialCount = timelineController.messagesFor('alice').value.length;
    const body = 'Profile-mode insertion benchmark';
    final composer = find.byKey(const Key('composer-field'));
    await tester.enterText(composer, body);
    await tester.pump();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('composer-send')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    final messages = timelineController.messagesFor('alice').value;
    expect(messages, hasLength(initialCount + 1));
    final inserted = messages.last;
    expect(inserted.body, body);
    expect(inserted.sendState.value, TimelineSendState.sent);
    expect(find.byKey(Key('message-bubble-${inserted.id}')), findsOneWidget);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_new_message_insertion'] = <String, dynamic>{
      'journey': 'timeline_new_message_insertion',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });
}
