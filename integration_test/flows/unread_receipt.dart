// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kite/pages/chat_list/chat_list.dart';
import 'package:kite/pages/chat_list/chat_list_item.dart';
import 'package:kite/pages/chat_list/unread_bubble.dart';
import 'package:kite/widgets/kite_app.dart';
import 'package:kite/widgets/matrix.dart';
import 'package:matrix/matrix.dart';

import '../data/environment_constants.dart';
import '../utils/kite_tester.dart';

Future<void> unreadClearsOnOpen(WidgetTester widgetTester) =>
    widgetTester.startKiteTest().then((tester) => tester._unreadClearsOnOpen());

extension on KiteTester {
  Future<void> _unreadClearsOnOpen() async {
    await waitFor(Matrix, timeout: const Duration(seconds: 60));
    final matrixState = tester.state<MatrixState>(find.byType(Matrix).first);
    final client = matrixState.client;
    if (!client.isLogged()) {
      await client.checkHomeserver(
        Uri.parse('http://$homeserver'),
        fetchAuthMetadata: false,
      );
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: user1Name),
        // Keep compatibility with the Synapse fixture.
        // ignore: deprecated_member_use
        user: user1Name,
        password: user1Pw,
        initialDeviceDisplayName: 'Kite unread receipt E2E',
      );
      KiteApp.router.go('/rooms');
      await tester.pumpAndSettle();
    }
    await waitFor(ChatList, timeout: const Duration(seconds: 60));
    final bob = await _loginSecondUser();
    final roomName =
        'Unread receipt E2E ${DateTime.now().millisecondsSinceEpoch}';
    final roomId = await client.createRoom(
      name: roomName,
      invite: [bob.userId],
      preset: CreateRoomPreset.privateChat,
    );

    await _joinRoom(bob.accessToken, roomId);

    const unreadMessage = 'Unread receipt E2E message';
    await _sendMessage(bob.accessToken, roomId, unreadMessage);

    await waitFor(roomName);
    await _waitForRoomState(
      roomName,
      (room) => room.notificationCount > 0,
      description: 'room to become unread',
    );

    await tapOn(roomName, pumpAndSettle: false);
    await waitFor(unreadMessage);
    await tester.pumpAndSettle();
    KiteApp.router.go('/rooms');
    await tester.pumpAndSettle();
    await waitFor(ChatList);

    await _waitForRoomState(
      roomName,
      (room) =>
          room.notificationCount == 0 &&
          !room.markedUnread &&
          !room.hasNewMessages,
      description: 'room to become fully read',
    );

    final room = _roomForName(roomName);
    expect(room.notificationCount, 0);
    expect(room.markedUnread, isFalse);
    expect(room.hasNewMessages, isFalse);

    await room.leave();
  }

  Future<void> _waitForRoomState(
    String roomName,
    bool Function(Room room) predicate, {
    required String description,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final room = _roomForNameOrNull(roomName);
      if (room != null && predicate(room)) return;
      await tester.pump(const Duration(milliseconds: 250));
    }
    throw TestFailure('Timed out waiting for $description');
  }

  Room _roomForName(String roomName) {
    final room = _roomForNameOrNull(roomName);
    if (room == null) {
      throw TestFailure('Could not find chat list room "$roomName"');
    }
    return room;
  }

  Room? _roomForNameOrNull(String roomName) {
    final title = find.text(roomName);
    if (title.evaluate().isEmpty) return null;

    final item = find.ancestor(
      of: title.first,
      matching: find.byType(ChatListItem),
    );
    if (item.evaluate().isEmpty) return null;

    final bubble = find.descendant(
      of: item.first,
      matching: find.byType(UnreadBubble),
    );
    if (bubble.evaluate().isEmpty) return null;

    return tester.widget<UnreadBubble>(bubble.first).room;
  }
}

Future<({String accessToken, String userId})> _loginSecondUser() async {
  final response = await http.post(
    Uri.parse('http://$homeserver/_matrix/client/v3/login'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'type': 'm.login.password',
      'identifier': {'type': 'm.id.user', 'user': user2Name},
      'password': user2Pw,
    }),
  );
  expect(response.statusCode, 200, reason: response.body);
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  return (
    accessToken: json['access_token'] as String,
    userId: json['user_id'] as String,
  );
}

Future<void> _joinRoom(String accessToken, String roomId) async {
  final response = await http.post(
    Uri.parse(
      'http://$homeserver/_matrix/client/v3/join/${Uri.encodeComponent(roomId)}',
    ),
    headers: {
      'authorization': 'Bearer $accessToken',
      'content-type': 'application/json',
    },
    body: '{}',
  );
  expect(response.statusCode, 200, reason: response.body);
}

Future<void> _sendMessage(
  String accessToken,
  String roomId,
  String body,
) async {
  final transactionId = DateTime.now().microsecondsSinceEpoch;
  final response = await http.put(
    Uri.parse(
      'http://$homeserver/_matrix/client/v3/rooms/'
      '${Uri.encodeComponent(roomId)}/send/m.room.message/$transactionId',
    ),
    headers: {
      'authorization': 'Bearer $accessToken',
      'content-type': 'application/json',
    },
    body: jsonEncode({'msgtype': 'm.text', 'body': body}),
  );
  expect(response.statusCode, 200, reason: response.body);
}
