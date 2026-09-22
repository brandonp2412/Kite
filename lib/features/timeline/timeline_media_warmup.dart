import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/matrix/matrix_models.dart';

List<TimelineAttachment> selectRecentTimelineImageWarmups({
  required MatrixPresentationSnapshot snapshot,
  required String currentUserId,
  int roomLimit = 12,
  int perRoomLimit = 2,
  int totalLimit = 16,
}) {
  assert(roomLimit > 0);
  assert(perRoomLimit > 0);
  assert(totalLimit > 0);

  final seenContentUris = <String>{};
  final perRoom = <List<TimelineAttachment>>[];

  for (final room in snapshot.rooms.take(roomLimit)) {
    final images = <TimelineAttachment>[];
    final events =
        snapshot.timelines[room.roomId] ?? const <MatrixTimelineEvent>[];
    for (final event in events.reversed) {
      final attachment = TimelineMessage.fromMatrixEvent(
        event,
        currentUserId: currentUserId,
      )?.attachment;
      final contentUri = attachment?.contentUri;
      if (attachment?.kind != TimelineAttachmentKind.image ||
          contentUri == null ||
          !seenContentUris.add(contentUri)) {
        continue;
      }
      images.add(attachment!);
      if (images.length == perRoomLimit) break;
    }
    perRoom.add(images);
  }

  final selected = <TimelineAttachment>[];
  for (var rank = 0; rank < perRoomLimit; rank += 1) {
    for (final images in perRoom) {
      if (rank >= images.length) continue;
      selected.add(images[rank]);
      if (selected.length == totalLimit) {
        return List<TimelineAttachment>.unmodifiable(selected);
      }
    }
  }
  return List<TimelineAttachment>.unmodifiable(selected);
}
