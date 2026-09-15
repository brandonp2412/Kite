import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/auth/app_lock_gate.dart';

final class _GateCredentials implements AppLockCredentialGateway {
  AppLockSettings stored = const AppLockSettings.disabled();
  String pin = '1234';
  Completer<AppLockSettings>? deferredLoad;
  Object? loadError;

  @override
  Future<void> disable() async {
    stored = const AppLockSettings.disabled();
  }

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {
    this.pin = pin;
    stored = settings;
  }

  @override
  Future<AppLockSettings> loadSettings() async {
    if (loadError case final error?) throw error;
    final deferred = deferredLoad;
    if (deferred != null) return deferred.future;
    return stored;
  }

  @override
  Future<void> saveSettings(AppLockSettings settings) async {
    stored = settings;
  }

  @override
  Future<bool> verifyPin(String pin) async => pin == this.pin;
}

final class _GateBiometrics implements BiometricAuthenticationGateway {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => true;
}

Widget _app({
  required AppLockController controller,
  required Widget child,
  bool loadOnInit = true,
  Future<void> Function()? refreshNotificationPrivacy,
}) {
  return MaterialApp(
    home: AppLockGate(
      controller: controller,
      loadOnInit: loadOnInit,
      refreshNotificationPrivacy: refreshNotificationPrivacy,
      child: child,
    ),
  );
}

void main() {
  testWidgets(
    'protected content is withheld until lock restoration completes',
    (tester) async {
      final credentials = _GateCredentials()
        ..deferredLoad = Completer<AppLockSettings>();
      final controller = AppLockController(credentials, _GateBiometrics());
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          controller: controller,
          child: const Text('private timeline', key: Key('private-content')),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('app-lock-protected-heading')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('private-content')), findsNothing);
      expect(controller.shouldHideNotificationContents, isTrue);

      credentials.deferredLoad!.complete(const AppLockSettings.disabled());
      await tester.pumpAndSettle();

      expect(controller.isReady.value, isTrue);
      expect(find.byKey(const Key('private-content')), findsOneWidget);
    },
  );

  testWidgets('restoration failure stays protected and can be retried', (
    tester,
  ) async {
    final credentials = _GateCredentials()
      ..loadError = StateError('secure store unavailable');
    final controller = AppLockController(credentials, _GateBiometrics());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        controller: controller,
        child: const Text('private timeline', key: Key('private-content')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('private-content')), findsNothing);
    expect(find.byKey(const Key('app-lock-protected-error')), findsOneWidget);
    expect(find.text('Kite could not load app lock settings.'), findsOneWidget);

    credentials.loadError = null;
    await tester.tap(find.byKey(const Key('app-lock-protected-retry')));
    await tester.pumpAndSettle();

    expect(controller.isReady.value, isTrue);
    expect(find.byKey(const Key('private-content')), findsOneWidget);
  });

  testWidgets('failed PIN unlock clears the entered credential', (
    tester,
  ) async {
    final credentials = _GateCredentials()
      ..stored = const AppLockSettings(
        enabled: true,
        biometricsEnabled: false,
        hideNotificationContents: true,
      );
    final controller = AppLockController(credentials, _GateBiometrics());
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      _app(
        controller: controller,
        loadOnInit: false,
        child: const Text('private timeline', key: Key('private-content')),
      ),
    );

    final pinFinder = find.byKey(const Key('app-unlock-pin'));
    await tester.enterText(pinFinder, '9999');
    await tester.tap(find.byKey(const Key('app-unlock-pin-submit')));
    await tester.pumpAndSettle();

    final pinField = tester.widget<TextField>(pinFinder);
    expect(pinField.controller?.text, isEmpty);
    expect(controller.isLocked.value, isTrue);
    expect(find.text('Incorrect PIN.'), findsOneWidget);
  });

  testWidgets(
    'backgrounding relocks and unlocking refreshes notification privacy',
    (tester) async {
      final credentials = _GateCredentials()
        ..stored = const AppLockSettings(
          enabled: true,
          biometricsEnabled: false,
          hideNotificationContents: true,
        );
      final controller = AppLockController(credentials, _GateBiometrics());
      addTearDown(controller.dispose);
      await controller.load();
      expect(await controller.unlockWithPin('1234'), isTrue);

      var privacyRefreshes = 0;
      await tester.pumpWidget(
        _app(
          controller: controller,
          loadOnInit: false,
          refreshNotificationPrivacy: () async {
            privacyRefreshes += 1;
          },
          child: const Text('private timeline', key: Key('private-content')),
        ),
      );
      expect(find.byKey(const Key('private-content')), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();

      expect(controller.isLocked.value, isTrue);
      expect(find.byKey(const Key('private-content')), findsNothing);
      expect(find.byKey(const Key('app-unlock-heading')), findsOneWidget);
      expect(privacyRefreshes, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.isLocked.value, isTrue);

      await tester.enterText(find.byKey(const Key('app-unlock-pin')), '1234');
      await tester.tap(find.byKey(const Key('app-unlock-pin-submit')));
      await tester.pumpAndSettle();

      expect(controller.isLocked.value, isFalse);
      expect(find.byKey(const Key('private-content')), findsOneWidget);
      expect(privacyRefreshes, 2);
    },
  );
}
