import 'package:kite/matrix/matrix_account_runtime_registry.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_navigation.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';
import 'package:kite/matrix/matrix_restoration.dart';
import 'package:kite/matrix/matrix_runtime_coordinator.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals.dart';

final class MatrixSessionRuntime
    implements MatrixActivityRuntime, MatrixConnectivityRuntime {
  MatrixSessionRuntime({
    required this.accounts,
    required this.restoration,
    required this.isAccountAvailable,
  });

  final MatrixAccountRuntimeRegistry accounts;
  final MatrixRestorationCoordinator restoration;
  final MatrixRestorationAccountAvailable isAccountAvailable;

  final Signal<MatrixNavigationTarget> navigationTarget =
      signal<MatrixNavigationTarget>(const MatrixNavigationTarget.home());

  Future<bool> restoreCachedState() async {
    final snapshot = await restoration.restore();
    if (snapshot == null) return false;

    if (!await isAccountAvailable(snapshot.accountId)) {
      await restoration.clear();
      return false;
    }

    await accounts.activateCached(
      snapshot.accountId,
      onActivated: () {
        navigationTarget.value = snapshot.navigationTarget;
      },
    );
    return true;
  }

  Future<void> resumeSync() => accounts.resumeActive();

  ReadonlySignal<MatrixSyncState>? get syncState => accounts.activeSyncState;

  @override
  Future<void> updateActivity(MatrixAppActivity activity) {
    return accounts.updateActivity(activity);
  }

  @override
  Future<void> updateNetworkState(MatrixNetworkState state) {
    return accounts.updateNetworkState(state);
  }

  ReadonlySignal<MatrixPaginationState>? paginationState(String roomId) {
    return accounts.activePaginationState(roomId);
  }

  Future<void> onTimelineViewportChanged({
    required String roomId,
    required int oldestVisibleIndex,
    required bool hasMoreHistory,
  }) {
    return accounts.onTimelineViewportChanged(
      roomId: roomId,
      oldestVisibleIndex: oldestVisibleIndex,
      hasMoreHistory: hasMoreHistory,
    );
  }

  Future<MatrixPresentationCache> activateAccount(
    String accountId, {
    MatrixNavigationTarget target = const MatrixNavigationTarget.home(),
  }) async {
    final previousAccountId = accounts.activeAccountId.value;
    final previousTarget = navigationTarget.value;
    try {
      return await accounts.activate(
        accountId,
        onActivated: () => _recordNavigation(target),
      );
    } catch (error, stackTrace) {
      navigationTarget.value = previousTarget;
      try {
        if (previousAccountId == null) {
          await restoration.clear();
        } else {
          await restoration.record(
            accountId: previousAccountId,
            navigationTarget: previousTarget,
          );
        }
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> navigate(MatrixNavigationTarget target) async {
    if (accounts.activeAccountId.value == null) {
      throw StateError(
        'Cannot navigate Matrix state without an active account',
      );
    }
    await _recordNavigation(target);
  }

  Future<void> deactivate({bool clearRestoration = true}) async {
    await accounts.deactivate();
    navigationTarget.value = const MatrixNavigationTarget.home();
    if (clearRestoration) {
      await restoration.clear();
    }
  }

  Future<void> _recordNavigation(MatrixNavigationTarget target) async {
    final accountId = accounts.activeAccountId.value;
    if (accountId == null) {
      throw StateError('Cannot persist navigation without an active account');
    }
    navigationTarget.value = target;
    await restoration.record(accountId: accountId, navigationTarget: target);
  }
}
