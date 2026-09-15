import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:kite/features/auth/app_lock_gate.dart';
import 'package:kite/features/auth/platform_app_lock_gateway.dart';
import 'package:kite/features/home/home_screen.dart';

class KiteRuntime extends StatefulWidget {
  const KiteRuntime({
    super.key,
    this.appLockController,
    this.refreshNotificationPrivacy,
    this.home = const HomeScreen(),
  });

  final AppLockController? appLockController;
  final Future<void> Function()? refreshNotificationPrivacy;
  final Widget home;

  @override
  State<KiteRuntime> createState() => _KiteRuntimeState();
}

class _KiteRuntimeState extends State<KiteRuntime> {
  AppLockController? _appLockController;
  var _ownsAppLockController = false;

  @override
  void initState() {
    super.initState();
    _configureAppLock();
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

  @override
  void didUpdateWidget(KiteRuntime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.appLockController, widget.appLockController)) {
      return;
    }

    if (_ownsAppLockController) {
      _appLockController?.dispose();
    }
    _appLockController = null;
    _ownsAppLockController = false;
    _configureAppLock();
  }

  @override
  void dispose() {
    if (_ownsAppLockController) {
      _appLockController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLockController = _appLockController;
    final home = appLockController == null
        ? widget.home
        : AppLockGate(
            controller: appLockController,
            refreshNotificationPrivacy: widget.refreshNotificationPrivacy,
            child: widget.home,
          );
    return KiteApp(home: home);
  }
}

bool get _supportsPlatformAppLock =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
