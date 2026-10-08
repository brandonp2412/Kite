// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/l10n/l10n.dart';
import 'package:kite/pages/chat_list/chat_list_item.dart';
import 'package:kite/widgets/matrix.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../test/utils/test_client.dart';

class _PerfRoom extends Room {
  _PerfRoom({
    required super.client,
    required super.id,
    required this.index,
  });

  final int index;

  @override
  Future<List<User>> loadHeroUsers() async => const [];

  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) {
    const categories = [
      'Family',
      'Developers',
      'Project planning',
      'Announcements',
      'Weekend plans',
      'Neighbourhood',
      'Book club',
    ];
    return 'Room $index · ${categories[index % categories.length]}';
  }
}

class _PerfMatrixState extends MatrixState {
  _PerfMatrixState(this.client);

  @override
  final Client client;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('representative chat list scroll performance', (tester) async {
    final client = (await tester.runAsync(prepareTestClient))!;
    const previewBodies = [
      'Can you send the updated notes before lunch?',
      'The build is green now — I pushed the fix.',
      'Photos from the weekend are ready.',
      'Meeting moved to 3:30, same room.',
      'That sounds good to me, thanks!',
      'Longer message preview to exercise ellipsis and text layout.',
    ];

    final rooms = List.generate(180, (index) {
      final room = _PerfRoom(
        client: client,
        id: '!perf$index:test',
        index: index,
      );
      final senderId = '@sender${index % 11}:test';
      room.setState(
        User(
          senderId,
          room: room,
          displayName: 'Sender ${index % 11}',
        ),
      );
      room.lastEvent = Event(
        content: {
          'msgtype': MessageTypes.Text,
          'body': previewBodies[index % previewBodies.length],
        },
        type: EventTypes.Message,
        eventId: r'$perf-event-' + index.toString(),
        senderId: senderId,
        originServerTs: DateTime.utc(
          2026,
          10,
          8,
          index % 24,
          (index * 7) % 60,
        ),
        room: room,
      );
      room.notificationCount = index % 4 == 0 ? (index % 9) + 1 : 0;
      room.highlightCount = index % 17 == 0 ? 1 : 0;
      return room;
    });

    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _PerfMatrixState(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 760,
              child: ListView.builder(
                controller: controller,
                cacheExtent: 1200,
                itemCount: rooms.length,
                itemBuilder: (context, index) => SizedBox(
                  key: ValueKey('perf-row-$index'),
                  height: 84,
                  child: ChatListItem(rooms[index], onTap: () {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(800, 20));
    await tester.pump();
    addTearDown(mouse.removePointer);

    expect(controller.position.maxScrollExtent, greaterThan(7200));

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['metadata'] = <String, dynamic>{
      'surface': 'linux',
      'scenario':
          '180 ChatListItem rows; varied names/message previews/timestamps/'
          'unread/highlight counts/fallback avatars; 520x760; cacheExtent 1200; '
          'mouse outside list; 4 fixed 0<->7200 scroll cycles',
    };

    await binding.watchPerformance(() async {
      for (var cycle = 0; cycle < 4; cycle++) {
        for (var step = 1; step <= 40; step++) {
          controller.jumpTo(7200 * step / 40);
          await tester.pump(const Duration(milliseconds: 16));
        }
        for (var step = 1; step <= 40; step++) {
          controller.jumpTo(7200 * (1 - step / 40));
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
    }, reportKey: 'chat_list_scroll');
  });
}
