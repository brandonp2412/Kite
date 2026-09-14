import 'package:flutter_test/flutter_test.dart';
import 'package:kite/diagnostics/crash_reporting.dart';
import 'package:kite/diagnostics/structured_logging.dart';

final class SecretBearingError implements Exception {
  @override
  String toString() => 'token=super-secret decrypted message body';
}

void main() {
  test('structured logging covers every required flow with trace IDs', () {
    final sink = MemoryStructuredLogSink();
    final logger = StructuredLogger(
      sink: sink,
      traceIds: SequenceTraceIdGenerator(seed: 40),
    );

    final operations = <DiagnosticFlow, DiagnosticOperation>{
      DiagnosticFlow.sync: DiagnosticOperation.syncCycle,
      DiagnosticFlow.timeline: DiagnosticOperation.timelineUpdate,
      DiagnosticFlow.media: DiagnosticOperation.mediaTransfer,
      DiagnosticFlow.encryption: DiagnosticOperation.encryptionOperation,
      DiagnosticFlow.notification: DiagnosticOperation.notificationDelivery,
      DiagnosticFlow.call: DiagnosticOperation.callSession,
    };

    for (final entry in operations.entries) {
      logger
          .trace(entry.key, entry.value)
          .log(
            LogLevel.info,
            DiagnosticEvent.completed,
            metrics: const <DiagnosticMetric, num>{
              DiagnosticMetric.durationMs: 12,
              DiagnosticMetric.itemCount: 3,
            },
          );
    }

    expect(sink.events, hasLength(DiagnosticFlow.values.length));
    expect(
      sink.events.map((event) => event.flow),
      orderedEquals(DiagnosticFlow.values),
    );
    expect(sink.events.first.traceId.value, 'sync-41');
    expect(sink.events.last.traceId.value, 'call-46');
    expect(
      sink.events.every(
        (event) => event.metrics[DiagnosticMetric.durationMs] == 12,
      ),
      isTrue,
    );
  });

  test(
    'crash reporting never serializes exception text or message contents',
    () async {
      final sink = MemoryCrashReportSink();
      final reporter = SanitizingCrashReporter(sink);
      final error = SecretBearingError();

      await reporter.report(
        error,
        stackTrace: StackTrace.current,
        context: const CrashDiagnosticContext(
          flow: DiagnosticFlow.encryption,
          traceId: TraceId('encryption-9'),
          operation: DiagnosticOperation.encryptionOperation,
          component: CrashComponent.matrixSdk,
          state: CrashState.recovering,
        ),
      );

      expect(sink.reports, hasLength(1));
      final report = sink.reports.single;
      expect(report.errorType, 'SecretBearingError');
      expect(report.flow, DiagnosticFlow.encryption);
      expect(report.traceId.value, 'encryption-9');
      expect(report.operation, DiagnosticOperation.encryptionOperation);
      expect(report.component, CrashComponent.matrixSdk);
      expect(report.state, CrashState.recovering);

      final serializedFields = <Object?>[
        report.errorType,
        report.flow.name,
        report.traceId.value,
        report.operation.name,
        report.component?.name,
        report.state?.name,
      ].join(' ');
      expect(serializedFields, isNot(contains('super-secret')));
      expect(serializedFields, isNot(contains('decrypted message body')));
      expect(serializedFields, isNot(contains(error.toString())));
    },
  );
}
