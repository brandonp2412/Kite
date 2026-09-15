import 'package:kite/features/navigation/app_destination.dart';

final class CallDeepLinkTarget {
  const CallDeepLinkTarget({
    required this.accountId,
    required this.roomId,
    required this.callId,
  });

  final String accountId;
  final String roomId;
  final String callId;

  AppDestination toDestination() =>
      AppDestination.call(accountId: accountId, roomId: roomId, callId: callId);
}

final class CallDeepLinkCoordinator {
  factory CallDeepLinkCoordinator({
    required AccountActivationPort accounts,
    required AppNavigationPort navigation,
  }) => CallDeepLinkCoordinator._(accounts, navigation);

  const CallDeepLinkCoordinator._(this._accounts, this._navigation);

  final AccountActivationPort _accounts;
  final AppNavigationPort _navigation;

  Future<void> open(CallDeepLinkTarget target) async {
    _validate(target);
    if (_accounts.activeAccountId != target.accountId) {
      await _accounts.activateAccount(target.accountId);
    }
    await _navigation.open(target.toDestination());
  }

  void _validate(CallDeepLinkTarget target) {
    if (target.accountId.trim().isEmpty ||
        target.accountId != target.accountId.trim()) {
      throw ArgumentError.value(
        target.accountId,
        'target.accountId',
        'Call deep links require an exact non-empty account id.',
      );
    }
    if (!target.roomId.startsWith('!') ||
        target.roomId.length <= 2 ||
        !target.roomId.contains(':') ||
        target.roomId.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(
        target.roomId,
        'target.roomId',
        'Call deep links require an exact Matrix room id.',
      );
    }
    if (target.callId.isEmpty ||
        target.callId != target.callId.trim() ||
        target.callId.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(
        target.callId,
        'target.callId',
        'Call deep links require an exact MatrixRTC call id.',
      );
    }
  }
}
