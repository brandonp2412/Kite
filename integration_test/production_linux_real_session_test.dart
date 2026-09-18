import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/app/production_kite_runtime.dart';
import 'package:kite/features/profile/matrix_avatar_image_provider.dart';
import 'package:kite/main.dart' as app;
import 'package:kite/matrix/matrix_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const e2eMessage = String.fromEnvironment('KITE_E2E_MESSAGE');
  const expectedInboundMessage = String.fromEnvironment(
    'KITE_E2E_EXPECTED_INBOUND',
  );

  testWidgets('real Linux session renders Matrix avatars and shared content', (
    tester,
  ) async {
    await app.main();

    void expectSoftLogout() {
      expect(find.byKey(const Key('soft-logout-notice')), findsOneWidget);
      expect(find.byKey(const Key('auth-subtitle')), findsOneWidget);
      expect(find.textContaining('Matrix session expired'), findsOneWidget);
    }

    for (var i = 0; i < 80; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byKey(const Key('home-search')).evaluate().isNotEmpty ||
          find.byKey(const Key('soft-logout-notice')).evaluate().isNotEmpty) {
        break;
      }
    }

    if (find.byKey(const Key('soft-logout-notice')).evaluate().isNotEmpty) {
      expectSoftLogout();
      return;
    }

    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(find.text('Matrix runtime is unavailable.'), findsNothing);
    expect(find.text('Could not start Matrix sync.'), findsNothing);

    final runtime = tester
        .widget<ProductionKiteRuntime>(find.byType(ProductionKiteRuntime))
        .matrixRuntime;
    final accountId = runtime.activeAccountId.value;
    expect(accountId, isNotNull);
    final activeAccountId = accountId!;
    final cache = runtime.activeCache;
    expect(cache, isNotNull);

    for (var i = 0; i < 80; i += 1) {
      final snapshot = cache!.snapshot();
      final hasTimeline = snapshot.rooms.any(
        (room) => (snapshot.timelines[room.roomId]?.length ?? 0) > 0,
      );
      if (hasTimeline) break;
      await tester.pump(const Duration(milliseconds: 250));
    }

    final liveSnapshot = cache!.snapshot();
    final roomsWithTimeline = liveSnapshot.rooms
        .where((room) => (liveSnapshot.timelines[room.roomId]?.length ?? 0) > 0)
        .toList(growable: false);
    expect(
      roomsWithTimeline,
      isNotEmpty,
      reason: 'Real Matrix sync must hydrate at least one room timeline.',
    );
    final targetRoom = roomsWithTimeline.fold(roomsWithTimeline.first, (
      current,
      candidate,
    ) {
      final currentIsTyla = current.displayName.toLowerCase().contains(
        'tyla lockwood',
      );
      final candidateIsTyla = candidate.displayName.toLowerCase().contains(
        'tyla lockwood',
      );
      if (candidateIsTyla && !currentIsTyla) return candidate;
      if (currentIsTyla) return current;
      final currentCount = liveSnapshot.timelines[current.roomId]?.length ?? 0;
      final candidateCount =
          liveSnapshot.timelines[candidate.roomId]?.length ?? 0;
      return candidateCount > currentCount ? candidate : current;
    });

    final roomList = find.byKey(const Key('room-list'));
    expect(roomList, findsOneWidget);
    final targetRoomTile = find.byKey(Key('room-${targetRoom.roomId}'));
    for (var i = 0; i < 100 && targetRoomTile.evaluate().isEmpty; i += 1) {
      await tester.drag(roomList, const Offset(0, -260));
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(
      targetRoomTile,
      findsOneWidget,
      reason:
          'The selected live Matrix room must be reachable in the room list.',
    );
    await tester.tap(targetRoomTile);
    final messageList = find.byKey(const Key('message-list'));
    for (var i = 0; i < 40; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
      if (messageList.evaluate().isNotEmpty ||
          find.byKey(const Key('soft-logout-notice')).evaluate().isNotEmpty) {
        break;
      }
    }
    if (find.byKey(const Key('soft-logout-notice')).evaluate().isNotEmpty) {
      expectSoftLogout();
      return;
    }
    expect(messageList, findsOneWidget);

    if (expectedInboundMessage.isNotEmpty) {
      for (var i = 0; i < 80; i += 1) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.text(expectedInboundMessage).evaluate().isNotEmpty) break;
      }
      expect(find.text(expectedInboundMessage), findsWidgets);
    }

    final roomId = selectedRoomId.value;
    expect(roomId, targetRoom.roomId);
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

    for (var i = 0; i < 80; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
      final hasAvatar = cache.snapshot().rooms.any(
        (room) => Uri.tryParse(room.avatarUrl ?? '')?.scheme == 'mxc',
      );
      if (hasAvatar) break;
    }
    final avatarRooms = cache
        .snapshot()
        .rooms
        .where((room) => Uri.tryParse(room.avatarUrl ?? '')?.scheme == 'mxc')
        .toList(growable: false);
    expect(
      avatarRooms,
      isNotEmpty,
      reason: 'Real Matrix sync must hydrate room avatar MXC metadata.',
    );

    final avatarBatch = avatarRooms.take(12).toList(growable: false);
    expect(
      avatarBatch.length,
      greaterThan(3),
      reason:
          'The real-session avatar regression check needs more than the old '
          'three-avatar happy path.',
    );
    final avatarPrefetchTimer = Stopwatch()..start();
    final prefetched = await runtime.prefetchMedia(
      accountId: activeAccountId,
      contentUris: avatarBatch.map((room) => room.avatarUrl!).toList(),
      width: 192,
      height: 192,
    );
    avatarPrefetchTimer.stop();
    expect(
      prefetched,
      avatarBatch.length,
      reason: 'Native avatar prefetch must warm every requested Matrix avatar.',
    );

    final avatarLoadTimer = Stopwatch()..start();
    final avatarPayloads = await Future.wait(
      avatarBatch.map(
        (room) => runtime.downloadMedia(
          accountId: activeAccountId,
          contentUri: room.avatarUrl!,
          width: 192,
          height: 192,
        ),
      ),
    );
    avatarLoadTimer.stop();
    for (final bytes in avatarPayloads) {
      expect(
        bytes.length,
        greaterThan(128),
        reason: 'Each prefetched Matrix avatar must be available from cache.',
      );
    }
    final avatarBytes = avatarPayloads.first;
    final avatarCodec = await ui.instantiateImageCodec(avatarBytes);
    final avatarFrame = await avatarCodec.getNextFrame();
    expect(avatarFrame.image.width, greaterThan(0));
    expect(avatarFrame.image.height, greaterThan(0));
    avatarFrame.image.dispose();
    avatarCodec.dispose();
    expect(
      avatarLoadTimer.elapsed,
      lessThan(const Duration(seconds: 3)),
      reason:
          'Warm Matrix avatar reads should come from the SDK media cache rather '
          'than serial network downloads.',
    );
    debugPrint(
      'Kite E2E: prefetched $prefetched Matrix avatars in '
      '${avatarPrefetchTimer.elapsedMilliseconds}ms; warm reads took '
      '${avatarLoadTimer.elapsedMilliseconds}ms',
    );

    final targetEvents = cache.snapshot().timelines[roomId] ?? const [];
    final cachedVisualMedia = targetEvents.where((event) {
      if (event.type != 'm.room.message') return false;
      final msgtype = event.content['msgtype'];
      return msgtype == 'm.image' || msgtype == 'm.video';
    }).length;
    if (targetRoom.displayName.toLowerCase().contains('tyla lockwood')) {
      expect(
        cachedVisualMedia,
        greaterThan(0),
        reason:
            'The real Tyla Lockwood timeline contains shared visual media and '
            'must not project as an empty Shared content gallery.',
      );
    }
    if (cachedVisualMedia > 0) {
      await tester.tap(find.byKey(const Key('room-content-gallery-action')));
      for (var i = 0; i < 20; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find
            .byKey(const Key('room-content-media-grid'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(
        find.byKey(const Key('room-content-media-grid')),
        findsOneWidget,
        reason:
            'Cached Matrix image/video events must render in Shared content.',
      );
      expect(find.byKey(const Key('room-content-empty-media')), findsNothing);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 300));
      expect(messageList, findsOneWidget);
    }

    var renderedAvatarCount = 0;
    final expectedRenderedAvatars = avatarRooms.length < 3
        ? avatarRooms.length
        : 3;
    for (var attempt = 0; attempt < 40; attempt += 1) {
      renderedAvatarCount = find
          .descendant(
            of: roomList,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Image && widget.image is MatrixAvatarImageProvider,
            ),
          )
          .evaluate()
          .length;
      if (renderedAvatarCount >= expectedRenderedAvatars) break;
      await tester.drag(roomList, const Offset(0, -320));
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(
      renderedAvatarCount,
      greaterThanOrEqualTo(expectedRenderedAvatars),
      reason: 'Several real room rows with Matrix avatar metadata must render their leading avatar images.',
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

    final scrollView = tester.widget<CustomScrollView>(messageList);
    expect(
      scrollView.semanticChildCount ?? 0,
      greaterThan(0),
      reason: 'The real selected Matrix room must render timeline messages.',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
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
