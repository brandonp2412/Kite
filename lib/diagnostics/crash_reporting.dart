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

final class _SanitizedStackTrace implements StackTrace {
  const _SanitizedStackTrace(this._frames);

  final List<String> _frames;

  @override
  String toString() => _frames.join('\n');
}

final RegExp _dartStackFrame = RegExp(
  r'^\s*#(\d+)\s+([^\s(]+)(?:\s+\((package:[^\s?)]+|dart:[^\s?)]+)(?::(\d+))?(?::(\d+))?\))?\s*$',
);

StackTrace? _sanitizeStackTrace(StackTrace? stackTrace) {
  if (stackTrace == null) return null;
  final frames = <String>[];
  for (final line in stackTrace.toString().split('\n')) {
    final match = _dartStackFrame.firstMatch(line);
    if (match != null) {
      final buffer = StringBuffer('#${match.group(1)} ${match.group(2)}');
      final uri = match.group(3);
      if (uri != null) {
        buffer.write(' ($uri');
        final lineNumber = match.group(4);
        final columnNumber = match.group(5);
        if (lineNumber != null) buffer.write(':$lineNumber');
        if (columnNumber != null) buffer.write(':$columnNumber');
        buffer.write(')');
      }
      frames.add(buffer.toString());
      continue;
    }
    if (line.trim() == '<asynchronous suspension>') {
      frames.add('<asynchronous suspension>');
    }
  }
  return _SanitizedStackTrace(List<String>.unmodifiable(frames));
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
        stackTrace: _sanitizeStackTrace(stackTrace),
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
