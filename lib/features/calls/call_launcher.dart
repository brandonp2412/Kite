import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/calls/call_screen.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:signals/signals_flutter.dart';

enum KiteCallLaunchChoice {
  directVoice,
  directVideo,
  groupVoice,
  groupVideo,
  joinGroup,
}

class KiteRoomCallLauncher extends StatelessWidget {
  const KiteRoomCallLauncher({
    required this.coordinator,
    required this.roomId,
    required this.roomName,
    required this.isDirect,
    this.activeGroupCallId,
    this.activeGroupCallKind = KiteCallKind.video,
    super.key,
  });

  final KiteCallCoordinator coordinator;
  final String roomId;
  final String roomName;
  final bool isDirect;
  final String? activeGroupCallId;
  final KiteCallKind activeGroupCallKind;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final activity = coordinator.activity.value;
        final activeInThisRoom =
            activity?.roomId == roomId && activity!.isActive;
        final activeElsewhere = activity?.isActive == true && !activeInThisRoom;
        return IconButton(
          key: const Key('room-call-button'),
          tooltip: activeInThisRoom
              ? 'Return to call'
              : activeElsewhere
              ? 'Another call is active'
              : 'Call',
          onPressed: activeElsewhere
              ? null
              : () => unawaited(
                  activeInThisRoom ? _openCall(context) : _showChoices(context),
                ),
          icon: Icon(
            activeInThisRoom ? Icons.call_rounded : Icons.call_outlined,
          ),
        );
      },
    );
  }

  Future<void> _showChoices(BuildContext context) async {
    final choice = await showGeneralDialog<KiteCallLaunchChoice>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss call options',
      barrierColor: const Color(0x52000000),
      transitionDuration: KiteMotion.instant,
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              color: Theme.of(dialogContext).colorScheme.surface,
              elevation: KiteElevation.flat,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(KiteRadii.lg),
              ),
              child: _CallLaunchSheet(
                isDirect: isDirect,
                hasActiveGroupCall: !isDirect && activeGroupCallId != null,
              ),
            ),
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;

    try {
      switch (choice) {
        case KiteCallLaunchChoice.directVoice:
          await coordinator.startDirectVoiceCall(roomId);
        case KiteCallLaunchChoice.directVideo:
          await coordinator.startDirectVideoCall(roomId);
        case KiteCallLaunchChoice.groupVoice:
          await coordinator.startGroupCall(roomId, kind: KiteCallKind.voice);
        case KiteCallLaunchChoice.groupVideo:
          await coordinator.startGroupCall(roomId);
        case KiteCallLaunchChoice.joinGroup:
          final callId = activeGroupCallId;
          if (callId == null) return;
          await coordinator.joinGroupCall(
            roomId: roomId,
            callId: callId,
            kind: activeGroupCallKind,
          );
      }
      if (context.mounted) {
        await _openCall(context);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Kite could not start that call.')),
        );
    }
  }

  Future<void> _openCall(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (callContext) => KiteCallScreen(
          coordinator: coordinator,
          roomName: roomName,
          onClose: () => Navigator.of(callContext).pop(),
        ),
      ),
    );
  }
}

class _CallLaunchSheet extends StatelessWidget {
  const _CallLaunchSheet({
    required this.isDirect,
    required this.hasActiveGroupCall,
  });

  final bool isDirect;
  final bool hasActiveGroupCall;

  @override
  Widget build(BuildContext context) {
    final options = isDirect
        ? const <_CallLaunchOption>[
            _CallLaunchOption(
              choice: KiteCallLaunchChoice.directVoice,
              key: Key('start-direct-voice-call'),
              icon: Icons.call_outlined,
              title: 'Voice call',
              subtitle: 'Start an encrypted one-to-one audio call',
            ),
            _CallLaunchOption(
              choice: KiteCallLaunchChoice.directVideo,
              key: Key('start-direct-video-call'),
              icon: Icons.videocam_outlined,
              title: 'Video call',
              subtitle: 'Start an encrypted one-to-one video call',
            ),
          ]
        : hasActiveGroupCall
        ? const <_CallLaunchOption>[
            _CallLaunchOption(
              choice: KiteCallLaunchChoice.joinGroup,
              key: Key('join-group-call'),
              icon: Icons.groups_2_outlined,
              title: 'Join call',
              subtitle: 'Join the active MatrixRTC call in this room',
            ),
          ]
        : const <_CallLaunchOption>[
            _CallLaunchOption(
              choice: KiteCallLaunchChoice.groupVoice,
              key: Key('start-group-voice-call'),
              icon: Icons.call_outlined,
              title: 'Voice call',
              subtitle: 'Start a group audio call',
            ),
            _CallLaunchOption(
              choice: KiteCallLaunchChoice.groupVideo,
              key: Key('start-group-video-call'),
              icon: Icons.video_call_outlined,
              title: 'Video call',
              subtitle: 'Start a group video call',
            ),
          ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.lg,
        0,
        KiteSpacing.lg,
        KiteSpacing.lg,
      ),
      child: Column(
        key: const Key('call-launch-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Start a call', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: KiteSpacing.sm),
          for (final option in options)
            ListTile(
              key: option.key,
              contentPadding: EdgeInsets.zero,
              leading: Icon(option.icon),
              title: Text(option.title),
              subtitle: Text(option.subtitle),
              onTap: () => Navigator.of(context).pop(option.choice),
            ),
        ],
      ),
    );
  }
}

final class _CallLaunchOption {
  const _CallLaunchOption({
    required this.choice,
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final KiteCallLaunchChoice choice;
  final Key key;
  final IconData icon;
  final String title;
  final String subtitle;
}
