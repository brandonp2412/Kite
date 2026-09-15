import 'package:flutter/foundation.dart';

@immutable
class RoomListEntry {
  const RoomListEntry({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.latestSender,
    required this.timeLabel,
    this.unreadCount = 0,
    this.mentionCount = 0,
    this.isMuted = false,
    this.hasMutedActivity = false,
    this.hasActiveCall = false,
    this.isFavourite = false,
    this.isDirectMessage = false,
  });

  final String id;
  final String name;
  final String subtitle;
  final String latestSender;
  final String timeLabel;
  final int unreadCount;
  final int mentionCount;
  final bool isMuted;
  final bool hasMutedActivity;
  final bool hasActiveCall;
  final bool isFavourite;
  final bool isDirectMessage;
}
