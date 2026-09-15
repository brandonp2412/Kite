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

  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      pollPort: DeterministicTimelinePollPort(),
    );
    selectRoom('kite');
  });

  testWidgets('poll create, vote, and end stay within the frame contract', (
    tester,
  ) async {
    timelineController.reset(
      pollPort: DeterministicTimelinePollPort(latency: Duration.zero),
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('composer-attach')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('attachment-option-poll')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('poll-question-field')),
          'Ship tonight?',
        );
        await tester.enterText(
          find.byKey(const Key('poll-option-field-0')),
          'Yes',
        );
        await tester.enterText(
          find.byKey(const Key('poll-option-field-1')),
          'Tomorrow',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('poll-create-confirm')));
        await tester.pumpAndSettle();

        final message = timelineController.messagesFor('alice').value.last;
        await tester.tap(find.byKey(Key('poll-option-${message.id}-option-0')));
        await tester.pumpAndSettle();
        await tester.longPress(find.byKey(Key('message-poll-${message.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('message-action-end-poll')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    final message = timelineController.messagesFor('alice').value.last;
    expect(message.poll?.selectedOptionId, 'option-0');
    expect(message.poll?.isEnded, isTrue);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['poll_workflow'] = <String, dynamic>{
      'journey': 'poll_create_vote_end',
      'fixture': 'deterministic_poll_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });
}
