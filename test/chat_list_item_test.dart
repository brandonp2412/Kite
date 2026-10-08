// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/l10n/l10n.dart';
import 'package:kite/pages/chat_list/chat_list_item.dart';
import 'package:kite/widgets/matrix.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'utils/test_client.dart';

class _TestRoom extends Room {
  _TestRoom({required super.client}) : super(id: '!room:test');

  int heroLoads = 0;
  String displayName = 'Before loading';

  @override
  Future<List<User>> loadHeroUsers() async {
    heroLoads++;
    await Future<void>.delayed(Duration.zero);
    displayName = 'Loaded name';
    return [];
  }

  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => displayName;
}

class _TestMatrixState extends MatrixState {
  _TestMatrixState(this.client);

  @override
  final Client client;
}

void main() {
  testWidgets('row rebuilds reuse hero lookup and display the loaded name', (
    tester,
  ) async {
    final client = (await tester.runAsync(prepareTestClient))!;
    final room = _TestRoom(client: client);

    Future<void> pumpRow({bool active = false}) async {
      await tester.pumpWidget(
        Provider<MatrixState>.value(
          value: _TestMatrixState(client),
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: ChatListItem(room, activeChat: active, onTap: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpRow();
    expect(find.text('Loaded name'), findsOneWidget);
    expect(room.heroLoads, 1);

    for (var i = 0; i < 5; i++) {
      await pumpRow(active: i.isEven);
    }
    expect(room.heroLoads, 1);

    room.summary.mHeroes = ['@new:test'];
    await pumpRow();
    expect(room.heroLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropdown affordance exists only while the row is hovered', (
    tester,
  ) async {
    final client = (await tester.runAsync(prepareTestClient))!;
    final room = _TestRoom(client: client);
    var longPressCalls = 0;

    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _TestMatrixState(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ChatListItem(
              room,
              onTap: () {},
              onLongPress: (_) => longPressCalls++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.arrow_drop_down_circle_outlined),
      findsNothing,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(900, 900));
    await mouse.moveTo(tester.getCenter(find.byType(ChatListItem)));
    await tester.pump();

    final dropdown = find.byIcon(Icons.arrow_drop_down_circle_outlined);
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    expect(longPressCalls, 1);

    await mouse.moveTo(const Offset(900, 900));
    await tester.pump();
    expect(dropdown, findsNothing);
    await mouse.removePointer();
  });
}
