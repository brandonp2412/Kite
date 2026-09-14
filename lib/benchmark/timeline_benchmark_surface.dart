import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';

class TimelineBenchmarkController {
  TimelineBenchmarkController()
    : messages = ValueNotifier<List<BenchmarkMessage>>(
        List<BenchmarkMessage>.of(BenchmarkFixture.richTimelineMessages),
      );

  final ValueNotifier<List<BenchmarkMessage>> messages;
  final ValueNotifier<int> reactionCount = ValueNotifier<int>(2);
  final ValueNotifier<int> readReceiptCount = ValueNotifier<int>(3);
  final ValueNotifier<bool> typing = ValueNotifier<bool>(false);

  void prependOlderPage() {
    messages.value = <BenchmarkMessage>[
      ...BenchmarkFixture.olderTimelinePage,
      ...messages.value,
    ];
  }

  void insertIncomingMessage() {
    messages.value = <BenchmarkMessage>[
      ...messages.value,
      BenchmarkFixture.incomingTimelineMessage,
    ];
  }

  void updateEphemeralState() {
    reactionCount.value += 1;
    readReceiptCount.value += 1;
    typing.value = !typing.value;
  }

  void dispose() {
    messages.dispose();
    reactionCount.dispose();
    readReceiptCount.dispose();
    typing.dispose();
  }
}

class TimelineBenchmarkSurface extends StatelessWidget {
  const TimelineBenchmarkSurface({required this.controller, super.key});

  final TimelineBenchmarkController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Timeline performance fixture',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: controller.readReceiptCount,
                      builder: (context, receipts, child) => Text(
                        '$receipts read',
                        key: const Key('benchmark-read-receipts'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<List<BenchmarkMessage>>(
                valueListenable: controller.messages,
                builder: (context, messages, child) {
                  return ListView.builder(
                    key: const Key('benchmark-message-list'),
                    reverse: true,
                    itemCount: messages.length,
                    itemExtent: 72,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      return _BenchmarkMessageRow(
                        key: Key('benchmark-message-${message.id}'),
                        message: message,
                        reactionCount: index == 0
                            ? controller.reactionCount
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: controller.typing,
                    builder: (context, typing, child) => Text(
                      typing ? 'Alice is typing' : 'No active typing',
                      key: const Key('benchmark-typing'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenchmarkMessageRow extends StatelessWidget {
  const _BenchmarkMessageRow({
    required this.message,
    required this.reactionCount,
    super.key,
  });

  final BenchmarkMessage message;
  final ValueListenable<int>? reactionCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Align(
        alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: message.mine
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 72,
                    child: Text(
                      _labelFor(message.kind),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          message.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Text(
                          message.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (reactionCount != null)
                    ValueListenableBuilder<int>(
                      valueListenable: reactionCount!,
                      builder: (context, value, child) => Text(
                        'Reactions $value',
                        key: const Key('benchmark-reactions'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _labelFor(BenchmarkMessageKind kind) => switch (kind) {
    BenchmarkMessageKind.text => 'TEXT',
    BenchmarkMessageKind.formatted => 'RICH',
    BenchmarkMessageKind.image => 'IMAGE',
    BenchmarkMessageKind.file => 'FILE',
    BenchmarkMessageKind.audio => 'AUDIO',
    BenchmarkMessageKind.poll => 'POLL',
    BenchmarkMessageKind.location => 'LOCATION',
  };
}
