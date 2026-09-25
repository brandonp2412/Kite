import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

typedef ComposerVoiceMessagePortFactory = ComposerVoiceMessagePort Function();

abstract interface class ComposerVoiceMessagePort {
  Stream<double> get amplitudes;
  Stream<Duration> get playbackPositions;
  Stream<void> get playbackCompleted;
  Future<bool> requestPermission();
  Future<void> startRecording();
  Future<TimelineAttachment?> stopRecording();
  Future<void> cancelRecording();
  Future<void> play(TimelineAttachment attachment);
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

final class PlatformComposerVoiceMessagePort
    implements ComposerVoiceMessagePort {
  PlatformComposerVoiceMessagePort({
    AudioRecorder? recorder,
    AudioPlayer? player,
  }) : _recorder = recorder ?? AudioRecorder(),
       _player = player ?? AudioPlayer();

  final AudioRecorder _recorder;
  final AudioPlayer _player;
  final Stopwatch _recordingClock = Stopwatch();
  final StreamController<double> _amplitudes =
      StreamController<double>.broadcast();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  String? _recordingPath;
  List<double> _waveform = <double>[];

  @override
  Stream<double> get amplitudes => _amplitudes.stream;

  @override
  Stream<Duration> get playbackPositions => _player.onPositionChanged;

  @override
  Stream<void> get playbackCompleted => _player.onPlayerComplete;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> startRecording() async {
    await pause();
    await cancelRecording();
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/kite-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    _recordingPath = path;
    _waveform = <double>[];
    _recordingClock
      ..reset()
      ..start();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 48000,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amplitude) {
          final normalized = _normalizeAmplitude(amplitude.current);
          _waveform.add(normalized);
          if (!_amplitudes.isClosed) _amplitudes.add(normalized);
        });
  }

  @override
  Future<TimelineAttachment?> stopRecording() async {
    final stoppedPath = await _recorder.stop();
    _recordingClock.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final path = stoppedPath ?? _recordingPath;
    _recordingPath = null;
    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } on FileSystemException {
      // Temporary recording cleanup is best effort.
    }
    if (bytes.isEmpty) return null;

    final duration = _recordingClock.elapsed;
    final waveform = _compressWaveform(_waveform);
    return TimelineAttachment(
      id: 'kite-local-voice-${DateTime.now().microsecondsSinceEpoch}',
      kind: TimelineAttachmentKind.voice,
      name: 'Voice message.m4a',
      sizeLabel: 'Voice message',
      sizeBytes: bytes.length,
      duration: duration,
      mimeType: 'audio/mp4',
      localBytes: bytes,
      waveform: waveform,
    );
  }

  @override
  Future<void> cancelRecording() async {
    if (await _recorder.isRecording()) {
      await _recorder.cancel();
    }
    _recordingClock
      ..stop()
      ..reset();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _recordingPath = null;
    _waveform = <double>[];
  }

  @override
  Future<void> play(TimelineAttachment attachment) async {
    final bytes = attachment.localBytes;
    final mimeType = attachment.mimeType;
    if (bytes == null || bytes.isEmpty || mimeType == null) {
      throw StateError('Voice message preview has no local audio payload');
    }
    await _player.play(BytesSource(bytes, mimeType: mimeType));
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() async {
    await cancelRecording();
    await _player.dispose();
    await _recorder.dispose();
    await _amplitudes.close();
  }
}

double _normalizeAmplitude(double db) {
  if (!db.isFinite) return 0;
  return ((db + 60) / 60).clamp(0.0, 1.0);
}

List<double> _compressWaveform(List<double> values, {int maxSamples = 64}) {
  if (values.isEmpty) return const <double>[];
  if (values.length <= maxSamples) return List<double>.unmodifiable(values);
  final result = <double>[];
  for (var bucket = 0; bucket < maxSamples; bucket++) {
    final start = bucket * values.length ~/ maxSamples;
    final end = (bucket + 1) * values.length ~/ maxSamples;
    var peak = 0.0;
    for (var index = start; index < end; index++) {
      if (values[index] > peak) peak = values[index];
    }
    result.add(peak);
  }
  return List<double>.unmodifiable(result);
}
