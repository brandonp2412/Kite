import 'package:kite/matrix/matrix_account_runtime_registry.dart';
import 'package:kite/matrix/matrix_navigation.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';
import 'package:kite/matrix/matrix_restoration.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals.dart';

final class MatrixSessionRuntime {
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

    await accounts.activateCached(snapshot.accountId);
    navigationTarget.value = snapshot.navigationTarget;
    return true;
  }

  Future<void> resumeSync() => accounts.resumeActive();

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
    final cache = await accounts.activate(accountId);
    await _recordNavigation(target);
    return cache;
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
