import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/app/production_kite_runtime.dart';
import 'package:kite/main.dart' as app;
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_pagination_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const e2eMessage = String.fromEnvironment('KITE_E2E_MESSAGE');
  const expectedInboundMessage = String.fromEnvironment(
    'KITE_E2E_EXPECTED_INBOUND',
  );

  testWidgets('real Linux session paginates the selected Matrix timeline', (
    tester,
  ) async {
    await app.main();

    for (var i = 0; i < 80; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byKey(const Key('home-search')).evaluate().isNotEmpty ||
          find.byKey(const Key('soft-logout-notice')).evaluate().isNotEmpty) {
        break;
      }
    }

    if (find.byKey(const Key('soft-logout-notice')).evaluate().isNotEmpty) {
      expect(find.byKey(const Key('soft-logout-notice')), findsOneWidget);
      expect(find.byKey(const Key('auth-subtitle')), findsOneWidget);
      expect(find.textContaining('Matrix session expired'), findsOneWidget);
      return;
    }

    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(find.text('Matrix runtime is unavailable.'), findsNothing);
    expect(find.text('Could not start Matrix sync.'), findsNothing);

    final uptimeRoom = find.ancestor(
      of: find.text('Uptime'),
      matching: find.byType(ListTile),
    );
    expect(uptimeRoom, findsWidgets);
    await tester.tap(uptimeRoom.first);
    final messageList = find.byKey(const Key('message-list'));
    for (var i = 0; i < 40; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
      if (messageList.evaluate().isNotEmpty) break;
    }
    expect(messageList, findsOneWidget);

    if (expectedInboundMessage.isNotEmpty) {
      for (var i = 0; i < 80; i += 1) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.text(expectedInboundMessage).evaluate().isNotEmpty) break;
      }
      expect(find.text(expectedInboundMessage), findsWidgets);
    }

    final runtime = tester
        .widget<ProductionKiteRuntime>(find.byType(ProductionKiteRuntime))
        .matrixRuntime;
    final accountId = runtime.activeAccountId.value;
    expect(accountId, isNotNull);
    final roomId = selectedRoomId.value;
    final paginationState = runtime.paginationState(
      accountId: accountId!,
      roomId: roomId,
    );
    expect(paginationState, isNotNull);
    for (var i = 0; i < 40; i += 1) {
      final syncState = runtime.activeSyncState?.value;
      if (syncState?.phase == MatrixSyncPhase.running) break;
      await tester.pump(const Duration(milliseconds: 250));
    }
    final syncState = runtime.activeSyncState?.value;
    expect(
      syncState?.phase,
      MatrixSyncPhase.running,
      reason: 'Real Matrix sync must be running: ${syncState?.error}',
    );

    if (e2eMessage.isNotEmpty) {
      final composer = find.byKey(const Key('composer-field'));
      expect(composer, findsOneWidget);
      await tester.enterText(composer, e2eMessage);
      await tester.tap(find.byKey(const Key('composer-send')));
      expect(find.text(e2eMessage), findsWidgets);

      Finder outgoingRows() => find.ancestor(
        of: find.text(e2eMessage),
        matching: find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('message-row-');
        }),
      );
      Finder outgoingIcon(IconData icon) =>
          find.descendant(of: outgoingRows(), matching: find.byIcon(icon));

      for (var i = 0; i < 80; i += 1) {
        await tester.pump(const Duration(milliseconds: 250));
        if (outgoingIcon(Icons.done_rounded).evaluate().isNotEmpty ||
            outgoingIcon(Icons.error_rounded).evaluate().isNotEmpty) {
          break;
        }
      }
      expect(
        outgoingIcon(Icons.error_rounded),
        findsNothing,
        reason: 'Real Matrix send must not settle as failed.',
      );
      expect(
        outgoingIcon(Icons.done_rounded),
        findsWidgets,
        reason: 'Real Matrix send must settle as sent.',
      );
      expect(find.text(e2eMessage), findsWidgets);
    }

    var listView = tester.widget<ListView>(messageList);
    final initialCount = listView.childrenDelegate.estimatedChildCount ?? 0;
    expect(initialCount, greaterThan(0));

    var position = listView.controller!.position;
    final initialExtentAfter = position.extentAfter;
    expect(initialExtentAfter, greaterThan(0));

    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.drag(messageList, const Offset(0, 500));
      await tester.pump(const Duration(milliseconds: 100));
      listView = tester.widget<ListView>(messageList);
      position = listView.controller!.position;
      if (position.extentAfter <= 520) break;
    }
    expect(position.extentAfter, lessThanOrEqualTo(520));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      paginationState!.value.phase != MatrixPaginationPhase.idle ||
          paginationState.value.reachedStart ||
          (tester
                      .widget<ListView>(messageList)
                      .childrenDelegate
                      .estimatedChildCount ??
                  0) >
              initialCount,
      isTrue,
      reason: 'Reaching the oldest edge must dispatch real pagination.',
    );

    for (var i = 0; i < 80; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
      listView = tester.widget<ListView>(messageList);
      final currentCount = listView.childrenDelegate.estimatedChildCount ?? 0;
      final state = paginationState.value;
      if (currentCount > initialCount ||
          state.reachedStart ||
          state.phase == MatrixPaginationPhase.failed) {
        break;
      }
    }

    final state = paginationState.value;
    expect(
      state.phase,
      isNot(MatrixPaginationPhase.loading),
      reason: 'Real pagination must complete instead of remaining in-flight.',
    );
    expect(
      state.phase,
      isNot(MatrixPaginationPhase.failed),
      reason: 'Real pagination must not fail at the oldest visible edge.',
    );

    listView = tester.widget<ListView>(messageList);
    final finalCount = listView.childrenDelegate.estimatedChildCount ?? 0;
    expect(
      finalCount > initialCount || state.reachedStart,
      isTrue,
      reason: 'Pagination must add older events or prove history is exhausted.',
    );
    expect(
      find.textContaining('Matrix Rust SDK back-pagination failed'),
      findsNothing,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byKey(const Key('home-search')).evaluate().isNotEmpty) break;
    }
    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(find.text('Could not start Matrix sync.'), findsNothing);
  });
}
