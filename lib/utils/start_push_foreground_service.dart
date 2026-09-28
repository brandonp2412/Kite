// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:universal_html/html.dart' as html;

import '../l10n/l10n.dart';

abstract class ForegroundServices {
  static final List<String> runningServices = [];
  static const String directSyncServiceName = 'direct_sync';
  static bool _runningAsDirectSync = false;

  static bool get platformSupported =>
      PlatformInfos.isMobile || PlatformInfos.isWeb;

  static bool _beforeUnload(html.Event e) {
    e.preventDefault();
    return true;
  }

  static Future<void> stopService(String name) async {
    runningServices.remove(name);
    if (runningServices.isNotEmpty) return;
    if (kIsWeb) {
      html.window.removeEventListener('beforeunload', _beforeUnload);
      return;
    }
    await FlutterForegroundTask.stopService();
    _runningAsDirectSync = false;
  }

  static Future<bool> startService(String name) async {
    try {
      if (!runningServices.contains(name)) {
        runningServices.add(name);
      }
      if (kIsWeb) {
        html.window.addEventListener('beforeunload', _beforeUnload);
        return true;
      }
      if (!PlatformInfos.isMobile) return true;

      final directSync = name == directSyncServiceName;
      final l10n = await L10n.delegate.load(PlatformDispatcher.instance.locale);
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'fluffychat_sync',
          channelName: directSync
              ? 'FluffyChat background sync'
              : l10n.loadingMessages,
          channelDescription: directSync
              ? 'Keeps Matrix connected for message notifications'
              : l10n.loadingMessages,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
          allowAutoRestart: true,
          stopWithTask: directSync ? false : null,
        ),
      );

      final alreadyRunning = await FlutterForegroundTask.isRunningService;
      if (alreadyRunning && (!directSync || _runningAsDirectSync)) {
        Logs().d('[PushHelper] Foreground service already running');
        return true;
      }
      if (alreadyRunning && directSync && !_runningAsDirectSync) {
        await FlutterForegroundTask.stopService();
      }

      final result = await FlutterForegroundTask.startService(
        serviceTypes: [
          directSync
              ? ForegroundServiceTypes.remoteMessaging
              : ForegroundServiceTypes.shortService,
        ],
        notificationTitle: 'FluffyChat Test',
        notificationText: directSync
            ? 'Listening for new Matrix messages'
            : l10n.loadingMessages,
        notificationIcon: NotificationIcon(metaDataName: 'ic_launcher'),
      );
      final started = result is ServiceRequestSuccess;
      if (started) {
        _runningAsDirectSync = directSync;
      } else {
        runningServices.remove(name);
      }
      Logs().d('[PushHelper] Foreground service start: $started ($result)');
      return started;
    } catch (e, s) {
      runningServices.remove(name);
      Logs().w('[PushHelper] Unable to start foreground service', e, s);
      return false;
    }
  }
}
