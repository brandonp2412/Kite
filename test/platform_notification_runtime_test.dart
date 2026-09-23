import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/notifications/platform_notification_runtime.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nz.presley.kite/notifications');
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'requestPermission') return true;
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'background Matrix message reaches the Android notification channel',
    () async {
      final runtime = ProductionNotificationRuntime();

      await runtime.handleSyncBatch(
        accountId: '@me:kite.test',
        batch: MatrixSyncBatch(
          cursor: 'next',
          rooms: <MatrixRoomDelta>[
            MatrixRoomDelta(
              roomId: '!room:kite.test',
              timelineEvents: <MatrixTimelineEvent>[
                MatrixTimelineEvent(
                  eventId: r'$event',
                  roomId: '!room:kite.test',
                  senderId: '@alice:kite.test',
                  senderDisplayName: 'Alice',
                  type: 'm.room.message',
                  originServerTimestamp: DateTime.utc(2026, 9, 23, 0, 0),
                  streamPosition: 12,
                  content: const <String, Object?>{
                    'msgtype': 'm.text',
                    'body': 'notification e2e proof',
                  },
                ),
              ],
            ),
          ],
        ),
        isInitialSync: false,
        activity: MatrixAppActivity.background,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'show');
      final arguments = calls.single.arguments! as Map<Object?, Object?>;
      expect(arguments['title'], 'Alice');
      expect(arguments['body'], 'notification e2e proof');
      expect(arguments['roomId'], '!room:kite.test');
      expect(arguments['eventId'], r'$event');
    },
  );

  test('foreground and initial sync do not produce notifications', () async {
    final runtime = ProductionNotificationRuntime();
    final batch = MatrixSyncBatch(
      cursor: 'next',
      rooms: <MatrixRoomDelta>[
        MatrixRoomDelta(
          roomId: '!room:kite.test',
          timelineEvents: <MatrixTimelineEvent>[
            MatrixTimelineEvent(
              eventId: r'$event',
              roomId: '!room:kite.test',
              senderId: '@alice:kite.test',
              type: 'm.room.message',
              originServerTimestamp: DateTime.utc(2026, 9, 23, 0, 0),
              streamPosition: 12,
              content: const <String, Object?>{'body': 'hello'},
            ),
          ],
        ),
      ],
    );

    await runtime.handleSyncBatch(
      accountId: '@me:kite.test',
      batch: batch,
      isInitialSync: false,
      activity: MatrixAppActivity.foreground,
    );
    await runtime.handleSyncBatch(
      accountId: '@me:kite.test',
      batch: batch,
      isInitialSync: true,
      activity: MatrixAppActivity.background,
    );

    expect(calls, isEmpty);
  });
}
