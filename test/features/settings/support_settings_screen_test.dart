import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/settings/support_settings_controller.dart';
import 'package:kite/features/settings/support_settings_screen.dart';

final class _FakeSupportSettingsGateway implements SupportSettingsGateway {
  StorageUsageSnapshot storage = const StorageUsageSnapshot(
    mediaCacheBytes: 2048,
    presentationCacheBytes: 1024,
    diagnosticLogBytes: 512,
  );
  AppAboutInfo about = const AppAboutInfo(
    version: '1.2.3',
    buildNumber: '45',
    licenseCount: 7,
  );
  ProblemReportRequest? submitted;

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
  Future<AppAboutInfo> loadAboutInfo() async => about;

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
  Future<void> submitProblemReport(ProblemReportRequest report) async {
    submitted = report;
  }
}

Widget _app(SupportSettingsController controller) {
  return MaterialApp(
    home: SupportSettingsScreen(controller: controller, loadOnInit: false),
  );
}

void main() {
  testWidgets('shows storage usage and preserves diagnostic logs on clear', (
    tester,
  ) async {
    final gateway = _FakeSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));

    expect(find.text('2.0 KiB'), findsOneWidget);
    expect(find.text('1.0 KiB'), findsOneWidget);
    expect(find.text('512 B'), findsOneWidget);
    expect(
      find.text('Preserved when cached content is cleared.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('clear-cached-content')));
    await tester.pumpAndSettle();

    expect(controller.storage.value?.mediaCacheBytes, 0);
    expect(controller.storage.value?.presentationCacheBytes, 0);
    expect(controller.storage.value?.diagnosticLogBytes, 512);
    expect(find.text('0 B'), findsNWidgets(2));
    expect(find.text('512 B'), findsOneWidget);
  });

  testWidgets('submits only sanitized diagnostic metadata', (tester) async {
    final gateway = _FakeSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));
    await tester.enterText(
      find.byKey(const Key('problem-description')),
      'Timeline briefly froze',
    );
    await tester.tap(find.byKey(const Key('submit-problem-report')));
    await tester.pumpAndSettle();

    expect(gateway.submitted?.description, 'Timeline briefly froze');
    expect(gateway.submitted?.diagnostics.structuredEventCount, 4);
    expect(gateway.submitted?.diagnostics.crashReportCount, 1);
    await tester.scrollUntilVisible(
      find.byKey(const Key('support-settings-status')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Problem report sent.'), findsOneWidget);
  });

  testWidgets('shows version/build and opens the Flutter license page', (
    tester,
  ) async {
    final gateway = _FakeSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(_app(controller));
    await tester.scrollUntilVisible(
      find.byKey(const Key('about-info')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
    expect(find.text('Open source licenses (7)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-licenses')));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.textContaining('1.2.3 (45)'), findsOneWidget);
  });
}
