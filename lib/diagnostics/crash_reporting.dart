import 'package:kite/diagnostics/structured_logging.dart';

enum CrashComponent {
  matrixSdk,
  presentationCache,
  media,
  notifications,
  calls,
}

enum CrashState { starting, active, retrying, backgrounded, recovering }

final class CrashDiagnosticContext {
  const CrashDiagnosticContext({
    required this.flow,
    required this.traceId,
    required this.operation,
    this.component,
    this.state,
  });

  final DiagnosticFlow flow;
  final TraceId traceId;
  final DiagnosticOperation operation;
  final CrashComponent? component;
  final CrashState? state;
}

final class SanitizedCrashReport {
  const SanitizedCrashReport({
    required this.errorType,
    required this.flow,
    required this.traceId,
    required this.operation,
    required this.stackTrace,
    this.component,
    this.state,
  });

  final String errorType;
  final DiagnosticFlow flow;
  final TraceId traceId;
  final DiagnosticOperation operation;
  final CrashComponent? component;
  final CrashState? state;
  final StackTrace? stackTrace;
}

abstract interface class CrashReportSink {
  Future<void> send(SanitizedCrashReport report);
}

abstract interface class CrashReporter {
  Future<void> report(
    Object error, {
    StackTrace? stackTrace,
    required CrashDiagnosticContext context,
  });
}

final class SanitizingCrashReporter implements CrashReporter {
  const SanitizingCrashReporter(this._sink);

  final CrashReportSink _sink;

  @override
  Future<void> report(
    Object error, {
    StackTrace? stackTrace,
    required CrashDiagnosticContext context,
  }) {
    return _sink.send(
      SanitizedCrashReport(
        errorType: error.runtimeType.toString(),
        flow: context.flow,
        traceId: context.traceId,
        operation: context.operation,
        component: context.component,
        state: context.state,
        stackTrace: stackTrace,
      ),
    );
  }
}

final class MemoryCrashReportSink implements CrashReportSink {
  final List<SanitizedCrashReport> reports = <SanitizedCrashReport>[];

  @override
  Future<void> send(SanitizedCrashReport report) async {
    reports.add(report);
  }
}
