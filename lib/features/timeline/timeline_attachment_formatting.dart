import 'package:flutter/widgets.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/l10n/kite_local_formats.dart';

String timelineAttachmentSizeLabel(
  BuildContext context,
  TimelineAttachment attachment,
) {
  final bytes = attachment.sizeBytes;
  if (bytes == null) return attachment.sizeLabel;
  return '${KiteLocalFormats.mediaByteSize(context, bytes)} · ${attachment.sizeLabel}';
}

String timelineAttachmentDurationLabel(
  BuildContext context,
  TimelineAttachment attachment,
) {
  final duration = attachment.duration;
  if (duration != null) {
    return KiteLocalFormats.minuteSecond(context, duration);
  }
  return attachment.durationLabel ??
      timelineAttachmentSizeLabel(context, attachment);
}
