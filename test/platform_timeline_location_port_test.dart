import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kite/features/timeline/platform_timeline_location_port.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/matrix/matrix_models.dart';

void main() {
  test(
    'platform location port prepares and sends a static device location',
    () async {
      TimelineLocation? sent;
      final port = PlatformTimelineLocationPort(
        checkPermission: () async => LocationPermission.whileInUse,
        requestPermission: () async => LocationPermission.whileInUse,
        getCurrentPosition: ({locationSettings}) async => Position(
          longitude: 174.7682,
          latitude: -36.8468,
          timestamp: DateTime.utc(2026, 9, 26),
          accuracy: 4,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
        openSettings: () async => true,
        sendStaticLocation:
            ({
              required roomId,
              required transactionId,
              required location,
            }) async {
              expect(roomId, '!room:example.org');
              expect(transactionId, 'txn-1');
              sent = location;
            },
      );

      expect(port.supportsLiveLocation, isFalse);
      final prepared = await port.prepare(TimelineLocationKind.staticLocation);
      expect(prepared.permission, TimelineLocationPermission.granted);
      expect(prepared.location?.latitude, -36.8468);
      expect(prepared.location?.longitude, 174.7682);

      final outcome = await port.sendLocation(
        roomId: '!room:example.org',
        transactionId: 'txn-1',
        location: prepared.location!,
      );
      expect(outcome, TimelineSendOutcome.sent);
      expect(sent, same(prepared.location));
    },
  );

  test('matrix location events project back into location cards', () {
    final message = TimelineMessage.fromMatrixEvent(
      MatrixTimelineEvent(
        eventId: r'$event',
        roomId: '!room:example.org',
        senderId: '@alice:example.org',
        type: 'm.room.message',
        originServerTimestamp: DateTime.utc(2026, 9, 26, 1),
        streamPosition: 1,
        content: const <String, Object?>{
          'msgtype': 'm.location',
          'body': 'Britomart',
          'geo_uri': 'geo:-36.8468,174.7682;u=5',
        },
      ),
      currentUserId: '@me:example.org',
    );

    expect(message, isNotNull);
    expect(message!.body, isEmpty);
    expect(message.location?.kind, TimelineLocationKind.staticLocation);
    expect(message.location?.label, 'Britomart');
    expect(message.location?.latitude, -36.8468);
    expect(message.location?.longitude, 174.7682);
  });

  test(
    'permanent denial remains distinguishable for settings recovery',
    () async {
      final port = PlatformTimelineLocationPort(
        checkPermission: () async => LocationPermission.deniedForever,
        requestPermission: () async => LocationPermission.deniedForever,
        getCurrentPosition: ({locationSettings}) async =>
            throw StateError('unused'),
        openSettings: () async => true,
        sendStaticLocation: ({
          required roomId,
          required transactionId,
          required location,
        }) async {},
      );

      final prepared = await port.prepare(TimelineLocationKind.staticLocation);
      expect(prepared.permission, TimelineLocationPermission.permanentlyDenied);
      expect(prepared.location, isNull);
    },
  );
}
