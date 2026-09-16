import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/auth/account_security_runtime.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/auth/app_lock_gate.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/auth/platform_app_lock_gateway.dart';
import 'package:kite/features/auth/session_gate.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/matrix/matrix_account_sdk_boundary.dart';

class KiteRuntime extends StatefulWidget {
  const KiteRuntime({
    super.key,
    this.appLockController,
    this.refreshNotificationPrivacy,
    this.accountSdkBoundary,
    this.authenticatedHomeBuilder,
    this.requireSessionVerification = false,
    this.home = const HomeScreen(),
  });

  final AppLockController? appLockController;
  final Future<void> Function()? refreshNotificationPrivacy;
  final MatrixAccountSdkBoundary? accountSdkBoundary;
  final AuthenticatedSessionBuilder? authenticatedHomeBuilder;
  final bool requireSessionVerification;
  final Widget home;

  @override
  State<KiteRuntime> createState() => _KiteRuntimeState();
}

class _KiteRuntimeState extends State<KiteRuntime> {
  AppLockController? _appLockController;
  AccountSecurityRuntime? _accountSecurityRuntime;
  var _ownsAppLockController = false;

  @override
  void initState() {
    super.initState();
    _configureAppLock();
    _configureAccountSecurity();
  }

  void _configureAppLock() {
    final injected = widget.appLockController;
    if (injected != null) {
      _appLockController = injected;
      return;
    }
    if (!_supportsPlatformAppLock) return;

    final gateway = PlatformAppLockGateway();
    _appLockController = AppLockController(gateway, gateway);
    _ownsAppLockController = true;
  }

  void _configureAccountSecurity() {
    final boundary = widget.accountSdkBoundary;
    if (boundary == null) return;
    _accountSecurityRuntime = AccountSecurityRuntime(boundary);
  }

  @override
  void didUpdateWidget(KiteRuntime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.appLockController, widget.appLockController)) {
      if (_ownsAppLockController) {
        _appLockController?.dispose();
      }
      _appLockController = null;
      _ownsAppLockController = false;
      _configureAppLock();
    }

    if (!identical(oldWidget.accountSdkBoundary, widget.accountSdkBoundary)) {
      _accountSecurityRuntime?.dispose();
      _accountSecurityRuntime = null;
      _configureAccountSecurity();
    }
  }

  @override
  void dispose() {
    _accountSecurityRuntime?.dispose();
    if (_ownsAppLockController) {
      _appLockController?.dispose();
    }
    super.dispose();
  }

  Widget _withAppLock(Widget child) {
    final appLockController = _appLockController;
    return appLockController == null
        ? child
        : AppLockGate(
            controller: appLockController,
            refreshNotificationPrivacy: widget.refreshNotificationPrivacy,
            child: child,
          );
  }

  Widget _authenticatedHome(
    BuildContext context,
    AuthenticatedSession session,
  ) {
    final builder = widget.authenticatedHomeBuilder;
    if (builder != null) return builder(context, session);
    return const Scaffold(
      body: Center(
        child: Text(
          'Matrix runtime is unavailable.',
          key: Key('matrix-runtime-unavailable'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountSecurity = _accountSecurityRuntime;
    if (accountSecurity == null) {
      return KiteApp(home: _withAppLock(widget.home));
    }

    return KiteApp(
      home: SessionGate(
        lifecycleController: accountSecurity.lifecycle,
        authenticationGateway: accountSecurity.gateway,
        verificationController: accountSecurity.verification,
        requireVerification: widget.requireSessionVerification,
        authenticatedBuilder: (context) => _withAppLock(
          const Scaffold(
            body: Center(child: Text('Matrix runtime is unavailable.')),
          ),
        ),
        authenticatedSessionBuilder: (context, session) =>
            _withAppLock(_authenticatedHome(context, session)),
      ),
    );
  }
}

bool get _supportsPlatformAppLock =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
