// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/l10n/l10n.dart';
import 'package:kite/pages/chat_list/chat_list_item.dart';
import 'package:kite/widgets/matrix.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../utils/test_client.dart';

class _WorkRoom extends Room {
  _WorkRoom({required super.client, required super.id, required this.index});

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

class _WorkMatrixState extends MatrixState {
  _WorkMatrixState(this.client);

  @override
  final Client client;
}

// Counts every dirty Element build inside an actual ChatListItem subtree.
// This debug-only hook does not report CPU instructions or release-mode costs.
class _BuildWork {
  int totalRowElementBuilds = 0;
  int chatListItemBuilds = 0;
  final distinctElements = Set<Element>.identity();
  final byWidget = <String, int>{};

  void record(Element element, bool builtOnce) {
    if (element.widget is! ChatListItem &&
        element.findAncestorWidgetOfExactType<ChatListItem>() == null) {
      return;
    }
    totalRowElementBuilds++;
    distinctElements.add(element);
    if (element.widget is ChatListItem) chatListItemBuilds++;
    final name = element.widget.runtimeType.toString();
    byWidget.update(name, (count) => count + 1, ifAbsent: () => 1);
  }

  Map<String, Object> toJson() {
    final mostBuilt = byWidget.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {
      'rowElementBuilds': totalRowElementBuilds,
      'chatListItemBuilds': chatListItemBuilds,
      'distinctElementsBuilt': distinctElements.length,
      'repeatElementBuilds': totalRowElementBuilds - distinctElements.length,
      'topWidgetBuilds': {
        for (final entry in mostBuilt.take(12)) entry.key: entry.value,
      },
    };
  }
}

void main() {
  testWidgets('chat list scroll framework work budget', (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
      final room = _WorkRoom(
        client: client,
        id: '!perf$index:test',
        index: index,
      );
      final senderId = '@sender${index % 11}:test';
      room.setState(
        User(senderId, room: room, displayName: 'Sender ${index % 11}'),
      );
      room.lastEvent = Event(
        content: {
          'msgtype': MessageTypes.Text,
          'body': previewBodies[index % previewBodies.length],
        },
        type: EventTypes.Message,
        eventId: r'$perf-event-' + index.toString(),
        senderId: senderId,
        originServerTs: DateTime.utc(2026, 10, 8, index % 24, (index * 7) % 60),
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
        value: _WorkMatrixState(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 760,
              child: ListView.builder(
                controller: controller,
                scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
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

    final work = _BuildWork();
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = work.record;
    try {
      // The original 180-row benchmark path, replayed without a stopwatch.
      // Count Flutter builds instead of relying on machine-dependent timing.
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
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }

    debugPrint('CHAT_LIST_WORK_COUNTS=${jsonEncode(work.toJson())}');
    // Baseline e7de05440: 71,912 subtree builds, 1,256 row builds,
    // 35,956 distinct elements across four identical debug-mode runs.
    // Small headroom catches churn without involving wall-clock speed.
    expect(work.totalRowElementBuilds, lessThanOrEqualTo(75000));
    expect(work.chatListItemBuilds, lessThanOrEqualTo(1300));
    expect(work.distinctElements.length, lessThanOrEqualTo(38000));
    expect(tester.takeException(), isNull);
  });
}
