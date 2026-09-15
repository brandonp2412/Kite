import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/account_registration_screen.dart';
import 'package:kite/features/auth/authentication_gateway.dart';

final class _DeferredRegistrationGateway implements AccountRegistrationGateway {
  final beginStep = Completer<AccountRegistrationStep>();

  @override
  Future<AccountRegistrationStep> begin(HomeserverAddress homeserver) =>
      beginStep.future;

  @override
  Future<AccountRegistrationStep> continueInteractiveAuthentication({
    required HomeserverAddress homeserver,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AccountRegistrationStep> submitCredentials({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) {
    throw UnimplementedError();
  }
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

void main() {
  testWidgets('registration discovery reserves stable 120 Hz geometry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    final homeserver = HomeserverAddress.parse('matrix.example.org');
    final gateway = _DeferredRegistrationGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountRegistrationScreen(
          homeserver: homeserver,
          gateway: gateway,
        ),
      ),
    );

    final heading = find.byKey(const Key('registration-heading'));
    final status = find.byKey(const Key('registration-status-slot'));
    final action = find.byKey(const Key('registration-action-slot'));
    final headingRect = _rectOf(tester, heading);
    final statusRect = _rectOf(tester, status);
    final actionRect = _rectOf(tester, action);

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(_rectOf(tester, heading), headingRect);
      expect(_rectOf(tester, status), statusRect);
      expect(_rectOf(tester, action), actionRect);
      expect(tester.takeException(), isNull);
    }

    gateway.beginStep.complete(const RegistrationCredentialsStep());
    await tester.pump();

    expect(_rectOf(tester, heading), headingRect);
    expect(_rectOf(tester, status), statusRect);
    expect(_rectOf(tester, action), actionRect);
    expect(
      find.byKey(const Key('registration-submit-credentials')),
      findsOneWidget,
    );
  });
}
