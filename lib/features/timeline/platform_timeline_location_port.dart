import 'package:geolocator/geolocator.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

typedef TimelineStaticLocationSender = Future<void> Function({
  required String roomId,
  required String transactionId,
  required TimelineLocation location,
});

final class PlatformTimelineLocationPort implements TimelineLocationPort {
  const PlatformTimelineLocationPort({
    required this.sendStaticLocation,
    this.checkPermission = Geolocator.checkPermission,
    this.requestPermission = Geolocator.requestPermission,
    this.getCurrentPosition = Geolocator.getCurrentPosition,
    this.openSettings = Geolocator.openAppSettings,
  });

  final TimelineStaticLocationSender sendStaticLocation;
  final Future<LocationPermission> Function() checkPermission;
  final Future<LocationPermission> Function() requestPermission;
  final Future<Position> Function({LocationSettings? locationSettings})
  getCurrentPosition;
  final Future<bool> Function() openSettings;

  @override
  bool get supportsLiveLocation => false;

  @override
  Future<TimelineLocationPreparation> prepare(TimelineLocationKind kind) async {
    if (kind == TimelineLocationKind.liveLocation) {
      return const TimelineLocationPreparation(
        permission: TimelineLocationPermission.denied,
      );
    }
    var permission = await checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await requestPermission();
    }
    final mapped = _mapPermission(permission);
    if (mapped != TimelineLocationPermission.granted) {
      return TimelineLocationPreparation(permission: mapped);
    }
    final position = await getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return TimelineLocationPreparation(
      permission: TimelineLocationPermission.granted,
      location: TimelineLocation(
        kind: TimelineLocationKind.staticLocation,
        latitude: position.latitude,
        longitude: position.longitude,
        label: 'Current location',
      ),
    );
  }

  @override
  Future<TimelineSendOutcome> sendLocation({
    required String roomId,
    required String transactionId,
    required TimelineLocation location,
  }) async {
    if (location.kind != TimelineLocationKind.staticLocation) {
      return TimelineSendOutcome.failed;
    }
    try {
      await sendStaticLocation(
        roomId: roomId,
        transactionId: transactionId,
        location: location,
      );
      return TimelineSendOutcome.sent;
    } on Object {
      return TimelineSendOutcome.failed;
    }
  }

  @override
  Future<TimelineSendOutcome> stopLiveLocation({
    required String roomId,
    required String eventId,
  }) async => TimelineSendOutcome.failed;

  @override
  Future<void> openAppSettings() async {
    await openSettings();
  }

  static TimelineLocationPermission _mapPermission(
    LocationPermission permission,
  ) => switch (permission) {
    LocationPermission.always ||
    LocationPermission.whileInUse => TimelineLocationPermission.granted,
    LocationPermission.deniedForever =>
      TimelineLocationPermission.permanentlyDenied,
    LocationPermission.denied ||
    LocationPermission.unableToDetermine => TimelineLocationPermission.denied,
  };
}
