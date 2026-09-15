import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/settings/settings_screen.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void main() {
  testWidgets('settings entry geometry stays stable at 120 Hz', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          accountLabel: '@alice:example.org',
          onOpenProfile: () {},
          onOpenAccounts: () {},
          onOpenGeneral: () {},
          onOpenNotifications: () {},
          onOpenPrivacySecurity: () {},
          onOpenSupport: () {},
        ),
      ),
    );
    await tester.pump();

    final list = find.byKey(const Key('settings-list'));
    final profile = find.byKey(const Key('settings-profile'));
    final accounts = find.byKey(const Key('settings-accounts'));
    final initialList = _rectOf(tester, list);
    final initialProfile = _rectOf(tester, profile);
    final initialAccounts = _rectOf(tester, accounts);

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, profile), initialProfile);
      expect(_rectOf(tester, accounts), initialAccounts);
      expect(tester.takeException(), isNull);
    }
  });
}
