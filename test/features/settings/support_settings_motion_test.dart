import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/settings/support_settings_controller.dart';
import 'package:kite/features/settings/support_settings_screen.dart';

final class _DeferredSupportGateway implements SupportSettingsGateway {
  final clearMedia = Completer<void>();

  @override
  Future<void> clearMediaCache() => clearMedia.future;

  @override
  Future<void> clearPresentationCache() async {}

  @override
  Future<AppAboutInfo> loadAboutInfo() async {
    return const AppAboutInfo(
      version: '1.0.0',
      buildNumber: '1',
      licenseCount: 3,
    );
  }

  @override
  Future<StorageUsageSnapshot> loadStorageUsage() async {
    return const StorageUsageSnapshot(
      mediaCacheBytes: 2048,
      presentationCacheBytes: 1024,
      diagnosticLogBytes: 512,
    );
  }

  @override
  Future<SanitizedDiagnosticBundle> prepareSanitizedDiagnostics() async {
    return SanitizedDiagnosticBundle(
      generatedAt: DateTime.utc(2026, 9, 15, 5),
      structuredEventCount: 1,
      crashReportCount: 0,
    );
  }

  @override
  Future<void> submitProblemReport(ProblemReportRequest report) async {}
}

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

void main() {
  testWidgets(
    'cache clearing keeps support settings geometry stable at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      final gateway = _DeferredSupportGateway();
      final controller = SupportSettingsController(gateway);
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          home: SupportSettingsScreen(
            controller: controller,
            loadOnInit: false,
          ),
        ),
      );

      final list = find.byKey(const Key('support-settings-list'));
      final report = find.byKey(const Key('problem-description'));
      final about = find.byKey(const Key('about-info'));
      final initialList = _rectOf(tester, list);
      final initialReport = _rectOf(tester, report);
      final initialAbout = _rectOf(tester, about);

      await tester.tap(find.byKey(const Key('clear-cached-content')));
      await tester.pump();

      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        expect(_rectOf(tester, list), initialList);
        expect(_rectOf(tester, report), initialReport);
        expect(_rectOf(tester, about), initialAbout);
        expect(tester.takeException(), isNull);
      }

      gateway.clearMedia.complete();
      await tester.pumpAndSettle();
      expect(_rectOf(tester, list), initialList);
      expect(_rectOf(tester, report), initialReport);
      expect(_rectOf(tester, about), initialAbout);
    },
  );
}
