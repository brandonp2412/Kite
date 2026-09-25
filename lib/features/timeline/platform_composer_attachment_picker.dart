import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:kite/features/timeline/timeline_attachment_widgets.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

typedef ComposerFileSelector = Future<XFile?> Function(
  ComposerAttachmentSource source,
);
typedef ComposerCameraCapture = Future<XFile?> Function();

final class PlatformComposerAttachmentPicker
    implements ComposerAttachmentPicker {
  const PlatformComposerAttachmentPicker({
    this.selectFile,
    this.captureImage,
    this.cameraAvailable,
  });

  final ComposerFileSelector? selectFile;
  final ComposerCameraCapture? captureImage;
  final bool? cameraAvailable;

  @override
  Set<ComposerAttachmentSource> get supportedSources =>
      <ComposerAttachmentSource>{
        ComposerAttachmentSource.photos,
        ComposerAttachmentSource.videos,
        ComposerAttachmentSource.files,
        if (cameraAvailable ?? _cameraSupportedByPlatform())
          ComposerAttachmentSource.camera,
      };

  @override
  Future<TimelineAttachment?> pick(ComposerAttachmentSource source) async {
    if (!supportedSources.contains(source)) return null;
    final file = source == ComposerAttachmentSource.camera
        ? await (captureImage?.call() ?? _captureImage())
        : await (selectFile?.call(source) ?? _selectFile(source));
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Selected attachment is empty');
    }
    final mimeType = _mimeType(file, source);
    final kind = _kindForMimeType(mimeType, source);

    return TimelineAttachment(
      id: 'kite-local-media-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      name: file.name.trim().isEmpty ? _fallbackName(kind) : file.name.trim(),
      sizeLabel: _kindLabel(kind),
      sizeBytes: bytes.length,
      mimeType: mimeType,
      localBytes: bytes,
    );
  }

  static bool _cameraSupportedByPlatform() =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<XFile?> _captureImage() {
    return ImagePicker().pickImage(source: ImageSource.camera);
  }

  static Future<XFile?> _selectFile(ComposerAttachmentSource source) {
    return switch (source) {
      ComposerAttachmentSource.photos => openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(
            label: 'Images',
            extensions: <String>[
              'jpg',
              'jpeg',
              'png',
              'webp',
              'gif',
              'heic',
              'heif',
            ],
            mimeTypes: <String>['image/*'],
            webWildCards: <String>['image/*'],
          ),
        ],
      ),
      ComposerAttachmentSource.videos => openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(
            label: 'Videos',
            extensions: <String>['mp4', 'mov', 'm4v', 'webm', 'mkv'],
            mimeTypes: <String>['video/*'],
            webWildCards: <String>['video/*'],
          ),
        ],
      ),
      ComposerAttachmentSource.files => openFile(),
      ComposerAttachmentSource.camera => Future<XFile?>.value(),
    };
  }

  static String _mimeType(XFile file, ComposerAttachmentSource source) {
    final provided = file.mimeType?.trim().toLowerCase();
    if (provided != null && provided.isNotEmpty) {
      if ((source == ComposerAttachmentSource.photos ||
              source == ComposerAttachmentSource.camera) &&
          !provided.startsWith('image/')) {
        throw StateError('Selected file is not an image');
      }
      if (source == ComposerAttachmentSource.videos &&
          !provided.startsWith('video/')) {
        throw StateError('Selected file is not a video');
      }
      return provided;
    }

    final name = file.name.toLowerCase();
    final inferred = switch (name) {
      final value when value.endsWith('.jpg') || value.endsWith('.jpeg') =>
        'image/jpeg',
      final value when value.endsWith('.png') => 'image/png',
      final value when value.endsWith('.webp') => 'image/webp',
      final value when value.endsWith('.gif') => 'image/gif',
      final value when value.endsWith('.heic') => 'image/heic',
      final value when value.endsWith('.heif') => 'image/heif',
      final value when value.endsWith('.mp4') => 'video/mp4',
      final value when value.endsWith('.mov') => 'video/quicktime',
      final value when value.endsWith('.m4v') => 'video/x-m4v',
      final value when value.endsWith('.webm') => 'video/webm',
      final value when value.endsWith('.mkv') => 'video/x-matroska',
      final value when value.endsWith('.mp3') => 'audio/mpeg',
      final value when value.endsWith('.m4a') => 'audio/mp4',
      final value when value.endsWith('.ogg') => 'audio/ogg',
      final value when value.endsWith('.wav') => 'audio/wav',
      final value when value.endsWith('.pdf') => 'application/pdf',
      _ => 'application/octet-stream',
    };
    if ((source == ComposerAttachmentSource.photos ||
            source == ComposerAttachmentSource.camera) &&
        !inferred.startsWith('image/')) {
      throw StateError('Selected file is not an image');
    }
    if (source == ComposerAttachmentSource.videos &&
        !inferred.startsWith('video/')) {
      throw StateError('Selected file is not a video');
    }
    return inferred;
  }

  static TimelineAttachmentKind _kindForMimeType(
    String mimeType,
    ComposerAttachmentSource source,
  ) {
    if (source == ComposerAttachmentSource.photos ||
        source == ComposerAttachmentSource.camera ||
        mimeType.startsWith('image/')) {
      return TimelineAttachmentKind.image;
    }
    if (source == ComposerAttachmentSource.videos ||
        mimeType.startsWith('video/')) {
      return TimelineAttachmentKind.video;
    }
    if (mimeType.startsWith('audio/')) return TimelineAttachmentKind.audio;
    return TimelineAttachmentKind.file;
  }

  static String _kindLabel(TimelineAttachmentKind kind) => switch (kind) {
    TimelineAttachmentKind.image => 'Image',
    TimelineAttachmentKind.video => 'Video',
    TimelineAttachmentKind.file => 'File',
    TimelineAttachmentKind.audio => 'Audio',
    TimelineAttachmentKind.voice => 'Voice message',
  };

  static String _fallbackName(TimelineAttachmentKind kind) => switch (kind) {
    TimelineAttachmentKind.image => 'Image',
    TimelineAttachmentKind.video => 'Video',
    TimelineAttachmentKind.file => 'File',
    TimelineAttachmentKind.audio => 'Audio',
    TimelineAttachmentKind.voice => 'Voice message',
  };
}
