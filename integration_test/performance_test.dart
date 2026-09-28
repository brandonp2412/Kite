// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/pages/chat_list/chat_list_item.dart';

import 'flows/auth_flows.dart';
import 'utils/kite_tester.dart';

const _runId = String.fromEnvironment(
  'KITE_PERF_RUN_ID',
  defaultValue: 'manual',
);
const _dependencyLockSha = String.fromEnvironment(
  'KITE_PERF_DEPENDENCY_LOCK_SHA',
  defaultValue: 'manual',
);

Future<void> _stressScroll(
  WidgetTester tester,
  Finder scrollable, {
  int cycles = 8,
}) async {
  for (var cycle = 0; cycle < cycles; cycle++) {
    final direction = cycle.isEven ? -1.0 : 1.0;
    await tester.timedDrag(
      scrollable,
      Offset(0, 1050 * direction),
      const Duration(milliseconds: 420),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _waitForVisibleRooms(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (find.byType(ChatListItem).evaluate().length < 3) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out waiting for seeded rooms to render');
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kite Nox Waydroid performance fixture', (tester) async {
    final kite = await tester.startKiteTest();
    await kite.ensureLoggedIn(initializeCryptoIdentity: false);

    await kite.waitFor(
      const Key('chat_list_scroll'),
      timeout: const Duration(seconds: 90),
    );
    await _waitForVisibleRooms(tester);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['metadata'] = <String, dynamic>{
      'runId': _runId,
      'fixture': 'real_chat_shape_v1',
      'surface': 'nox_waydroid',
      'dependencyLockSha256': _dependencyLockSha,
    };

    await binding.watchPerformance(
      () => _stressScroll(tester, find.byKey(const Key('chat_list_scroll'))),
      reportKey: 'chat_list_cold_scroll',
    );
    await binding.watchPerformance(
      () => _stressScroll(tester, find.byKey(const Key('chat_list_scroll'))),
      reportKey: 'chat_list_warm_scroll',
    );

    await tester.dragUntilVisible(
      find.byType(ChatListItem).first,
      find.byKey(const Key('chat_list_scroll')),
      const Offset(0, 500),
    );
    await tester.tap(find.byType(ChatListItem).first);
    await tester.pumpAndSettle();
    await kite.waitFor(
      const Key('chat_timeline_scroll'),
      timeout: const Duration(seconds: 60),
    );

    await binding.watchPerformance(
      () =>
          _stressScroll(tester, find.byKey(const Key('chat_timeline_scroll'))),
      reportKey: 'chat_timeline_cold_scroll',
    );
    await binding.watchPerformance(
      () =>
          _stressScroll(tester, find.byKey(const Key('chat_timeline_scroll'))),
      reportKey: 'chat_timeline_warm_scroll',
    );

    await kite.goBack();
    await kite.waitFor(
      const Key('chat_list_scroll'),
      timeout: const Duration(seconds: 30),
    );
    await kite.tapOn(const Key('accounts_and_settings_buttons'));
    await kite.tapOn('Settings');
    await kite.waitFor(
      const Key('SettingsListViewContent'),
      timeout: const Duration(seconds: 30),
    );

    await binding.watchPerformance(
      () => _stressScroll(
        tester,
        find.byKey(const Key('SettingsListViewContent')),
        cycles: 6,
      ),
      reportKey: 'settings_scroll_control',
    );
  });
}
