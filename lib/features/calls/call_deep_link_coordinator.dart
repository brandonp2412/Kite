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
    if (_accounts.activeAccountId != target.accountId) {
      await _accounts.activateAccount(target.accountId);
    }
    await _navigation.open(target.toDestination());
  }
}
