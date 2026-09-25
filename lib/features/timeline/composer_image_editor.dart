import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

enum ComposerImageCropAspect {
  original,
  square,
  fourThree,
  sixteenNine;

  double? get ratio => switch (this) {
    original => null,
    square => 1,
    fourThree => 4 / 3,
    sixteenNine => 16 / 9,
  };

  String get label => switch (this) {
    original => 'Original',
    square => 'Square',
    fourThree => '4:3',
    sixteenNine => '16:9',
  };
}

typedef ComposerImageProcessor = Future<TimelineAttachment> Function({
  required TimelineAttachment attachment,
  required int quarterTurns,
  required ComposerImageCropAspect cropAspect,
  required Offset focus,
});

Future<TimelineAttachment?> showComposerImageEditor(
  BuildContext context, {
  required TimelineAttachment attachment,
  ComposerImageProcessor processor = processComposerImageEdit,
}) {
  return Navigator.of(context).push<TimelineAttachment>(
    MaterialPageRoute<TimelineAttachment>(
      builder: (_) =>
          ComposerImageEditor(attachment: attachment, processor: processor),
    ),
  );
}

class ComposerImageEditor extends StatefulWidget {
  const ComposerImageEditor({
    super.key,
    required this.attachment,
    this.processor = processComposerImageEdit,
  });

  final TimelineAttachment attachment;
  final ComposerImageProcessor processor;

  @override
  State<ComposerImageEditor> createState() => _ComposerImageEditorState();
}

class _ComposerImageEditorState extends State<ComposerImageEditor> {
  int _quarterTurns = 0;
  ComposerImageCropAspect _cropAspect = ComposerImageCropAspect.original;
  Offset _focus = const Offset(0.5, 0.5);
  bool _applying = false;

  bool get _changed =>
      _quarterTurns % 4 != 0 || _cropAspect != ComposerImageCropAspect.original;

  void _rotate(int delta) {
    setState(() {
      _quarterTurns = (_quarterTurns + delta) % 4;
      if (_quarterTurns < 0) _quarterTurns += 4;
      _focus = const Offset(0.5, 0.5);
    });
  }

  void _setCropAspect(ComposerImageCropAspect cropAspect) {
    if (_cropAspect == cropAspect) return;
    setState(() {
      _cropAspect = cropAspect;
      _focus = const Offset(0.5, 0.5);
    });
  }

  void _moveFocus(Offset delta, Size viewportSize) {
    if (_cropAspect == ComposerImageCropAspect.original ||
        viewportSize.isEmpty) {
      return;
    }
    setState(() {
      _focus = Offset(
        (_focus.dx - delta.dx / viewportSize.width).clamp(0.0, 1.0).toDouble(),
        (_focus.dy - delta.dy / viewportSize.height).clamp(0.0, 1.0).toDouble(),
      );
    });
  }

  Future<void> _apply() async {
    if (_applying) return;
    if (!_changed) {
      Navigator.of(context).pop(widget.attachment);
      return;
    }

    setState(() => _applying = true);
    try {
      final edited = await widget.processor(
        attachment: widget.attachment,
        quarterTurns: _quarterTurns,
        cropAspect: _cropAspect,
        focus: _focus,
      );
      if (!mounted) return;
      Navigator.of(context).pop(edited);
    } catch (_) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not edit this image.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.attachment.localBytes;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('composer-image-editor'),
      backgroundColor: context.kiteColors.canvas,
      appBar: AppBar(
        title: const Text('Edit image'),
        leading: IconButton(
          key: const Key('composer-image-cancel'),
          tooltip: 'Cancel image editing',
          onPressed: _applying ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('composer-image-apply'),
            onPressed: _applying ? null : _apply,
            child: _applying
                ? const SizedBox.square(
                    key: Key('composer-image-processing'),
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Apply'),
          ),
          const SizedBox(width: KiteSpacing.xs),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(KiteSpacing.md),
                child: _ImageCropPreview(
                  bytes: bytes,
                  quarterTurns: _quarterTurns,
                  cropAspect: _cropAspect,
                  focus: _focus,
                  onPanUpdate: _moveFocus,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  top: BorderSide(
                    color: colors.outlineVariant,
                    width: KiteStroke.hairline,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KiteSpacing.md,
                  KiteSpacing.sm,
                  KiteSpacing.md,
                  KiteSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        IconButton.filledTonal(
                          key: const Key('composer-image-rotate-left'),
                          tooltip: 'Rotate left',
                          onPressed: _applying ? null : () => _rotate(-1),
                          icon: const Icon(Icons.rotate_left_rounded),
                        ),
                        const SizedBox(width: KiteSpacing.md),
                        IconButton.filledTonal(
                          key: const Key('composer-image-rotate-right'),
                          tooltip: 'Rotate right',
                          onPressed: _applying ? null : () => _rotate(1),
                          icon: const Icon(Icons.rotate_right_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: KiteSpacing.sm),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: KiteSpacing.xs,
                      runSpacing: KiteSpacing.xs,
                      children: <Widget>[
                        for (final aspect in ComposerImageCropAspect.values)
                          ChoiceChip(
                            key: Key('composer-image-crop-${aspect.name}'),
                            label: Text(aspect.label),
                            selected: _cropAspect == aspect,
                            onSelected: _applying
                                ? null
                                : (_) => _setCropAspect(aspect),
                          ),
                      ],
                    ),
                    const SizedBox(height: KiteSpacing.xs),
                    Visibility(
                      visible: _cropAspect != ComposerImageCropAspect.original,
                      maintainAnimation: true,
                      maintainSize: true,
                      maintainState: true,
                      child: Text(
                        'Drag image to reposition crop',
                        style: KiteTypography.metadata.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCropPreview extends StatelessWidget {
  const _ImageCropPreview({
    required this.bytes,
    required this.quarterTurns,
    required this.cropAspect,
    required this.focus,
    required this.onPanUpdate,
  });

  final Uint8List? bytes;
  final int quarterTurns;
  final ComposerImageCropAspect cropAspect;
  final Offset focus;
  final void Function(Offset delta, Size viewportSize) onPanUpdate;

  @override
  Widget build(BuildContext context) {
    final imageBytes = bytes;
    if (imageBytes == null || imageBytes.isEmpty) {
      return const Center(child: Text('This image cannot be edited.'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = cropAspect.ratio;
        final maxSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (ratio == null) {
          return Center(
            child: RotatedBox(
              quarterTurns: quarterTurns,
              child: Image.memory(
                imageBytes,
                key: const Key('composer-image-preview'),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          );
        }

        final viewportSize = _fittedAspectSize(maxSize, ratio);
        final alignment = Alignment(focus.dx * 2 - 1, focus.dy * 2 - 1);
        return Center(
          child: GestureDetector(
            key: const Key('composer-image-preview'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => onPanUpdate(details.delta, viewportSize),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KiteRadii.sm),
              child: SizedBox(
                width: viewportSize.width,
                height: viewportSize.height,
                child: RotatedBox(
                  quarterTurns: quarterTurns,
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.cover,
                    alignment: alignment,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Size _fittedAspectSize(Size maxSize, double ratio) {
  var width = maxSize.width;
  var height = width / ratio;
  if (height > maxSize.height) {
    height = maxSize.height;
    width = height * ratio;
  }
  return Size(width, height);
}

Future<TimelineAttachment> processComposerImageEdit({
  required TimelineAttachment attachment,
  required int quarterTurns,
  required ComposerImageCropAspect cropAspect,
  required Offset focus,
}) async {
  if (attachment.kind != TimelineAttachmentKind.image) {
    throw ArgumentError.value(
      attachment.kind,
      'attachment',
      'must be an image attachment',
    );
  }
  final bytes = attachment.localBytes;
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Image editing requires local image bytes');
  }

  final turns = quarterTurns % 4;
  final normalizedTurns = turns < 0 ? turns + 4 : turns;
  if (normalizedTurns == 0 && cropAspect == ComposerImageCropAspect.original) {
    return attachment;
  }

  final inputMimeType = attachment.mimeType?.toLowerCase();
  final inputName = attachment.name;
  final cropRatio = cropAspect.ratio;
  final focusX = focus.dx.clamp(0.0, 1.0).toDouble();
  final focusY = focus.dy.clamp(0.0, 1.0).toDouble();

  final processed = await Isolate.run<Map<String, Object>>(() {
    var image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('Image format could not be decoded');
    }
    image = img.bakeOrientation(image);

    if (normalizedTurns != 0) {
      image = img.copyRotate(image, angle: normalizedTurns * 90);
    }

    if (cropRatio != null) {
      final sourceRatio = image.width / image.height;
      final cropWidth = sourceRatio > cropRatio
          ? (image.height * cropRatio).round().clamp(1, image.width)
          : image.width;
      final cropHeight = sourceRatio > cropRatio
          ? image.height
          : (image.width / cropRatio).round().clamp(1, image.height);
      final x = ((image.width - cropWidth) * focusX).round().clamp(
        0,
        image.width - cropWidth,
      );
      final y = ((image.height - cropHeight) * focusY).round().clamp(
        0,
        image.height - cropHeight,
      );
      image = img.copyCrop(
        image,
        x: x,
        y: y,
        width: cropWidth,
        height: cropHeight,
      );
    }

    final preserveJpeg =
        inputMimeType == 'image/jpeg' || inputMimeType == 'image/jpg';
    final outputBytes = Uint8List.fromList(
      preserveJpeg
          ? img.encodeJpg(image, quality: 92)
          : img.encodePng(image, level: 6),
    );
    return <String, Object>{
      'bytes': outputBytes,
      'mimeType': preserveJpeg ? 'image/jpeg' : 'image/png',
      'name': preserveJpeg ? inputName : _withPngExtension(inputName),
    };
  });

  final outputBytes = processed['bytes']! as Uint8List;
  return TimelineAttachment(
    id: attachment.id,
    kind: attachment.kind,
    name: processed['name']! as String,
    sizeLabel: attachment.sizeLabel,
    sizeBytes: outputBytes.length,
    mimeType: processed['mimeType']! as String,
    localBytes: outputBytes,
  );
}

String _withPngExtension(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return '${stem.isEmpty ? 'image' : stem}.png';
}
