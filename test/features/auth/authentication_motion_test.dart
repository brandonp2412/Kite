import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/authentication_screen.dart';

final class _DeferredDiscoveryGateway implements AuthenticationGateway {
  final discovery = Completer<HomeserverLoginMethods>();

  @override
  Future<HomeserverLoginMethods> discover(HomeserverAddress homeserver) {
    return discovery.future;
  }

  @override
  Future<AuthenticatedSession> loginWithOidc({
    required HomeserverAddress homeserver,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthenticatedSession> loginWithQrCode(String qrCodeData) {
    throw UnimplementedError();
  }

  @override
  Future<AuthenticatedSession> loginWithPassword({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthenticatedSession> loginWithSso({
    required HomeserverAddress homeserver,
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
  testWidgets(
    'homeserver discovery keeps auth heading geometry stable at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final gateway = _DeferredDiscoveryGateway();
      await tester.pumpWidget(
        MaterialApp(home: AuthenticationScreen(gateway: gateway)),
      );
      await tester.enterText(
        find.byKey(const Key('homeserver-field')),
        'matrix.example.org',
      );

      final heading = find.text('Sign in to Kite');
      final subtitle = find.byKey(const Key('auth-subtitle'));
      final initialHeading = _rectOf(tester, heading);
      final initialSubtitle = _rectOf(tester, subtitle);

      await tester.pump();
      await tester.tap(find.byKey(const Key('discover-homeserver')));
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, heading), initialHeading);
        expect(_rectOf(tester, subtitle), initialSubtitle);
        expect(tester.takeException(), isNull);
      }

      final homeserver = HomeserverAddress.parse('matrix.example.org');
      gateway.discovery.complete(
        HomeserverLoginMethods(
          homeserver: homeserver,
          methods: const <AuthenticationMethod>{AuthenticationMethod.password},
        ),
      );
      await tester.pump();

      expect(_rectOf(tester, heading), initialHeading);
      expect(_rectOf(tester, subtitle), initialSubtitle);
      expect(find.byKey(const Key('password-login')), findsOneWidget);
    },
  );
}
