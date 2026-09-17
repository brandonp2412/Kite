import 'package:flutter/material.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/home/room_invites.dart';
import 'package:kite/features/home/room_list_presentation.dart';
import 'package:kite/features/profile/user_profile_screen.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_management.dart' as managed;
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals.dart';

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

final class MatrixTimelineSendPort implements TimelineSendPort {
  const MatrixTimelineSendPort(this._send);

  final MatrixPlainTextSender _send;

  @override
  Future<TimelineSendOutcome> sendText({
    required String roomId,
    required String transactionId,
    required String body,
  }) async {
    try {
      await _send(roomId: roomId, transactionId: transactionId, body: body);
      return TimelineSendOutcome.sent;
    } catch (_) {
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
    this.onTimelineHistoryRequested,
    this.onRoomFavouriteChanged,
    this.onMarkAllRoomsRead,
    this.onRoomInviteResponse,
    this.profileAvatarPicker,
    this.roomCreation,
    this.memberManagement,
    this.roomMembersLoader,
    this.memberModerationEnabled = true,
  });

  final MatrixPresentationCache cache;
  final String currentUserId;
  final TimelineSendPort sendPort;
  final TimelineHistoryRequest? onTimelineHistoryRequested;
  final RoomFavouriteChange? onRoomFavouriteChanged;
  final MarkAllRoomsRead? onMarkAllRoomsRead;
  final MatrixRoomInviteResponse? onRoomInviteResponse;
  final AvatarPicker? profileAvatarPicker;
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
    if (identical(oldWidget.cache, widget.cache) &&
        oldWidget.currentUserId == widget.currentUserId &&
        identical(oldWidget.sendPort, widget.sendPort)) {
      return;
    }
    _binding.dispose();
    _binding = _createBinding();
  }

  MatrixHomePresentationBinding _createBinding() {
    return MatrixHomePresentationBinding(
      cache: widget.cache,
      currentUserId: widget.currentUserId,
      sendPort: widget.sendPort,
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
    return HomeScreen(
      roomListStore: _binding.roomListStore,
      inviteStore: _binding.inviteStore,
      timeline: _binding.controller,
      roomCreation: widget.roomCreation,
      memberManagement: widget.memberManagement,
      onTimelineHistoryRequested: widget.onTimelineHistoryRequested,
      onRoomFavouriteChanged: widget.onRoomFavouriteChanged,
      onMarkAllRoomsRead: widget.onMarkAllRoomsRead,
      profileAvatarPicker: widget.profileAvatarPicker,
      roomMembersLoader: widget.roomMembersLoader,
      memberModerationEnabled: widget.memberModerationEnabled,
    );
  }
}

final class MatrixHomePresentationBinding {
  MatrixHomePresentationBinding({
    required this.cache,
    required String currentUserId,
    required TimelineSendPort sendPort,
    TimelineController? controller,
    Signal<String>? selectedRoom,
    RoomInvitePort? invitePort,
  }) : currentUserId = _normalizeUserId(currentUserId),
       controller =
           controller ??
           TimelineController(
             sendPort: sendPort,
             fixtureProvider: (_) => const [],
           ),
       selectedRoom = selectedRoom ?? selectedRoomId,
       roomListStore = RoomListStateStore(matrixRoomListEntries(cache)),
       inviteStore = RoomInviteStore(
         _matrixRoomInvites(cache),
         port: invitePort ?? const DeterministicRoomInvitePort(),
       ) {
    this.controller.reset(sendPort: sendPort, fixtureProvider: (_) => const []);
    _projectCache();
    _disposeProjection = effect(_projectCache);
  }

  final MatrixPresentationCache cache;
  final String currentUserId;
  final TimelineController controller;
  final Signal<String> selectedRoom;
  final RoomListStateStore roomListStore;
  final RoomInviteStore inviteStore;
  late final void Function() _disposeProjection;

  void _projectCache() {
    final roomIds = cache.roomOrder.value;
    roomListStore.reconcile(matrixRoomListEntries(cache));
    inviteStore.reconcile(_matrixRoomInvites(cache));
    for (final roomId in roomIds) {
      controller.applyMatrixEvents(
        roomId,
        cache.timelineSignal(roomId).value,
        currentUserId: currentUserId,
      );
    }

    if (roomIds.isEmpty || roomIds.contains(selectedRoom.peek())) return;
    selectedRoom.value = roomIds.first;
  }

  void dispose() => _disposeProjection();

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
