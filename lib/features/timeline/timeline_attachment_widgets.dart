import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_media_viewer.dart';

const deterministicComposerAttachments = <TimelineAttachment>[
  TimelineAttachment(
    id: 'photo-library',
    kind: TimelineAttachmentKind.image,
    name: 'IMG_2048.jpg',
    sizeLabel: '2.4 MB · Photo',
  ),
  TimelineAttachment(
    id: 'video-library',
    kind: TimelineAttachmentKind.video,
    name: 'VID_1032.mp4',
    sizeLabel: '18.2 MB · Video',
  ),
  TimelineAttachment(
    id: 'camera-photo',
    kind: TimelineAttachmentKind.image,
    name: 'Camera photo.jpg',
    sizeLabel: '3.1 MB · Camera',
  ),
  TimelineAttachment(
    id: 'document-file',
    kind: TimelineAttachmentKind.file,
    name: 'project-notes.pdf',
    sizeLabel: '840 KB · PDF',
  ),
];

Future<TimelineAttachment?> showComposerAttachmentPicker(BuildContext context) {
  return showModalBottomSheet<TimelineAttachment>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.kiteColors.canvas,
    constraints: const BoxConstraints(maxWidth: 440),
    builder: (_) => const ComposerAttachmentPickerSheet(),
  );
}

class ComposerAttachmentPickerSheet extends StatelessWidget {
  const ComposerAttachmentPickerSheet({super.key});

  static const _labels = <String>['Photos', 'Videos', 'Camera', 'Files'];

  static const _icons = <IconData>[
    Icons.photo_library_outlined,
    Icons.video_library_outlined,
    Icons.photo_camera_outlined,
    Icons.attach_file_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('attachment-picker-sheet'),
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.md,
        0,
        KiteSpacing.md,
        KiteSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Add attachment',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: KiteSpacing.sm),
          for (
            var index = 0;
            index < deterministicComposerAttachments.length;
            index++
          )
            ListTile(
              key: Key(
                'attachment-option-${deterministicComposerAttachments[index].id}',
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: KiteSpacing.xs,
              ),
              leading: Icon(_icons[index]),
              title: Text(_labels[index]),
              subtitle: Text(deterministicComposerAttachments[index].name),
              onTap: () =>
                  Navigator.of(context)
                      .pop(deterministicComposerAttachments[index]),
            ),
        ],
      ),
    );
  }
}

class ComposerAttachmentPreview extends StatelessWidget {
  const ComposerAttachmentPreview({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  final TimelineAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('composer-attachment-preview'),
      height: 68,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KiteSpacing.md,
          KiteSpacing.xs,
          KiteSpacing.md,
          0,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(KiteRadii.md),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.72),
              width: KiteStroke.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: KiteSpacing.sm),
              SizedBox.square(
                dimension: 42,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(KiteRadii.sm),
                  ),
                  child: Icon(
                    _attachmentIcon(attachment.kind),
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: KiteSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      attachment.name,
                      key: const Key('composer-attachment-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      attachment.sizeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KiteTypography.metadata.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('composer-attachment-remove'),
                tooltip: 'Remove attachment',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
              const SizedBox(width: KiteSpacing.xxs),
            ],
          ),
        ),
      ),
    );
  }
}

class TimelineAttachmentCard extends StatelessWidget {
  const TimelineAttachmentCard({
    super.key,
    required this.messageId,
    required this.attachment,
    this.heroTag,
    this.onTap,
  });

  final String messageId;
  final TimelineAttachment attachment;
  final Object? heroTag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final imageLike = attachment.kind != TimelineAttachmentKind.file;
    final borderRadius = BorderRadius.circular(KiteRadii.sm);
    final media = TimelineMediaVisual(attachment: attachment);
    final content = imageLike
        ? heroTag == null
              ? media
              : Hero(tag: heroTag!, child: media)
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.sm),
            child: Row(
              children: <Widget>[
                Icon(Icons.insert_drive_file_outlined, color: colors.primary),
                const SizedBox(width: KiteSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KiteTypography.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        attachment.sizeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KiteTypography.metadata.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

    return Semantics(
      button: onTap != null,
      label: imageLike ? '${attachment.name}, open media' : attachment.name,
      child: SizedBox(
        key: Key('message-attachment-$messageId'),
        width: imageLike ? 250 : 230,
        height: imageLike ? 132 : 58,
        child: Material(
          color: colors.surface.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.7),
              width: KiteStroke.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: onTap == null
              ? content
              : InkWell(
                  key: Key('message-attachment-open-$messageId'),
                  onTap: onTap,
                  child: content,
                ),
        ),
      ),
    );
  }
}

IconData _attachmentIcon(TimelineAttachmentKind kind) => switch (kind) {
  TimelineAttachmentKind.image => Icons.image_outlined,
  TimelineAttachmentKind.video => Icons.play_circle_outline_rounded,
  TimelineAttachmentKind.file => Icons.insert_drive_file_outlined,
};
