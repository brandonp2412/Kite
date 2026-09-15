import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/auth/account_management_controller.dart';
import 'package:kite/features/auth/account_security_screen.dart';
import 'package:kite/features/auth/authentication_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/auth/app_unlock_screen.dart';
import 'package:kite/features/auth/authentication_screen.dart';
import 'package:kite/features/auth/session_device_controller.dart';
import 'package:kite/benchmark/timeline_benchmark_surface.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/settings/app_lock_settings_screen.dart';
import 'package:kite/features/settings/general_settings_screen.dart';
import 'package:kite/features/settings/notification_settings_screen.dart';
import 'package:kite/features/settings/settings_controller.dart';
import 'package:kite/features/settings/support_settings_controller.dart';
import 'package:kite/features/settings/support_settings_screen.dart';

import 'performance_benchmark_harness.dart';

final class _BenchmarkAuthenticationGateway implements AuthenticationGateway {
  _BenchmarkAuthenticationGateway(this.methods);

  final Set<AuthenticationMethod> methods;

  @override
  Future<HomeserverLoginMethods> discover(HomeserverAddress homeserver) async {
    return HomeserverLoginMethods(homeserver: homeserver, methods: methods);
  }

  AuthenticatedSession _session(HomeserverAddress homeserver) {
    return AuthenticatedSession(
      userId: '@benchmark:${homeserver.uri.host}',
      deviceId: 'BENCHMARK_DEVICE',
      homeserver: homeserver,
    );
  }

  @override
  Future<AuthenticatedSession> loginWithOidc({
    required HomeserverAddress homeserver,
  }) async => _session(homeserver);

  @override
  Future<AuthenticatedSession> loginWithQrCode(String qrCodeData) async =>
      _session(HomeserverAddress.parse('matrix.example.org'));

  @override
  Future<AuthenticatedSession> loginWithPassword({
    required HomeserverAddress homeserver,
    required String username,
    required String password,
  }) async => _session(homeserver);

  @override
  Future<AuthenticatedSession> loginWithSso({
    required HomeserverAddress homeserver,
  }) async => _session(homeserver);
}

final class _BenchmarkAccountGateway implements AccountManagementGateway {
  @override
  Future<void> activateAccount(String accountId) async {}

  @override
  Future<List<ManagedMatrixAccount>> loadAccounts() async {
    return <ManagedMatrixAccount>[
      ManagedMatrixAccount(
        accountId: 'work',
        displayName: 'Work',
        isActive: true,
        session: AuthenticatedSession(
          userId: '@benchmark:work.example.org',
          deviceId: 'WORK_DEVICE',
          homeserver: HomeserverAddress.parse('work.example.org'),
        ),
      ),
      ManagedMatrixAccount(
        accountId: 'personal',
        displayName: 'Personal',
        isActive: false,
        session: AuthenticatedSession(
          userId: '@benchmark:example.org',
          deviceId: 'PERSONAL_DEVICE',
          homeserver: HomeserverAddress.parse('example.org'),
        ),
      ),
    ];
  }

  @override
  Future<void> signOutAccount(String accountId) async {}
}

final class _BenchmarkSessionDeviceGateway implements SessionDeviceGateway {
  @override
  Future<List<SessionDevice>> loadDevices() async {
    return const <SessionDevice>[
      SessionDevice(
        deviceId: 'CURRENT',
        displayName: 'Benchmark device',
        isCurrent: true,
        verification: SessionDeviceVerification.verified,
      ),
      SessionDevice(
        deviceId: 'REMOTE',
        displayName: 'Remote device',
        isCurrent: false,
        verification: SessionDeviceVerification.unverified,
      ),
    ];
  }

  @override
  Future<void> signOutDevice(String deviceId) async {}
}

final class _BenchmarkSettingsGateway implements SettingsGateway {
  @override
  Future<KiteSettings> load() async => const KiteSettings.defaults();

  @override
  Future<void> saveAppearance(KiteAppearanceMode appearanceMode) async {}

  @override
  Future<void> saveLanguage(String? languageTag) async {}

  @override
  Future<void> saveNotificationMaster(bool enabled) async {}

  @override
  Future<void> saveNotificationCategory({
    required NotificationCategory category,
    required bool enabled,
  }) async {}

  @override
  Future<void> saveRoomNotificationMode({
    required String roomId,
    required RoomNotificationMode mode,
  }) async {}

  @override
  Future<void> saveMessageNotificationSound(String? soundId) async {}

  @override
  Future<void> saveCallRingtone(String? soundId) async {}
}

final class _BenchmarkAppLockCredentials implements AppLockCredentialGateway {
  AppLockSettings stored = const AppLockSettings(
    enabled: true,
    biometricsEnabled: true,
    hideNotificationContents: true,
  );
  final String pin = '1234';

  @override
  Future<void> disable() async {
    stored = const AppLockSettings.disabled();
  }

  @override
  Future<void> enablePin({
    required String pin,
    required AppLockSettings settings,
  }) async {
    stored = settings;
  }

  @override
  Future<AppLockSettings> loadSettings() async => stored;

  @override
  Future<void> saveSettings(AppLockSettings settings) async {
    stored = settings;
  }

  @override
  Future<bool> verifyPin(String pin) async => pin == this.pin;
}

final class _BenchmarkBiometrics implements BiometricAuthenticationGateway {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => true;
}

final class _BenchmarkSupportSettingsGateway implements SupportSettingsGateway {
  StorageUsageSnapshot storage = const StorageUsageSnapshot(
    mediaCacheBytes: 2048,
    presentationCacheBytes: 1024,
    diagnosticLogBytes: 512,
  );

  @override
  Future<void> clearMediaCache() async {
    storage = StorageUsageSnapshot(
      mediaCacheBytes: 0,
      presentationCacheBytes: storage.presentationCacheBytes,
      diagnosticLogBytes: storage.diagnosticLogBytes,
    );
  }

  @override
  Future<void> clearPresentationCache() async {
    storage = StorageUsageSnapshot(
      mediaCacheBytes: storage.mediaCacheBytes,
      presentationCacheBytes: 0,
      diagnosticLogBytes: storage.diagnosticLogBytes,
    );
  }

  @override
  Future<AppAboutInfo> loadAboutInfo() async {
    return const AppAboutInfo(
      version: '1.0.0',
      buildNumber: '1',
      licenseCount: 3,
    );
  }

  @override
  Future<StorageUsageSnapshot> loadStorageUsage() async => storage;

  @override
  Future<SanitizedDiagnosticBundle> prepareSanitizedDiagnostics() async {
    return SanitizedDiagnosticBundle(
      generatedAt: DateTime.utc(2026, 9, 15, 5),
      structuredEventCount: 4,
      crashReportCount: 1,
    );
  }

  @override
  Future<void> submitProblemReport(ProblemReportRequest report) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  testWidgets('3,000-room list scroll has zero late Flutter frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(benchmarkRooms: BenchmarkFixture.largeRoomListRooms),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      BenchmarkFixture.largeRoomListRooms,
      hasLength(PerformanceContract.roomListBenchmarkRoomCount),
    );

    final result = await measureFrames(
      binding: binding,
      action: () async {
        final list = find.byKey(const Key('room-list'));
        await tester.fling(list, const Offset(0, -1200), 5000);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, -1200), 5000);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, 1200), 5000);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['room_list_scroll_3000'] = <String, dynamic>{
      'journey': 'room_list_scroll',
      'fixture': 'deterministic_3000_rooms_v1',
      'roomCount': BenchmarkFixture.largeRoomListRooms.length,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('notification settings mutations have zero late Flutter frames', (
    tester,
  ) async {
    final controller = SettingsController(_BenchmarkSettingsGateway());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsScreen(
          controller: controller,
          roomId: '!kite:example.org',
          roomName: 'Kite room',
          messageSounds: const <NotificationSoundOption>[
            NotificationSoundOption(id: 'soft', label: 'Soft'),
          ],
          callRingtones: const <NotificationSoundOption>[
            NotificationSoundOption(id: 'bright', label: 'Bright'),
          ],
          loadOnInit: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        final master = find.byKey(const Key('notification-master'));
        await tester.tap(master);
        await tester.pump();
        await tester.tap(master);
        await tester.pump();

        await tester.tap(
          find.byKey(const Key('notification-category-mentions')),
        );
        await tester.pump();

        final roomMode = find.byKey(const Key('room-notification-mode'));
        await tester.ensureVisible(roomMode);
        await tester.tap(roomMode);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mentions only').last);
        await tester.pumpAndSettle();

        final messageSound = find.byKey(
          const Key('message-notification-sound'),
        );
        await tester.ensureVisible(messageSound);
        await tester.tap(messageSound);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Soft').last);
        await tester.pumpAndSettle();

        final callRingtone = find.byKey(
          const Key('call-notification-ringtone'),
        );
        await tester.ensureVisible(callRingtone);
        await tester.tap(callRingtone);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bright').last);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(controller.settings.value.notifications.masterEnabled, isTrue);
    expect(
      controller.settings.value.notifications.enabledCategories,
      isNot(contains(NotificationCategory.mentions)),
    );
    expect(
      controller.settings.value.notifications.roomMode('!kite:example.org'),
      RoomNotificationMode.mentionsOnly,
    );
    expect(controller.settings.value.notifications.messageSoundId, 'soft');
    expect(controller.settings.value.notifications.callRingtoneId, 'bright');

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['notification_settings_mutations'] = <String, dynamic>{
      'journey': 'notification_settings_mutations',
      'fixture': 'deterministic_notification_settings_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('general settings mutations have zero late Flutter frames', (
    tester,
  ) async {
    final controller = SettingsController(_BenchmarkSettingsGateway());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GeneralSettingsScreen(controller: controller, loadOnInit: false),
      ),
    );
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('appearance-dark')));
        await tester.pumpAndSettle();

        final languagePicker = find.byKey(const Key('language-picker'));
        await tester.ensureVisible(languagePicker);
        await tester.tap(languagePicker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('English (New Zealand)').last);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(controller.settings.value.appearanceMode, KiteAppearanceMode.dark);
    expect(controller.settings.value.languageTag, 'en-NZ');

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['general_settings_mutations'] = <String, dynamic>{
      'journey': 'general_settings_mutations',
      'fixture': 'deterministic_general_settings_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('support settings mutations have zero late Flutter frames', (
    tester,
  ) async {
    final gateway = _BenchmarkSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: SupportSettingsScreen(controller: controller, loadOnInit: false),
      ),
    );
    await tester.pumpAndSettle();

    final clearResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('clear-cached-content')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.storage.value?.clearableBytes, 0);
    expect(controller.storage.value?.diagnosticLogBytes, 512);

    final reportResult = await measureFrames(
      binding: binding,
      action: () async {
        await controller.submitProblemReport('Benchmark support report');
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(controller.reportSubmitted.value, isTrue);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['support_settings_clear_cache'] = <String, dynamic>{
      'journey': 'support_settings_clear_cache',
      'fixture': 'deterministic_support_settings_v1',
      ...clearResult,
      'result': 'PASS',
    };
    binding.reportData!['support_settings_problem_report'] = <String, dynamic>{
      'journey': 'support_settings_problem_report',
      'fixture': 'deterministic_support_settings_v1',
      ...reportResult,
      'result': 'PASS',
    };
  });

  testWidgets(
    'warm app lock settings mutations have zero late Flutter frames',
    (tester) async {
      final credentials = _BenchmarkAppLockCredentials();
      final controller = AppLockController(credentials, _BenchmarkBiometrics());
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          home: AppLockSettingsScreen(
            controller: controller,
            loadOnInit: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final biometrics = find.byKey(const Key('app-lock-biometrics'));
      final privacy = find.byKey(const Key('app-lock-hide-notifications'));
      await tester.tap(biometrics);
      await tester.pumpAndSettle();
      await tester.tap(biometrics);
      await tester.pumpAndSettle();
      await tester.tap(privacy);
      await tester.pumpAndSettle();
      await tester.tap(privacy);
      await tester.pumpAndSettle();

      final result = await measureFrames(
        binding: binding,
        action: () async {
          await tester.tap(biometrics);
          await tester.pumpAndSettle();
          await tester.tap(privacy);
          await tester.pumpAndSettle();
        },
        enforceTotalSpan: enforceTotalSpan,
      );

      expect(controller.settings.value.biometricsEnabled, isFalse);
      expect(controller.settings.value.hideNotificationContents, isFalse);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['app_lock_settings_mutations'] = <String, dynamic>{
        'journey': 'app_lock_settings_mutations',
        'fixture': 'deterministic_app_lock_v1',
        ...result,
        'result': 'PASS',
      };
    },
  );

  testWidgets('warm app unlock has zero late Flutter frames', (tester) async {
    final credentials = _BenchmarkAppLockCredentials();
    final controller = AppLockController(credentials, _BenchmarkBiometrics());
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: AppUnlockScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(await controller.unlockWithPin('1234'), isTrue);
    await tester.pumpAndSettle();
    controller.lock();
    await tester.pumpAndSettle();

    final result = await measureFrames(
      binding: binding,
      action: () async {
        expect(await controller.unlockWithPin('1234'), isTrue);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(controller.isLocked.value, isFalse);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['app_unlock'] = <String, dynamic>{
      'journey': 'app_unlock',
      'fixture': 'deterministic_app_lock_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('authentication interactions have zero late Flutter frames', (
    tester,
  ) async {
    final gateway = _BenchmarkAuthenticationGateway(
      const <AuthenticationMethod>{
        AuthenticationMethod.password,
        AuthenticationMethod.oidc,
        AuthenticationMethod.sso,
      },
    );
    final controllers = <AuthenticationController>[];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });

    Future<AuthenticationController> pumpAuthentication() async {
      final controller = AuthenticationController(gateway);
      controllers.add(controller);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthenticationScreen(
            key: UniqueKey(),
            gateway: gateway,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    var controller = await pumpAuthentication();
    final discoveryResult = await measureFrames(
      binding: binding,
      action: () async {
        await controller.discover('matrix.example.org');
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('password-login')), findsOneWidget);

    final passwordResult = await measureFrames(
      binding: binding,
      action: () async {
        await controller.loginWithPassword(
          username: 'benchmark',
          password: 'benchmark-password',
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('authenticated-session')), findsOneWidget);

    controller = await pumpAuthentication();
    await controller.discover('matrix.example.org');
    await tester.pumpAndSettle();
    final oidcResult = await measureFrames(
      binding: binding,
      action: () async {
        await controller.loginWithOidc();
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('authenticated-session')), findsOneWidget);

    controller = await pumpAuthentication();
    await controller.discover('matrix.example.org');
    await tester.pumpAndSettle();
    final ssoResult = await measureFrames(
      binding: binding,
      action: () async {
        await controller.loginWithSso();
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('authenticated-session')), findsOneWidget);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['authentication_homeserver_discovery'] =
        <String, dynamic>{
          'journey': 'authentication_homeserver_discovery',
          'fixture': 'deterministic_authentication_v1',
          ...discoveryResult,
          'result': 'PASS',
        };
    binding.reportData!['authentication_password_login'] = <String, dynamic>{
      'journey': 'authentication_password_login',
      'fixture': 'deterministic_authentication_v1',
      ...passwordResult,
      'result': 'PASS',
    };
    binding.reportData!['authentication_oidc_login'] = <String, dynamic>{
      'journey': 'authentication_oidc_login',
      'fixture': 'deterministic_authentication_v1',
      ...oidcResult,
      'result': 'PASS',
    };
    binding.reportData!['authentication_sso_login'] = <String, dynamic>{
      'journey': 'authentication_sso_login',
      'fixture': 'deterministic_authentication_v1',
      ...ssoResult,
      'result': 'PASS',
    };
  });

  testWidgets('account and session management have zero late Flutter frames', (
    tester,
  ) async {
    final accounts = AccountManagementController(_BenchmarkAccountGateway());
    final devices = SessionDeviceController(_BenchmarkSessionDeviceGateway());
    addTearDown(accounts.dispose);
    addTearDown(devices.dispose);
    await accounts.load();
    await devices.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AccountSecurityScreen(
          accountController: accounts,
          sessionDeviceController: devices,
          loadOnInit: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switchResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('activate-account-personal')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(accounts.activeAccount?.accountId, 'personal');

    final remoteSignOutResult = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('sign-out-device-REMOTE')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('account-security-confirm-Sign out device')),
        );
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );
    expect(find.byKey(const Key('device-REMOTE')), findsNothing);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['account_switch'] = <String, dynamic>{
      'journey': 'account_switch',
      'fixture': 'deterministic_account_security_v1',
      ...switchResult,
      'result': 'PASS',
    };
    binding.reportData!['remote_session_sign_out'] = <String, dynamic>{
      'journey': 'remote_session_sign_out',
      'fixture': 'deterministic_account_security_v1',
      ...remoteSignOutResult,
      'result': 'PASS',
    };
  });

  testWidgets('composer keyboard appearance has zero late Flutter frames', (
    tester,
  ) async {
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    final composer = find.descendant(
      of: find.byKey(const Key('composer')),
      matching: find.byType(TextField),
    );
    expect(composer, findsOneWidget);

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(composer);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['composer_keyboard'] = <String, dynamic>{
      'journey': 'composer_keyboard',
      'fixture': 'deterministic_v1',
      ...result,
      'result': 'PASS',
    };

    // Keep subsequent journey measurements isolated from the platform IME.
    editable.focusNode.unfocus();
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });

  testWidgets('mixed rich timeline scroll has zero late Flutter frames', (
    tester,
  ) async {
    final controller = TimelineBenchmarkController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      controller.messages.value,
      hasLength(PerformanceContract.timelineBenchmarkMessageCount),
    );
    expect(
      controller.messages.value.map((message) => message.kind).toSet(),
      hasLength(BenchmarkMessageKind.values.length),
    );

    final result = await measureFrames(
      binding: binding,
      action: () async {
        final list = find.byKey(const Key('benchmark-message-list'));
        await tester.fling(list, const Offset(0, 1400), 5200);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, 1400), 5200);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, -1400), 5200);
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_scroll_mixed_rich'] = <String, dynamic>{
      'journey': 'timeline_scroll_mixed_rich',
      'fixture': 'deterministic_1200_mixed_events_v1',
      'messageCount': controller.messages.value.length,
      'eventKinds': BenchmarkMessageKind.values.length,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('timeline pagination has zero late Flutter frames', (
    tester,
  ) async {
    final controller = TimelineBenchmarkController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
    );
    await tester.pumpAndSettle();

    final initialCount = controller.messages.value.length;
    final result = await measureFrames(
      binding: binding,
      action: () async {
        controller.prependOlderPage();
        await tester.pump();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(
      controller.messages.value,
      hasLength(initialCount + PerformanceContract.paginationBenchmarkPageSize),
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_pagination'] = <String, dynamic>{
      'journey': 'timeline_pagination',
      'fixture': 'deterministic_100_older_events_v1',
      'pageSize': PerformanceContract.paginationBenchmarkPageSize,
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets('new-message insertion has zero late Flutter frames', (
    tester,
  ) async {
    final controller = TimelineBenchmarkController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
    );
    await tester.pumpAndSettle();

    final initialCount = controller.messages.value.length;
    final result = await measureFrames(
      binding: binding,
      action: () async {
        controller.insertIncomingMessage();
        await tester.pump();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    expect(controller.messages.value, hasLength(initialCount + 1));
    expect(
      find.byKey(const Key('benchmark-message-incoming-timeline-message')),
      findsOneWidget,
    );
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['timeline_new_message'] = <String, dynamic>{
      'journey': 'timeline_new_message',
      'fixture': 'deterministic_incoming_event_v1',
      ...result,
      'result': 'PASS',
    };
  });

  testWidgets(
    'reaction receipt and typing updates have zero late Flutter frames',
    (tester) async {
      final controller = TimelineBenchmarkController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: TimelineBenchmarkSurface(controller: controller)),
      );
      await tester.pumpAndSettle();

      const iterations = 20;
      final initialReactionCount = controller.reactionCount.value;
      final initialReceiptCount = controller.readReceiptCount.value;
      final result = await measureFrames(
        binding: binding,
        action: () async {
          for (var index = 0; index < iterations; index++) {
            controller.updateEphemeralState();
            await tester.pump();
          }
        },
        enforceTotalSpan: enforceTotalSpan,
      );

      expect(controller.reactionCount.value, initialReactionCount + iterations);
      expect(
        controller.readReceiptCount.value,
        initialReceiptCount + iterations,
      );
      expect(controller.typing.value, isFalse);
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['timeline_ephemeral_updates'] = <String, dynamic>{
        'journey': 'reaction_read_receipt_typing_update',
        'fixture': 'deterministic_ephemeral_updates_v1',
        'iterations': iterations,
        ...result,
        'result': 'PASS',
      };
    },
  );
}
