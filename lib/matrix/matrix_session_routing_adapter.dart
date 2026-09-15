import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/matrix/matrix_navigation.dart';
import 'package:kite/matrix/matrix_session_runtime.dart';

final class MatrixSessionRoutingAdapter
    implements AccountActivationPort, AppNavigationPort {
  const MatrixSessionRoutingAdapter(this.session);

  final MatrixSessionRuntime session;

  @override
  String? get activeAccountId => session.accounts.activeAccountId.value;

  @override
  Future<void> activateAccount(String accountId) async {
    await session.activateAccount(accountId);
  }

  @override
  Future<void> open(AppDestination destination) async {
    if (activeAccountId != destination.accountId) {
      throw StateError(
        'Cannot route Matrix destination before its owning account is active',
      );
    }

    final target = switch (destination.kind) {
      AppDestinationKind.room => MatrixNavigationTarget.room(
        destination.roomId,
      ),
      AppDestinationKind.event => MatrixNavigationTarget.event(
        destination.roomId,
        destination.eventId!,
      ),
      AppDestinationKind.thread => MatrixNavigationTarget.thread(
        destination.roomId,
        destination.eventId!,
        destination.threadRootEventId!,
      ),
      AppDestinationKind.call => MatrixNavigationTarget.call(
        destination.roomId,
        callId: destination.callId,
      ),
    };
    await session.navigate(target);
  }
}
