import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:share_plus/share_plus.dart';

typedef TimelinePlatformShareLauncher = Future<void> Function(String text);

final class PlatformTimelineSharePort implements TimelineSharePort {
  const PlatformTimelineSharePort({this.launcher});

  final TimelinePlatformShareLauncher? launcher;

  @override
  Future<void> shareMessage(TimelineShareRequest request) async {
    final text = shareTextForTimelineRequest(request);
    if (text == null) return;
    await (launcher ?? _share)(text);
  }

  static Future<void> _share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}

String? shareTextForTimelineRequest(TimelineShareRequest request) {
  final body = request.body.trim();
  final attachmentName = request.attachment?.name.trim() ?? '';
  final content = body.isNotEmpty
      ? body
      : attachmentName.isNotEmpty
      ? attachmentName
      : 'Matrix message';
  final roomId = Uri.encodeComponent(request.roomId);
  final eventId = Uri.encodeComponent(request.eventId);
  final permalink = 'https://matrix.to/#/$roomId/$eventId';
  return '$content\n\n$permalink';
}
