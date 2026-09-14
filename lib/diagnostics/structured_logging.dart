enum DiagnosticFlow { sync, timeline, media, encryption, notification, call }

enum DiagnosticOperation {
  syncCycle,
  timelineUpdate,
  mediaTransfer,
  encryptionOperation,
  notificationDelivery,
  callSession,
}

enum DiagnosticEvent { started, completed, retried, stateChanged, failed }

enum DiagnosticMetric { durationMs, itemCount, attempt, queueDepth }

enum LogLevel { debug, info, warning, error }

final class TraceId {
  const TraceId(this.value);

  final String value;

  @override
  String toString() => value;
}

abstract interface class TraceIdGenerator {
  TraceId next(DiagnosticFlow flow);
}

final class SequenceTraceIdGenerator implements TraceIdGenerator {
  SequenceTraceIdGenerator({this.seed = 0});

  final int seed;
  int _counter = 0;

  @override
  TraceId next(DiagnosticFlow flow) {
    _counter += 1;
    return TraceId('${flow.name}-${seed + _counter}');
  }
}

final class StructuredLogEvent {
  const StructuredLogEvent({
    required this.level,
    required this.flow,
    required this.traceId,
    required this.operation,
    required this.event,
    this.metrics = const <DiagnosticMetric, num>{},
  });

  final LogLevel level;
  final DiagnosticFlow flow;
  final TraceId traceId;
  final DiagnosticOperation operation;
  final DiagnosticEvent event;
  final Map<DiagnosticMetric, num> metrics;
}

abstract interface class StructuredLogSink {
  void write(StructuredLogEvent event);
}

final class MemoryStructuredLogSink implements StructuredLogSink {
  final List<StructuredLogEvent> events = <StructuredLogEvent>[];

  @override
  void write(StructuredLogEvent event) => events.add(event);
}

final class StructuredLogger {
  factory StructuredLogger({
    required StructuredLogSink sink,
    TraceIdGenerator? traceIds,
  }) {
    return StructuredLogger._(sink, traceIds ?? SequenceTraceIdGenerator());
  }

  StructuredLogger._(this._sink, this._traceIds);

  final StructuredLogSink _sink;
  final TraceIdGenerator _traceIds;

  TraceLogger trace(DiagnosticFlow flow, DiagnosticOperation operation) {
    return TraceLogger._(
      _sink,
      flow: flow,
      operation: operation,
      traceId: _traceIds.next(flow),
    );
  }
}

final class TraceLogger {
  const TraceLogger._(
    this._sink, {
    required this.flow,
    required this.operation,
    required this.traceId,
  });

  final StructuredLogSink _sink;
  final DiagnosticFlow flow;
  final DiagnosticOperation operation;
  final TraceId traceId;

  void log(
    LogLevel level,
    DiagnosticEvent event, {
    Map<DiagnosticMetric, num> metrics = const <DiagnosticMetric, num>{},
  }) {
    _sink.write(
      StructuredLogEvent(
        level: level,
        flow: flow,
        traceId: traceId,
        operation: operation,
        event: event,
        metrics: Map<DiagnosticMetric, num>.unmodifiable(metrics),
      ),
    );
  }
}
