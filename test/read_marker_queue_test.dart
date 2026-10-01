// SPDX-FileCopyrightText: 2026 Brandon Dick
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/utils/read_marker_queue.dart';

void main() {
  test('coalesces overlapping read markers to the latest request', () async {
    final firstRequest = Completer<void>();
    final sent = <String?>[];
    final errors = <Object>[];

    final queue = ReadMarkerQueue(
      send: (eventId) async {
        sent.add(eventId);
        if (sent.length == 1) await firstRequest.future;
      },
      onError: (error, _) => errors.add(error),
    );

    queue.request(r'$event1');
    await Future<void>.delayed(Duration.zero);

    queue.request(r'$event2');
    queue.request(null);

    expect(sent, [r'$event1']);

    firstRequest.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(sent, [r'$event1', null]);
    expect(errors, isEmpty);
  });

  test('continues with pending request after a failed write', () async {
    final firstRequest = Completer<void>();
    final sent = <String?>[];
    final errors = <Object>[];

    final queue = ReadMarkerQueue(
      send: (eventId) async {
        sent.add(eventId);
        if (sent.length == 1) await firstRequest.future;
      },
      onError: (error, _) => errors.add(error),
    );

    queue.request(r'$event1');
    await Future<void>.delayed(Duration.zero);
    queue.request(r'$event2');

    firstRequest.completeError(StateError('network failure'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(sent, [r'$event1', r'$event2']);
    expect(errors, hasLength(1));
  });
}
