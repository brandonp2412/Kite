enum AppDestinationKind { room, event, thread, call }

final class AppDestination {
  const AppDestination._({
    required this.kind,
    required this.accountId,
    required this.roomId,
    this.eventId,
    this.threadRootEventId,
    this.callId,
  });

  const AppDestination.room({required String accountId, required String roomId})
    : this._(
        kind: AppDestinationKind.room,
        accountId: accountId,
        roomId: roomId,
      );

  const AppDestination.event({
    required String accountId,
    required String roomId,
    required String eventId,
  }) : this._(
         kind: AppDestinationKind.event,
         accountId: accountId,
         roomId: roomId,
         eventId: eventId,
       );

  const AppDestination.thread({
    required String accountId,
    required String roomId,
    required String eventId,
    required String threadRootEventId,
  }) : this._(
         kind: AppDestinationKind.thread,
         accountId: accountId,
         roomId: roomId,
         eventId: eventId,
         threadRootEventId: threadRootEventId,
       );

  const AppDestination.call({
    required String accountId,
    required String roomId,
    required String callId,
  }) : this._(
         kind: AppDestinationKind.call,
         accountId: accountId,
         roomId: roomId,
         callId: callId,
       );

  final AppDestinationKind kind;
  final String accountId;
  final String roomId;
  final String? eventId;
  final String? threadRootEventId;
  final String? callId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppDestination &&
            other.kind == kind &&
            other.accountId == accountId &&
            other.roomId == roomId &&
            other.eventId == eventId &&
            other.threadRootEventId == threadRootEventId &&
            other.callId == callId;
  }

  @override
  int get hashCode =>
      Object.hash(kind, accountId, roomId, eventId, threadRootEventId, callId);
}

abstract interface class AccountActivationPort {
  String? get activeAccountId;

  Future<void> activateAccount(String accountId);
}

abstract interface class AppNavigationPort {
  Future<void> open(AppDestination destination);
}
