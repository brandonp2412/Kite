import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_runtime.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/matrix/matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';

final class _RuntimeCredentials implements AppLockCredentialGateway {
  _RuntimeCredentials(this.stored);

  AppLockSettings stored;
  String pin = '1234';

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
  Future<AppLockSettings> loadSettings() async => stored;

  @override
  Future<void> saveSettings(AppLockSettings settings) async {
    stored = settings;
  }

  @override
  Future<bool> verifyPin(String pin) async => pin == this.pin;
}

final class _RuntimeBiometrics implements BiometricAuthenticationGateway {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => true;
}

final class _RuntimeNativeAuth implements MatrixNativeAuthSessionApi {
  _RuntimeNativeAuth({this.restoredSession});

  MatrixSdkSessionDescriptor? restoredSession;
  int discoveryCalls = 0;
  int loginCalls = 0;
  int persistCalls = 0;
  int logoutCalls = 0;
  int clearCalls = 0;
  final operations = <String>[];
  String? lastUsername;

  @override
  Future<void> clearSession() async {
    clearCalls += 1;
    operations.add('clear');
    restoredSession = null;
  }

  @override
  Future<MatrixSdkAuthenticationDiscovery> discoverAuthentication(
    Uri homeserver,
  ) async {
    discoveryCalls += 1;
    return MatrixSdkAuthenticationDiscovery(
      homeserver: homeserver,
      methods: const <MatrixSdkAuthenticationMethod>{
        MatrixSdkAuthenticationMethod.password,
      },
    );
  }

  @override
  Future<MatrixSdkSessionDescriptor> loginWithPassword({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    loginCalls += 1;
    lastUsername = username;
    if (password.isEmpty) throw StateError('Expected a password.');
    return MatrixSdkSessionDescriptor(
      userId: '@alice:${homeserver.host}',
      deviceId: 'DEVICE',
      homeserver: homeserver,
    );
  }

  @override
  Future<void> logoutSession(MatrixSdkSessionDescriptor session) async {
    logoutCalls += 1;
    operations.add('logout');
    restoredSession = null;
  }

  @override
  Future<void> persistSession(MatrixSdkSessionDescriptor session) async {
    persistCalls += 1;
    restoredSession = session;
  }

  @override
  Future<MatrixSdkSessionDescriptor?> restoreSession() async => restoredSession;
}

void main() {
  testWidgets(
    'runtime with disabled app lock exposes app content after restore',
    (tester) async {
      final controller = AppLockController(
        _RuntimeCredentials(const AppLockSettings.disabled()),
        _RuntimeBiometrics(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        KiteRuntime(
          appLockController: controller,
          home: const Text('private home', key: Key('runtime-private-home')),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.isReady.value, isTrue);
      expect(find.byKey(const Key('runtime-private-home')), findsOneWidget);
      expect(find.byKey(const Key('app-unlock-heading')), findsNothing);
    },
  );

  testWidgets(
    'native account runtime starts at authentication, not fixture home',
    (tester) async {
      final native = _RuntimeNativeAuth();

      await tester.pumpWidget(
        KiteRuntime(
          accountSdkBoundary: NativeMatrixAccountSdkBoundary(native),
          home: const Text('fixture home', key: Key('runtime-fixture-home')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('homeserver-field')), findsOneWidget);
      expect(find.byKey(const Key('runtime-fixture-home')), findsNothing);
    },
  );

  testWidgets('authenticated runtime never falls back to fixture home', (
    tester,
  ) async {
    final native = _RuntimeNativeAuth();
    final appLock = AppLockController(
      _RuntimeCredentials(const AppLockSettings.disabled()),
      _RuntimeBiometrics(),
    );
    addTearDown(appLock.dispose);

    await tester.pumpWidget(
      KiteRuntime(
        appLockController: appLock,
        accountSdkBoundary: NativeMatrixAccountSdkBoundary(native),
        home: const Text('fixture home', key: Key('runtime-fixture-home')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('homeserver-field')),
      'matrix.example.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-homeserver')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('username-field')), 'alice');
    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.pump();
    await tester.tap(find.byKey(const Key('password-login')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('runtime-fixture-home')), findsNothing);
    expect(find.byKey(const Key('matrix-runtime-unavailable')), findsOneWidget);
  });

  testWidgets(
    'password login persists session and hands it to runtime builder',
    (tester) async {
      final native = _RuntimeNativeAuth();
      final appLock = AppLockController(
        _RuntimeCredentials(const AppLockSettings.disabled()),
        _RuntimeBiometrics(),
      );
      addTearDown(appLock.dispose);

      await tester.pumpWidget(
        KiteRuntime(
          appLockController: appLock,
          accountSdkBoundary: NativeMatrixAccountSdkBoundary(native),
          home: const Text('fixture home', key: Key('runtime-fixture-home')),
          authenticatedHomeBuilder: (context, session) => Text(
            'authenticated ${session.userId}',
            key: const Key('runtime-authenticated-home'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('homeserver-field')),
        'matrix.example.org',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('discover-homeserver')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('username-field')), 'alice');
      await tester.enterText(find.byKey(const Key('password-field')), 'secret');
      await tester.pump();
      await tester.tap(find.byKey(const Key('password-login')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(native.discoveryCalls, 1);
      expect(native.loginCalls, 1);
      expect(native.persistCalls, 1);
      expect(native.lastUsername, 'alice');
      expect(
        find.byKey(const Key('runtime-authenticated-home')),
        findsOneWidget,
      );
      expect(
        find.text('authenticated @alice:matrix.example.org'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('runtime-fixture-home')), findsNothing);
    },
  );

  testWidgets(
    'restored native session reaches authenticated runtime directly',
    (tester) async {
      final native = _RuntimeNativeAuth(
        restoredSession: MatrixSdkSessionDescriptor(
          userId: '@alice:matrix.example.org',
          deviceId: 'RESTORED',
          homeserver: Uri.parse('https://matrix.example.org'),
        ),
      );
      final appLock = AppLockController(
        _RuntimeCredentials(const AppLockSettings.disabled()),
        _RuntimeBiometrics(),
      );
      final sessionInvalidation = ValueNotifier<int>(0);
      addTearDown(appLock.dispose);
      addTearDown(sessionInvalidation.dispose);

      await tester.pumpWidget(
        KiteRuntime(
          appLockController: appLock,
          accountSdkBoundary: NativeMatrixAccountSdkBoundary(native),
          sessionInvalidation: sessionInvalidation,
          authenticatedHomeBuilder: (context, session) => Text(
            '${session.userId}/${session.deviceId}',
            key: const Key('runtime-restored-home'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('runtime-restored-home')), findsOneWidget);
      expect(find.text('@alice:matrix.example.org/RESTORED'), findsOneWidget);
      expect(find.byKey(const Key('homeserver-field')), findsNothing);

      sessionInvalidation.value += 1;
      await tester.pump();
      expect(find.byKey(const Key('soft-logout-notice')), findsOneWidget);
      expect(find.byKey(const Key('runtime-restored-home')), findsNothing);
    },
  );

  testWidgets(
    'authenticated home exposes compact production sign out in safe teardown order',
    (tester) async {
      final native = _RuntimeNativeAuth(
        restoredSession: MatrixSdkSessionDescriptor(
          userId: '@alice:matrix.example.org',
          deviceId: 'RESTORED',
          homeserver: Uri.parse('https://matrix.example.org'),
        ),
      );
      final appLock = AppLockController(
        _RuntimeCredentials(const AppLockSettings.disabled()),
        _RuntimeBiometrics(),
      );
      addTearDown(appLock.dispose);

      await tester.pumpWidget(
        KiteRuntime(
          appLockController: appLock,
          accountSdkBoundary: NativeMatrixAccountSdkBoundary(native),
          beforeSignOut: (session) async {
            expect(session.userId, '@alice:matrix.example.org');
            native.operations.add('runtime-stop');
          },
          authenticatedHomeBuilder: (context, session) => const HomeScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('home-account-menu')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-account-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('@alice:matrix.example.org'), findsOneWidget);
      expect(find.text('Signed in on matrix.example.org'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-account-sign-out')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sign out from this device?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-account-sign-out-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(native.logoutCalls, 1);
      expect(native.clearCalls, 1);
      expect(native.operations, <String>['runtime-stop', 'logout', 'clear']);
      expect(find.byKey(const Key('homeserver-field')), findsOneWidget);
      expect(find.byKey(const Key('home-account-menu')), findsNothing);
    },
  );

  testWidgets('authenticated home omits read-all from the account menu', (
    tester,
  ) async {
    final native = _RuntimeNativeAuth(
      restoredSession: MatrixSdkSessionDescriptor(
        userId: '@alice:matrix.example.org',
        deviceId: 'RESTORED',
        homeserver: Uri.parse('https://matrix.example.org'),
      ),
    );
    final appLock = AppLockController(
      _RuntimeCredentials(const AppLockSettings.disabled()),
      _RuntimeBiometrics(),
    );
    addTearDown(appLock.dispose);
    final store = RoomListStateStore(const <RoomListEntry>[
      RoomListEntry(
        id: '!unread:matrix.example.org',
        name: 'Unread room',
        latestEventBody: 'Latest message',
        unreadCount: 3,
        hasMention: true,
      ),
    ]);
    var persistCalls = 0;

    await tester.pumpWidget(
      KiteRuntime(
        appLockController: appLock,
        accountSdkBoundary: NativeMatrixAccountSdkBoundary(native),
        authenticatedHomeBuilder: (context, session) => HomeScreen(
          roomListStore: store,
          onMarkAllRoomsRead: () async {
            persistCalls += 1;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('home-account-menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-account-mark-all-read')), findsNothing);
    expect(persistCalls, 0);
    expect(store.roomSignal('!unread:matrix.example.org').value.unreadCount, 3);
    expect(
      store.roomSignal('!unread:matrix.example.org').value.hasMention,
      isTrue,
    );
  });

  testWidgets(
    'runtime with enabled app lock withholds app content until unlock',
    (tester) async {
      final controller = AppLockController(
        _RuntimeCredentials(
          const AppLockSettings(
            enabled: true,
            biometricsEnabled: false,
            hideNotificationContents: true,
          ),
        ),
        _RuntimeBiometrics(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        KiteRuntime(
          appLockController: controller,
          home: const Text('private home', key: Key('runtime-private-home')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('runtime-private-home')), findsNothing);
      expect(find.byKey(const Key('app-unlock-heading')), findsOneWidget);
      expect(controller.shouldHideNotificationContents, isTrue);

      await tester.enterText(find.byKey(const Key('app-unlock-pin')), '1234');
      await tester.tap(find.byKey(const Key('app-unlock-pin-submit')));
      await tester.pumpAndSettle();

      expect(controller.isLocked.value, isFalse);
      expect(find.byKey(const Key('runtime-private-home')), findsOneWidget);
    },
  );
}
