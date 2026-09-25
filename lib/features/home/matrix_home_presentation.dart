import 'package:flutter/material.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_invites.dart';
import 'package:kite/features/home/spaces_controller.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/profile/user_profile_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_management.dart' as managed;
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_link_preview.dart';
import 'package:kite/features/timeline/timeline_media_viewer.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals_flutter.dart';

typedef MatrixRoomInviteResponse = Future<void> Function(
  String roomId,
  bool accept,
);

final class MatrixRoomInvitePort implements RoomInvitePort {
  const MatrixRoomInvitePort(this._respond);

  final MatrixRoomInviteResponse _respond;

  @override
  Future<void> accept(String inviteId) => _respond(inviteId, true);

  @override
  Future<void> decline(String inviteId) => _respond(inviteId, false);
}

typedef MatrixPlainTextSender = Future<void> Function({
  required String roomId,
  required String transactionId,
  required String body,
});
typedef MatrixReplyTextSender = Future<void> Function({
  required String roomId,
  required String transactionId,
  required String body,
  required String replyToEventId,
});
typedef MatrixTextEditor = Future<void> Function({
  required String roomId,
  required String transactionId,
  required String eventId,
  required String body,
});

typedef MatrixEventRedactor = Future<void> Function({
  required String roomId,
  required String transactionId,
  required String eventId,
});

typedef MatrixEventReporter = Future<void> Function({
  required String roomId,
  required String eventId,
  required String reason,
});

final class MatrixTimelineModerationPort implements TimelineModerationPort {
  const MatrixTimelineModerationPort(this._report);

  final MatrixEventReporter _report;

  @override
  Future<void> reportMessage(TimelineReportRequest request) {
    return _report(
      roomId: request.roomId,
      eventId: request.eventId,
      reason: request.reason,
    );
  }
}

final class MatrixTimelineEditPort implements TimelineEditPort {
  const MatrixTimelineEditPort(this._edit);

  final MatrixTextEditor _edit;

  @override
  Future<TimelineSendOutcome> editText({
    required String roomId,
    required String transactionId,
    required String eventId,
    required String body,
  }) async {
    try {
      await _edit(
        roomId: roomId,
        transactionId: transactionId,
        eventId: eventId,
        body: body,
      );
      return TimelineSendOutcome.sent;
    } catch (_) {
      return TimelineSendOutcome.failed;
    }
  }
}

final class MatrixTimelineRedactionPort implements TimelineRedactionPort {
  const MatrixTimelineRedactionPort(this._redact);

  final MatrixEventRedactor _redact;

  @override
  Future<TimelineSendOutcome> redactEvent({
    required String roomId,
    required String transactionId,
    required String eventId,
  }) async {
    try {
      await _redact(
        roomId: roomId,
        transactionId: transactionId,
        eventId: eventId,
      );
      return TimelineSendOutcome.sent;
    } catch (_) {
      return TimelineSendOutcome.failed;
    }
  }
}

final class MatrixTimelineSendPort implements TimelineSendPort {
  const MatrixTimelineSendPort(this._send, {this.sendReply});

  final MatrixPlainTextSender _send;
  final MatrixReplyTextSender? sendReply;

  @override
  Future<TimelineSendOutcome> sendText({
    required String roomId,
    required String transactionId,
    required String body,
    String? replyToEventId,
  }) async {
    try {
      final replySender = sendReply;
      if (replyToEventId != null && replySender != null) {
        await replySender(
          roomId: roomId,
          transactionId: transactionId,
          body: body,
          replyToEventId: replyToEventId,
        );
      } else {
        await _send(roomId: roomId, transactionId: transactionId, body: body);
      }
      return TimelineSendOutcome.sent;
    } catch (error) {
      debugPrint('Matrix timeline send failed: $error');
      return TimelineSendOutcome.failed;
    }
  }
}

final class MatrixHomeScreen extends StatefulWidget {
  const MatrixHomeScreen({
    super.key,
    required this.cache,
    required this.currentUserId,
    required this.sendPort,
    this.editPort,
    this.redactionPort,
    this.linkOpenPort,
    this.sharePort,
    this.moderationPort,
    this.onTimelineHistoryRequested,
    this.onRoomFavouriteChanged,
    this.onMarkRoomRead,
    this.onMarkAllRoomsRead,
    this.onRoomInviteResponse,
    this.profileAvatarPicker,
    this.profileAvatarImageProvider,
    this.timelineMediaImageProvider,
    this.roomCreation,
    this.memberManagement,
    this.roomMembersLoader,
    this.memberModerationEnabled = true,
  });

  final MatrixPresentationCache cache;
  final String currentUserId;
  final TimelineSendPort sendPort;
  final TimelineEditPort? editPort;
  final TimelineRedactionPort? redactionPort;
  final TimelineLinkOpenPort? linkOpenPort;
  final TimelineSharePort? sharePort;
  final TimelineModerationPort? moderationPort;
  final TimelineHistoryRequest? onTimelineHistoryRequested;
  final RoomFavouriteChange? onRoomFavouriteChanged;
  final MarkRoomRead? onMarkRoomRead;
  final MarkAllRoomsRead? onMarkAllRoomsRead;
  final MatrixRoomInviteResponse? onRoomInviteResponse;
  final AvatarPicker? profileAvatarPicker;
  final AvatarImageProvider? profileAvatarImageProvider;
  final TimelineMediaImageProvider? timelineMediaImageProvider;
  final RoomManagementCoordinator? roomCreation;
  final managed.RoomMemberManagementCoordinator? memberManagement;
  final RoomMembersLoader? roomMembersLoader;
  final bool memberModerationEnabled;

  @override
  State<MatrixHomeScreen> createState() => _MatrixHomeScreenState();
}

final class _MatrixHomeScreenState extends State<MatrixHomeScreen> {
  late MatrixHomePresentationBinding _binding;

  @override
  void initState() {
    super.initState();
    _binding = _createBinding();
  }

  @override
  void didUpdateWidget(MatrixHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cache, widget.cache) ||
        oldWidget.currentUserId != widget.currentUserId ||
        !identical(oldWidget.linkOpenPort, widget.linkOpenPort)) {
      _binding.dispose();
      _binding = _createBinding();
      return;
    }
    if (!identical(oldWidget.sendPort, widget.sendPort) ||
        !identical(oldWidget.editPort, widget.editPort) ||
        !identical(oldWidget.redactionPort, widget.redactionPort) ||
        !identical(oldWidget.linkOpenPort, widget.linkOpenPort) ||
        !identical(oldWidget.sharePort, widget.sharePort) ||
        !identical(oldWidget.moderationPort, widget.moderationPort)) {
      _binding.updateTransport(
        sendPort: widget.sendPort,
        editPort: widget.editPort,
        redactionPort: widget.redactionPort,
        linkOpenPort: widget.linkOpenPort,
        sharePort: widget.sharePort,
        moderationPort: widget.moderationPort,
      );
    }
  }

  MatrixHomePresentationBinding _createBinding() {
    return MatrixHomePresentationBinding(
      cache: widget.cache,
      currentUserId: widget.currentUserId,
      sendPort: widget.sendPort,
      editPort: widget.editPort,
      linkOpenPort: widget.linkOpenPort,
      sharePort: widget.sharePort,
      moderationPort: widget.moderationPort,
      invitePort: widget.onRoomInviteResponse == null
          ? null
          : MatrixRoomInvitePort(widget.onRoomInviteResponse!),
    );
  }

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) => HomeScreen(
        roomListStore: _binding.roomListStore,
        roomListLoading: !widget.cache.hasReceivedSyncBatch.value,
        timelineReloading: !widget.cache.hasReceivedSyncBatch.value,
        inviteStore: _binding.inviteStore,
        spacesController: _binding.spacesController,
        timeline: _binding.controller,
        roomCreation: widget.roomCreation,
        memberManagement: widget.memberManagement,
        onTimelineHistoryRequested: widget.onTimelineHistoryRequested,
        onRoomFavouriteChanged: widget.onRoomFavouriteChanged,
        onMarkRoomRead: widget.onMarkRoomRead,
        onMarkAllRoomsRead: widget.onMarkAllRoomsRead,
        profileAvatarPicker: widget.profileAvatarPicker,
        profileAvatarImageProvider: widget.profileAvatarImageProvider,
        profileAvatarFallbackUri: _cachedOwnAvatarUri(
          widget.cache,
          widget.currentUserId,
        ),
        recentPeople: _cachedRecentPeople(widget.cache, widget.currentUserId),
        timelineMediaImageProvider: widget.timelineMediaImageProvider,
        roomMembersLoader: widget.roomMembersLoader,
        memberModerationEnabled: widget.memberModerationEnabled,
      ),
    );
  }
}

Uri? _cachedOwnAvatarUri(MatrixPresentationCache cache, String currentUserId) {
  final normalizedUserId = currentUserId.trim();
  if (normalizedUserId.isEmpty) return null;

  final snapshot = cache.snapshot(roomLimit: 32, timelineEventLimitPerRoom: 8);
  DateTime? newestTimestamp;
  Uri? newestAvatar;
  for (final events in snapshot.timelines.values) {
    for (final event in events) {
      if (event.senderId != normalizedUserId) continue;
      final rawAvatar = event.senderAvatarUrl?.trim();
      if (rawAvatar == null || rawAvatar.isEmpty) continue;
      final avatarUri = Uri.tryParse(rawAvatar);
      if (avatarUri == null || avatarUri.scheme != 'mxc') continue;
      if (newestTimestamp == null ||
          event.originServerTimestamp.isAfter(newestTimestamp)) {
        newestTimestamp = event.originServerTimestamp;
        newestAvatar = avatarUri;
      }
    }
  }
  return newestAvatar;
}

List<KiteUserSearchResult> _cachedRecentPeople(
  MatrixPresentationCache cache,
  String currentUserId,
) {
  final snapshot = cache.snapshot(roomLimit: 24, timelineEventLimitPerRoom: 8);
  final seen = <String>{currentUserId.trim()};
  final people = <KiteUserSearchResult>[];
  for (final events in snapshot.timelines.values) {
    for (final event in events.reversed) {
      final id = event.senderId.trim();
      if (!id.startsWith('@') || !seen.add(id)) continue;
      final avatar = Uri.tryParse(event.senderAvatarUrl ?? '');
      people.add(
        KiteUserSearchResult(
          userId: id,
          displayName: event.senderDisplayName,
          avatarUrl: avatar?.scheme == 'mxc' ? avatar : null,
        ),
      );
      if (people.length == 24) return List.unmodifiable(people);
    }
  }
  return List.unmodifiable(people);
}

final class MatrixHomePresentationBinding {
  MatrixHomePresentationBinding({
    required this.cache,
    required String currentUserId,
    required TimelineSendPort sendPort,
    TimelineEditPort? editPort,
    TimelineRedactionPort? redactionPort,
    TimelineLinkOpenPort? linkOpenPort,
    TimelineSharePort? sharePort,
    TimelineModerationPort? moderationPort,
    TimelineController? controller,
    Signal<String>? selectedRoom,
    RoomInvitePort? invitePort,
  }) : currentUserId = _normalizeUserId(currentUserId),
       controller =
           controller ??
           TimelineController(
             sendPort: sendPort,
             editPort: editPort,
             redactionPort: redactionPort,
             linkOpenPort: linkOpenPort,
             sharePort: sharePort,
             moderationPort: moderationPort,
             fixtureProvider: (_) => const [],
           ),
       selectedRoom = selectedRoom ?? selectedRoomId,
       roomListStore = RoomListStateStore(matrixRoomListEntries(cache)),
       spacesController = SpacesController(spaces: _matrixSpaces(cache)),
       inviteStore = RoomInviteStore(
         _matrixRoomInvites(cache),
         port: invitePort ?? const DeterministicRoomInvitePort(),
       ) {
    this.controller.reset(
      sendPort: sendPort,
      editPort: editPort,
      redactionPort: redactionPort,
      linkOpenPort: linkOpenPort,
      sharePort: sharePort,
      moderationPort: moderationPort,
      fixtureProvider: (_) => const [],
    );
    _projectCache();
    _projectRecentTimelines();
    _projectSelectedTimeline();
    _disposeCacheProjection = effect(_projectCache);
    _disposeRecentTimelineProjection = effect(_projectRecentTimelines);
    _disposeTimelineProjection = effect(_projectSelectedTimeline);
  }

  final MatrixPresentationCache cache;
  final String currentUserId;
  final TimelineController controller;
  final Signal<String> selectedRoom;
  final RoomListStateStore roomListStore;
  final SpacesController spacesController;
  final RoomInviteStore inviteStore;
  static const int _eagerRecentRoomLimit = 8;

  late final void Function() _disposeCacheProjection;
  late final void Function() _disposeRecentTimelineProjection;
  late final void Function() _disposeTimelineProjection;

  void _projectCache() {
    final spaces = _matrixSpaces(cache);
    batch(() {
      roomListStore.reconcile(matrixRoomListEntries(cache));
      spacesController.reconcileSpaces(spaces);
      final selectedSpaceId = roomListStore.selectedSpaceId.peek();
      if (selectedSpaceId != null &&
          !spaces.any((space) => space.id == selectedSpaceId)) {
        roomListStore.selectSpace(null);
      }
      inviteStore.reconcile(_matrixRoomInvites(cache));
    });

    final roomIds = roomListStore.roomIds;
    if (roomIds.isEmpty || roomIds.contains(selectedRoom.peek())) return;
    selectedRoom.value = roomIds.first;
  }

  void _projectRecentTimelines() {
    final roomIds = cache.roomOrder.value
        .where(
          (roomId) => cache.roomSummarySignal(roomId).value?.isSpace != true,
        )
        .take(_eagerRecentRoomLimit);
    for (final roomId in roomIds) {
      final events = cache.timelineSignal(roomId).value;
      untracked(() {
        controller.applyMatrixEvents(
          roomId,
          events,
          currentUserId: currentUserId,
        );
      });
    }
  }

  void _projectSelectedTimeline() {
    final roomIds = cache.roomOrder.value
        .where(
          (roomId) => cache.roomSummarySignal(roomId).value?.isSpace != true,
        )
        .toList(growable: false);
    if (roomIds.isEmpty) return;
    final roomId = selectedRoom.value;
    if (!roomIds.contains(roomId)) return;
    final events = cache.timelineSignal(roomId).value;
    final summary = cache.roomSummarySignal(roomId).value;
    final typingUsers = cache.typingUsersSignal(roomId).value;
    final readReceipts = cache.readReceiptsSignal(roomId).value;
    untracked(() {
      controller.applyMatrixEvents(
        roomId,
        events,
        currentUserId: currentUserId,
      );
      controller.applyFullyReadMarker(
        roomId,
        summary?.fullyReadEventId,
        unreadMessageCount: summary?.unreadMessageCount ?? 0,
        timelineEvents: events,
      );
      controller.updateTypingUsers(roomId, typingUsers);
      controller.applyReadReceipts(roomId, readReceipts);
    });
  }

  void updateTransport({
    required TimelineSendPort sendPort,
    TimelineEditPort? editPort,
    TimelineRedactionPort? redactionPort,
    TimelineLinkOpenPort? linkOpenPort,
    TimelineSharePort? sharePort,
    TimelineModerationPort? moderationPort,
  }) {
    controller.updateTransport(
      sendPort: sendPort,
      editPort: editPort,
      redactionPort: redactionPort,
      linkOpenPort: linkOpenPort,
      sharePort: sharePort,
      moderationPort: moderationPort,
    );
  }

  void dispose() {
    _disposeCacheProjection();
    _disposeRecentTimelineProjection();
    _disposeTimelineProjection();
  }

  static List<SpaceSummary> _matrixSpaces(MatrixPresentationCache cache) {
    return List<SpaceSummary>.unmodifiable(<SpaceSummary>[
      for (final roomId in cache.roomOrder.value)
        if (cache.roomSummarySignal(roomId).value case final summary?)
          if (summary.isSpace)
            SpaceSummary(
              id: summary.roomId,
              name: summary.displayName,
              description: summary.topic?.trim().isNotEmpty == true
                  ? summary.topic!.trim()
                  : 'Joined Matrix Space',
              memberCount: summary.memberCount,
              childSpaceIds: <String>[
                for (final childRoomId in summary.childRoomIds)
                  if (cache.roomSummarySignal(childRoomId).value
                      case final childSummary?)
                    if (childSummary.isSpace) childSummary.roomId,
              ],
              rooms: <SpaceRoomPreview>[
                for (final childRoomId in summary.childRoomIds)
                  if (cache.roomSummarySignal(childRoomId).value
                      case final childSummary?)
                    if (!childSummary.isSpace)
                      SpaceRoomPreview(
                        id: childSummary.roomId,
                        name: childSummary.displayName,
                        topic: childSummary.topic?.trim() ?? '',
                        memberCount: childSummary.memberCount,
                        joined: true,
                      ),
              ],
            ),
    ]);
  }

  static List<RoomInvite> _matrixRoomInvites(MatrixPresentationCache cache) {
    return List<RoomInvite>.unmodifiable(
      cache.invites.value.map(
        (invite) => RoomInvite(
          id: invite.roomId,
          roomName: invite.roomName,
          inviterName: invite.inviterDisplayName,
          memberCount: invite.memberCount,
          description: invite.description,
        ),
      ),
    );
  }

  static String _normalizeUserId(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty || normalized.contains('\u0000')) {
      throw ArgumentError.value(
        userId,
        'currentUserId',
        'must be a non-empty Matrix user id without NUL bytes',
      );
    }
    return normalized;
  }
}
