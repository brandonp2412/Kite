import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/settings/support_settings_controller.dart';

final class _FakeSupportSettingsGateway implements SupportSettingsGateway {
  StorageUsageSnapshot storage = const StorageUsageSnapshot(
    mediaCacheBytes: 300,
    presentationCacheBytes: 200,
    diagnosticLogBytes: 100,
  );
  AppAboutInfo about = const AppAboutInfo(
    version: '1.2.3',
    buildNumber: '45',
    licenseCount: 12,
  );
  SanitizedDiagnosticBundle diagnostics = SanitizedDiagnosticBundle(
    generatedAt: DateTime.utc(2026, 9, 15, 2),
    structuredEventCount: 9,
    crashReportCount: 2,
  );
  Object? failure;
  int mediaClearCalls = 0;
  int presentationClearCalls = 0;
  int diagnosticPrepareCalls = 0;
  ProblemReportRequest? submittedReport;

  @override
  Future<void> clearMediaCache() async {
    if (failure case final error?) throw error;
    mediaClearCalls += 1;
    storage = StorageUsageSnapshot(
      mediaCacheBytes: 0,
      presentationCacheBytes: storage.presentationCacheBytes,
      diagnosticLogBytes: storage.diagnosticLogBytes,
    );
  }

  @override
  Future<void> clearPresentationCache() async {
    if (failure case final error?) throw error;
    presentationClearCalls += 1;
    storage = StorageUsageSnapshot(
      mediaCacheBytes: storage.mediaCacheBytes,
      presentationCacheBytes: 0,
      diagnosticLogBytes: storage.diagnosticLogBytes,
    );
  }

  @override
  Future<AppAboutInfo> loadAboutInfo() async {
    if (failure case final error?) throw error;
    return about;
  }

  @override
  Future<StorageUsageSnapshot> loadStorageUsage() async {
    if (failure case final error?) throw error;
    return storage;
  }

  @override
  Future<SanitizedDiagnosticBundle> prepareSanitizedDiagnostics() async {
    if (failure case final error?) throw error;
    diagnosticPrepareCalls += 1;
    return diagnostics;
  }

  @override
  Future<void> submitProblemReport(ProblemReportRequest report) async {
    if (failure case final error?) throw error;
    submittedReport = report;
  }
}

void main() {
  test('loads validated storage and about metadata', () async {
    final gateway = _FakeSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load(), isTrue);
    expect(controller.storage.value?.clearableBytes, 500);
    expect(controller.storage.value?.totalBytes, 600);
    expect(controller.about.value?.version, '1.2.3');
    expect(controller.about.value?.licenseCount, 12);
  });

  test('cache clearing never exposes a diagnostic-log deletion path', () async {
    final gateway = _FakeSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.clearClearableCaches(), isTrue);
    expect(gateway.mediaClearCalls, 1);
    expect(gateway.presentationClearCalls, 1);
    expect(controller.storage.value?.mediaCacheBytes, 0);
    expect(controller.storage.value?.presentationCacheBytes, 0);
    expect(controller.storage.value?.diagnosticLogBytes, 100);
  });

  test('individual cache clears refresh storage usage', () async {
    final gateway = _FakeSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.clearMediaCache(), isTrue);
    expect(controller.storage.value?.mediaCacheBytes, 0);
    expect(controller.storage.value?.diagnosticLogBytes, 100);

    expect(await controller.clearPresentationCache(), isTrue);
    expect(controller.storage.value?.presentationCacheBytes, 0);
    expect(controller.storage.value?.diagnosticLogBytes, 100);
  });

  test('problem reports accept only sanitized diagnostic metadata', () async {
    final gateway = _FakeSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);

    expect(
      await controller.submitProblemReport('  Timeline briefly froze  '),
      isTrue,
    );
    expect(gateway.diagnosticPrepareCalls, 1);
    expect(gateway.submittedReport?.description, 'Timeline briefly froze');
    expect(gateway.submittedReport?.diagnostics.structuredEventCount, 9);
    expect(gateway.submittedReport?.diagnostics.crashReportCount, 2);
    expect(controller.reportSubmitted.value, isTrue);
  });

  test('invalid refreshed storage never replaces the known snapshot', () async {
    final gateway = _FakeSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    final knownStorage = controller.storage.value;

    gateway.storage = const StorageUsageSnapshot(
      mediaCacheBytes: -1,
      presentationCacheBytes: 0,
      diagnosticLogBytes: 100,
    );
    expect(await controller.clearPresentationCache(), isFalse);

    expect(controller.storage.value, same(knownStorage));
    expect(
      controller.errorMessage.value,
      'Kite received invalid support settings data.',
    );
  });

  test('invalid diagnostic metadata is rejected before submission', () async {
    final gateway = _FakeSupportSettingsGateway()
      ..diagnostics = SanitizedDiagnosticBundle(
        generatedAt: DateTime.utc(2026, 9, 15, 2),
        structuredEventCount: -1,
        crashReportCount: 2,
      );
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.submitProblemReport('Timeline froze'), isFalse);
    expect(gateway.submittedReport, isNull);
    expect(
      controller.errorMessage.value,
      'Kite received invalid diagnostic metadata.',
    );
  });

  test('blank reports are rejected before diagnostics are prepared', () async {
    final gateway = _FakeSupportSettingsGateway();
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.submitProblemReport('   '), isFalse);
    expect(gateway.diagnosticPrepareCalls, 0);
    expect(gateway.submittedReport, isNull);
    expect(
      controller.errorMessage.value,
      'Describe the problem before sending a report.',
    );
  });

  test('gateway failures never expose exception contents', () async {
    final gateway = _FakeSupportSettingsGateway()
      ..failure = StateError(
        'access_token=secret decrypted_message=private recovery_key=hidden',
      );
    final controller = SupportSettingsController(gateway);
    addTearDown(controller.dispose);

    expect(await controller.load(), isFalse);
    expect(
      controller.errorMessage.value,
      'Kite could not load storage and app information.',
    );
    expect(controller.errorMessage.value, isNot(contains('secret')));
    expect(controller.errorMessage.value, isNot(contains('private')));
    expect(controller.errorMessage.value, isNot(contains('recovery_key')));
  });
}
