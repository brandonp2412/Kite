import 'package:signals/signals.dart';

final class StorageUsageSnapshot {
  const StorageUsageSnapshot({
    required this.mediaCacheBytes,
    required this.presentationCacheBytes,
    required this.diagnosticLogBytes,
  });

  final int mediaCacheBytes;
  final int presentationCacheBytes;
  final int diagnosticLogBytes;

  int get clearableBytes => mediaCacheBytes + presentationCacheBytes;
  int get totalBytes => clearableBytes + diagnosticLogBytes;
}

final class AppAboutInfo {
  const AppAboutInfo({
    required this.version,
    required this.buildNumber,
    required this.licenseCount,
  });

  final String version;
  final String buildNumber;
  final int licenseCount;
}

final class SanitizedDiagnosticBundle {
  const SanitizedDiagnosticBundle({
    required this.generatedAt,
    required this.structuredEventCount,
    required this.crashReportCount,
  });

  final DateTime generatedAt;
  final int structuredEventCount;
  final int crashReportCount;

  @override
  String toString() =>
      'SanitizedDiagnosticBundle('
      'generatedAt: $generatedAt, '
      'structuredEventCount: $structuredEventCount, '
      'crashReportCount: $crashReportCount'
      ')';
}

final class ProblemReportRequest {
  const ProblemReportRequest({
    required this.description,
    required this.diagnostics,
  });

  final String description;
  final SanitizedDiagnosticBundle diagnostics;
}

abstract interface class SupportSettingsGateway {
  Future<StorageUsageSnapshot> loadStorageUsage();

  Future<AppAboutInfo> loadAboutInfo();

  Future<void> clearMediaCache();

  Future<void> clearPresentationCache();

  /// Produces metadata from already-sanitized diagnostics only. Raw logs,
  /// tokens, recovery secrets, and decrypted message contents never cross this
  /// boundary into settings state.
  Future<SanitizedDiagnosticBundle> prepareSanitizedDiagnostics();

  Future<void> submitProblemReport(ProblemReportRequest report);
}

final class SupportSettingsController {
  SupportSettingsController(this._gateway);

  final SupportSettingsGateway _gateway;

  final storage = signal<StorageUsageSnapshot?>(null);
  final about = signal<AppAboutInfo?>(null);
  final isBusy = signal(false);
  final errorMessage = signal<String?>(null);
  final reportSubmitted = signal(false);

  Future<bool> load() async {
    if (isBusy.value) return false;

    isBusy.value = true;
    errorMessage.value = null;
    try {
      final nextStorage = await _gateway.loadStorageUsage();
      final nextAbout = await _gateway.loadAboutInfo();
      if (!_isValidStorage(nextStorage) || !_isValidAbout(nextAbout)) {
        errorMessage.value = 'Kite received invalid support settings data.';
        return false;
      }
      storage.value = nextStorage;
      about.value = nextAbout;
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not load storage and app information.';
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  Future<bool> clearMediaCache() {
    return _clearCache(
      _gateway.clearMediaCache,
      failureMessage: 'Kite could not clear the media cache.',
    );
  }

  Future<bool> clearPresentationCache() {
    return _clearCache(
      _gateway.clearPresentationCache,
      failureMessage: 'Kite could not clear the local presentation cache.',
    );
  }

  Future<bool> clearClearableCaches() async {
    if (isBusy.value) return false;

    isBusy.value = true;
    errorMessage.value = null;
    try {
      await _gateway.clearMediaCache();
      await _gateway.clearPresentationCache();
      final nextStorage = await _gateway.loadStorageUsage();
      if (!_isValidStorage(nextStorage)) {
        errorMessage.value = 'Kite received invalid support settings data.';
        return false;
      }
      storage.value = nextStorage;
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not clear all cached content.';
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  Future<bool> submitProblemReport(String description) async {
    if (isBusy.value) return false;
    final normalized = description.trim();
    if (normalized.isEmpty) {
      errorMessage.value = 'Describe the problem before sending a report.';
      return false;
    }

    isBusy.value = true;
    errorMessage.value = null;
    reportSubmitted.value = false;
    try {
      final diagnostics = await _gateway.prepareSanitizedDiagnostics();
      if (!_isValidDiagnostics(diagnostics)) {
        errorMessage.value = 'Kite received invalid diagnostic metadata.';
        return false;
      }
      await _gateway.submitProblemReport(
        ProblemReportRequest(description: normalized, diagnostics: diagnostics),
      );
      reportSubmitted.value = true;
      return true;
    } catch (_) {
      errorMessage.value = 'Kite could not send the problem report.';
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  Future<bool> _clearCache(
    Future<void> Function() clear, {
    required String failureMessage,
  }) async {
    if (isBusy.value) return false;

    isBusy.value = true;
    errorMessage.value = null;
    try {
      await clear();
      final nextStorage = await _gateway.loadStorageUsage();
      if (!_isValidStorage(nextStorage)) {
        errorMessage.value = 'Kite received invalid support settings data.';
        return false;
      }
      storage.value = nextStorage;
      return true;
    } catch (_) {
      errorMessage.value = failureMessage;
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  bool _isValidStorage(StorageUsageSnapshot value) {
    return value.mediaCacheBytes >= 0 &&
        value.presentationCacheBytes >= 0 &&
        value.diagnosticLogBytes >= 0;
  }

  bool _isValidDiagnostics(SanitizedDiagnosticBundle value) {
    return value.structuredEventCount >= 0 && value.crashReportCount >= 0;
  }

  bool _isValidAbout(AppAboutInfo value) {
    return value.version.trim().isNotEmpty &&
        value.buildNumber.trim().isNotEmpty &&
        value.licenseCount >= 0;
  }

  void dispose() {
    storage.dispose();
    about.dispose();
    isBusy.dispose();
    errorMessage.dispose();
    reportSubmitted.dispose();
  }
}
