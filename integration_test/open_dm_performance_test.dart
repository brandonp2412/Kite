import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/design/kite_shader_warm_up.dart';
import 'package:kite/features/threads/thread_controller.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

import 'performance_benchmark_harness.dart';

void main() {
  PaintingBinding.shaderWarmUp = const KiteShaderWarmUp();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );

  testWidgets('cold open Alice DM has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('room-alice')));
        await tester.pump();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(selectedRoomId.value, 'alice');
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['open_dm_cold'] = <String, dynamic>{
      'journey': 'open_alice_dm',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('30 warm user-chat opens have zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-bob')));
    await tester.pump();

    const iterations = PerformanceContract.warmChatOpenIterations;
    final result = await measureFrames(
      binding: binding,
      action: () async {
        for (var index = 0; index < iterations; index++) {
          final target = index.isEven ? 'alice' : 'bob';
          await tester.tap(find.byKey(Key('room-$target')));
          await tester.pump();
          expect(selectedRoomId.value, target);
        }
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['open_dm_warm'] = <String, dynamic>{
      'journey': 'open_user_dm',
      'fixture': 'deterministic_v1',
      'iterations': iterations,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('send message has zero late Flutter frames', (tester) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('composer-field')),
        matching: find.byType(EditableText),
      ),
    );
    editable.controller.text = 'Profile benchmark message';
    await tester.pump();
    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('composer-send')),
    );
    expect(sendButton.onPressed, isNotNull);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        sendButton.onPressed!();
        await tester.pump();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    final sentMessage = timelineController.messagesFor('alice').value.last;
    expect(sentMessage.body, 'Profile benchmark message');
    expect(sentMessage.sendState.value, TimelineSendState.sent);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['send_message'] = <String, dynamic>{
      'journey': 'send_text_message',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('formatting toolbar has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('composer-format-toggle')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(
      find.byKey(const Key('composer-formatting-toolbar')),
      findsOneWidget,
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['composer_formatting_toolbar'] = <String, dynamic>{
      'journey': 'open_composer_formatting_toolbar',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('mention autocomplete has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('composer-field'));
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );

    final result = await measureFrames(
      binding: binding,
      action: () async {
        editable.controller.value = const TextEditingValue(
          text: '@a',
          selection: TextSelection.collapsed(offset: 2),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('composer-autocomplete-Alice')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(editable.controller.text, '@Alice ');
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['composer_mention_autocomplete'] = <String, dynamic>{
      'journey': 'composer_mention_autocomplete',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('formatted send has zero late Flutter frames', (tester) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('composer-field')),
        matching: find.byType(EditableText),
      ),
    );
    editable.controller.text = 'Profile `inline` text.\n\n> Stable quote.\n\n```dart\nfinal stable = true;\n```';
    await tester.pump();
    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('composer-send')),
    );
    expect(sendButton.onPressed, isNotNull);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        sendButton.onPressed!();
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('timeline-body-quote')), findsOneWidget);
    expect(find.byKey(const Key('timeline-body-code')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['send_formatted_message'] = <String, dynamic>{
      'journey': 'send_formatted_text_message',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('reply composer transition has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-98')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-reply')), findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('message-action-reply')));
        for (
          var frame = 0;
          frame < 60 &&
              find.byKey(const Key('composer-context')).evaluate().isEmpty;
          frame++
        ) {
          await tester.pump(const Duration(microseconds: 16667));
        }
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('composer-context')), findsOneWidget);
    expect(find.text('Replying to Alice'), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['reply_composer'] = <String, dynamic>{
      'journey': 'open_reply_composer',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('reply in thread action has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    threadController.reset(
      sendPort: const DeterministicThreadSendPort(latency: Duration.zero),
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('message-action-reply-thread')),
      findsOneWidget,
    );

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('message-action-reply-thread')));
        for (
          var frame = 0;
          frame < 60 &&
              find.byKey(const Key('thread-panel')).evaluate().isEmpty;
          frame++
        ) {
          await tester.pump(const Duration(microseconds: 16667));
        }
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('thread-panel')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['reply_in_thread_action'] = <String, dynamic>{
      'journey': 'open_thread_from_message_action',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('quick reaction has zero late Flutter frames', (tester) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-reaction-0')), findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('quick-reaction-0')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    final message = timelineController.messagesFor('alice').value.last;
    expect(message.reactions['👍']?.count, 1);
    expect(find.byKey(const Key('message-reactions-alice-99')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['quick_reaction'] = <String, dynamic>{
      'journey': 'quick_reaction',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('reaction picker open has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('message-action-more-reactions')),
      findsOneWidget,
    );

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(
          find.byKey(const Key('message-action-more-reactions')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('reaction-picker-sheet')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['reaction_picker_open'] = <String, dynamic>{
      'journey': 'open_reaction_picker',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('forward message flow has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-98')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-forward')), findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('message-action-forward')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('forward-room-bob')));
        await tester.tap(find.byKey(const Key('forward-room-kite')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('forward-message-confirm')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(
      timelineController.messagesFor('bob').value.last.body,
      'Deterministic message 99 in Alice',
    );
    expect(
      timelineController.messagesFor('kite').value.last.body,
      'Deterministic message 99 in Alice',
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['forward_message'] = <String, dynamic>{
      'journey': 'forward_message_to_rooms',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('report message flow has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      moderationPort: DeterministicTimelineModerationPort(
        latency: Duration.zero,
      ),
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-98')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-report')), findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('message-action-report')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('report-reason-1')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.text('Report sent'), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['report_message'] = <String, dynamic>{
      'journey': 'report_message_reason',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('copy message action has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-copy')), findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('message-action-copy')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.text('Message copied'), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['copy_message'] = <String, dynamic>{
      'journey': 'copy_message_text',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('share message action has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      sharePort: DeterministicTimelineSharePort(latency: Duration.zero),
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-share')), findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('message-action-share')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.text('Share sheet opened'), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['share_message'] = <String, dynamic>{
      'journey': 'share_message_content',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('delete confirmation transition has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-delete')), findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('message-action-delete')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(find.byKey(const Key('delete-message-dialog')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['delete_confirmation'] = <String, dynamic>{
      'journey': 'open_delete_confirmation',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('delete redaction commit has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-action-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-message-confirm')), findsOneWidget);
    final message = timelineController.messagesFor('alice').value.last;

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('delete-message-confirm')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    expect(message.redacted, isTrue);
    expect(find.byKey(const Key('message-redacted-alice-99')), findsOneWidget);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['delete_message'] = <String, dynamic>{
      'journey': 'confirm_message_redaction',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('edit message commit has zero late Flutter frames', (
    tester,
  ) async {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('message-bubble-alice-99')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-action-edit')));
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('composer-field')),
        matching: find.byType(EditableText),
      ),
    );
    editable.controller.text = 'Profile edited message 100 in Alice';
    await tester.pump();
    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('composer-send')),
    );
    expect(sendButton.onPressed, isNotNull);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        sendButton.onPressed!();
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: virtualizedBenchmark
          ? PerformanceContract.gateVirtualizedTotalSpan
          : PerformanceContract.gatePhysicalTotalSpan,
    );

    final edited = timelineController.messagesFor('alice').value.last;
    expect(edited.id, 'alice-99');
    expect(edited.body, 'Profile edited message 100 in Alice');
    expect(edited.edited, isTrue);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['edit_message'] = <String, dynamic>{
      'journey': 'commit_message_edit',
      'fixture': 'deterministic_v1',
      'iterations': 1,
      ...result,
      'result': 'PASS',
    };
  });
}
