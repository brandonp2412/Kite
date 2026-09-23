import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/production_kite_runtime.dart';
import 'package:kite/features/auth/session_gate.dart';
import 'package:kite/features/auth/session_lifecycle.dart';
import 'package:kite/features/profile/matrix_avatar_image_provider.dart';
import 'package:kite/main.dart' as app;

// Run against an already signed-in production installation. No fixture media,
// explicit prefetch, pumpAndSettle, or cache clearing is allowed in this test.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const roomName = String.fromEnvironment(
    'KITE_MEDIA_ROOM',
    defaultValue: 'Google Messages',
  );
  const startupBudgetMs = 1500;
  const roomImageBudgetMs = 500;

  testWidgets('production session startup paints avatars and recent image', (
    tester,
  ) async {
    final clock = Stopwatch()..start();
    final report = <String, dynamic>{
      'mode': 'saved_session_startup',
      'startup_budget_ms': startupBudgetMs,
      'room_image_budget_ms': roomImageBudgetMs,
      'poll_interval_ms': 20,
      'avatar_painted_ms': <int>[],
    };
    binding.reportData = {'production_media_startup': report};
    final violations = <String>[];

    void observeSession() {
      final gates = find.byType(SessionGate).evaluate();
      if (gates.isNotEmpty &&
          (gates.first.widget as SessionGate).lifecycleController.state.value
              is SessionAuthenticated) {
        report.putIfAbsent(
          'session_authenticated_ms',
          () => clock.elapsedMilliseconds,
        );
      }
    }

    Future<bool> waitFor(bool Function() ready, {int seconds = 45}) async {
      final deadline = clock.elapsed + Duration(seconds: seconds);
      do {
        await tester.pump(const Duration(milliseconds: 20));
        observeSession();
        if (ready()) return true;
      } while (clock.elapsed < deadline);
      return false;
    }

    // An Image widget exists while loading or showing an error placeholder.
    // Only count its decoded RawImage once it occupies visible screen space.
    bool painted(Finder scope, {String? uri}) {
      final images = find.descendant(
        of: scope,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is MatrixAvatarImageProvider &&
              (uri == null ||
                  (widget.image as MatrixAvatarImageProvider).avatarUri
                          .toString() ==
                      uri),
        ),
      );
      final rawImages = find.descendant(
        of: images,
        matching: find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        ),
      );
      final viewport =
          Offset.zero &
          (tester.view.physicalSize / tester.view.devicePixelRatio);
      return rawImages.evaluate().any((element) {
        final rect = tester.getRect(
          find.byElementPredicate((candidate) => identical(candidate, element)),
        );
        return !rect.isEmpty && rect.overlaps(viewport);
      });
    }

    try {
      await app.main();
      final homeReady = await waitFor(
        () =>
            find.byKey(const Key('home-search')).evaluate().isNotEmpty ||
            find.byKey(const Key('authentication-panel')).evaluate().isNotEmpty,
      );
      expect(
        homeReady,
        isTrue,
        reason: 'Production startup never reached home or authentication.',
      );
      expect(
        find.byKey(const Key('authentication-panel')),
        findsNothing,
        reason: 'Fixture unavailable: sign into this installation first. A missing session is not a performance pass.',
      );
      report['home_visible_ms'] = clock.elapsedMilliseconds;
      final runtime = tester
          .widget<ProductionKiteRuntime>(find.byType(ProductionKiteRuntime))
          .matrixRuntime;

      final avatarRooms = <String>[];
      final avatarTimes = <String, int>{};
      final avatarsReady = await waitFor(() {
        final snapshot = runtime.activeCache?.snapshot();
        if (snapshot == null) return false;
        if (avatarRooms.isEmpty) {
          final visible = snapshot.rooms
              .where((room) {
                final row = find.byKey(Key('room-${room.roomId}'));
                return room.avatarUrl?.startsWith('mxc://') == true &&
                    row.hitTestable().evaluate().isNotEmpty;
              })
              .take(3)
              .toList();
          if (visible.length < 3) return false;
          avatarRooms.addAll(visible.map((room) => room.roomId));
          report['avatar_targets_selected_ms'] = clock.elapsedMilliseconds;
        }
        for (final room in avatarRooms) {
          if (!avatarTimes.containsKey(room) &&
              painted(find.byKey(Key('room-$room')))) {
            avatarTimes[room] = clock.elapsedMilliseconds;
            report['avatar_painted_ms'] = avatarTimes.values.toList();
          }
        }
        return avatarTimes.length == 3;
      });
      report['avatars_complete'] = avatarsReady;
      if (!avatarsReady) {
        violations.add(
          'Three visible chat avatars did not paint within 45 seconds.',
        );
      }
      if (avatarsReady) {
        report['all_avatars_painted_ms'] = clock.elapsedMilliseconds;
        if (clock.elapsedMilliseconds > startupBudgetMs) {
          violations.add(
            'Startup → three painted chat avatars: ${clock.elapsedMilliseconds}ms (budget ${startupBudgetMs}ms).',
          );
        }
      }

      String? roomId;
      String? imageUri;
      String? imageEventId;
      final imageMetadataReady = await waitFor(() {
        final snapshot = runtime.activeCache?.snapshot();
        if (snapshot == null) return false;
        for (final room in snapshot.rooms) {
          if (room.displayName.toLowerCase() != roomName.toLowerCase()) {
            continue;
          }
          roomId = room.roomId;
          for (final event
              in (snapshot.timelines[room.roomId] ?? []).reversed) {
            if (event.redacted || event.content['msgtype'] != 'm.image') {
              continue;
            }
            final file = event.content['file'];
            final uri = file is Map ? file['url'] : event.content['url'];
            if (uri is! String || !uri.startsWith('mxc://')) continue;
            imageUri = uri;
            imageEventId = event.eventId;
            return true;
          }
        }
        return false;
      });
      expect(
        imageMetadataReady,
        isTrue,
        reason: 'Fixture unavailable: target room must contain a recent Matrix image.',
      );
      report['recent_image_metadata_ms'] = clock.elapsedMilliseconds;
      final row = find.byKey(Key('room-$roomId'));
      expect(
        row.hitTestable(),
        findsOneWidget,
        reason: 'Target chat must be visible among recent chats; scrolling would change the startup measurement.',
      );
      report['room_open_ms'] = clock.elapsedMilliseconds;
      await tester.tap(row);
      final imageReady = await waitFor(
        () => painted(
          find.byKey(Key('message-row-$imageEventId')),
          uri: imageUri,
        ),
      );
      report['recent_image_complete'] = imageReady;
      if (imageReady) {
        report['recent_image_painted_ms'] = clock.elapsedMilliseconds;
        final elapsed =
            clock.elapsedMilliseconds - (report['room_open_ms'] as int);
        report['room_open_to_image_ms'] = elapsed;
        if (elapsed > roomImageBudgetMs) {
          violations.add(
            'Chat open → painted recent image: ${elapsed}ms (budget ${roomImageBudgetMs}ms).',
          );
        }
      } else {
        violations.add(
          'The latest image did not paint within 45 seconds of opening the chat.',
        );
      }
      report['violations'] = violations;
      expect(
        violations,
        isEmpty,
        reason: 'Real production media startup exceeded its latency budget.',
      );
    } finally {
      report['observation_duration_ms'] = clock.elapsedMilliseconds;
      debugPrint('KITE_MEDIA_STARTUP ${jsonEncode(report)}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
