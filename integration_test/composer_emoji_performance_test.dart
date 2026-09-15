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

  testWidgets('composer emoji picker stays within the frame contract', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('composer-field')), 'Hello ');
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('composer-emoji')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('composer-emoji-0')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('composer-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, 'Hello 😀');
    expect(editable.focusNode.hasFocus, isTrue);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['composer_emoji'] = <String, dynamic>{
      'journey': 'composer_emoji_picker',
      'fixture': 'deterministic_composer_emoji_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
