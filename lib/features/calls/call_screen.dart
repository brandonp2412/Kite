import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:signals/signals_flutter.dart';

class KiteCallScreen extends StatefulWidget {
  const KiteCallScreen({
    required this.coordinator,
    required this.roomName,
    this.onClose,
    super.key,
  });

  final KiteCallCoordinator coordinator;
  final String roomName;
  final VoidCallback? onClose;

  @override
  State<KiteCallScreen> createState() => _KiteCallScreenState();
}

class _KiteCallScreenState extends State<KiteCallScreen> {
  bool _hydrating = false;

  @override
  void initState() {
    super.initState();
    if (widget.coordinator.phase.value == KiteCallPhase.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateActiveCall());
    }
  }

  Future<void> _hydrateActiveCall() async {
    if (_hydrating || widget.coordinator.phase.value != KiteCallPhase.active) {
      return;
    }
    _hydrating = true;
    try {
      await Future.wait<void>(<Future<void>>[
        widget.coordinator.refreshParticipants().then((_) {}),
        widget.coordinator.refreshAudioRoutes().then((_) {}),
        widget.coordinator.refreshPictureInPictureSupport().then((_) {}),
      ]);
    } catch (_) {
      if (mounted) {
        _showFailure('Some call controls are unavailable right now.');
      }
    } finally {
      _hydrating = false;
    }
  }

  Future<void> _accept() async {
    try {
      await widget.coordinator.acceptIncomingCall();
      await _hydrateActiveCall();
    } catch (_) {
      if (mounted) _showFailure('Kite could not answer the call.');
    }
  }

  Future<void> _decline() async {
    try {
      await widget.coordinator.declineIncomingCall();
    } catch (_) {
      if (mounted) _showFailure('Kite could not decline the call.');
    }
  }

  Future<void> _hangUp() async {
    try {
      await widget.coordinator.hangUp();
    } catch (_) {
      if (mounted) _showFailure('Kite could not end the call.');
    }
  }

  Future<void> _toggleMicrophone(bool muted) async {
    try {
      await widget.coordinator.setMicrophoneMuted(muted);
    } catch (_) {
      if (mounted) _showFailure('Microphone state did not change.');
    }
  }

  Future<void> _toggleCamera(bool enabled) async {
    try {
      await widget.coordinator.setCameraEnabled(enabled);
    } catch (_) {
      if (mounted) _showFailure('Camera state did not change.');
    }
  }

  Future<void> _switchCamera() async {
    try {
      await widget.coordinator.switchCamera();
    } catch (_) {
      if (mounted) _showFailure('Kite could not switch cameras.');
    }
  }

  Future<void> _selectAudioRoute(String routeId) async {
    try {
      await widget.coordinator.selectAudioRoute(routeId);
    } catch (_) {
      if (mounted) _showFailure('Kite could not change the audio route.');
    }
  }

  Future<void> _enterPictureInPicture() async {
    try {
      await widget.coordinator.enterPictureInPicture();
    } catch (_) {
      if (mounted) _showFailure('Picture-in-picture is unavailable.');
    }
  }

  void _showFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.kiteColors.canvas,
      body: SafeArea(
        child: SignalBuilder(
          builder: (context) {
            final phase = widget.coordinator.phase.value;
            final session = widget.coordinator.session.value;
            return Column(
              children: <Widget>[
                _CallHeader(
                  roomName: widget.roomName,
                  phase: phase,
                  onClose: widget.onClose,
                ),
                Expanded(
                  child: switch (phase) {
                    KiteCallPhase.ringing => _IncomingCallBody(
                      roomName: widget.roomName,
                      video: session?.kind == KiteCallKind.video,
                      onAccept: _accept,
                      onDecline: _decline,
                    ),
                    KiteCallPhase.connecting => const _CallStatusBody(
                      key: Key('call-connecting'),
                      icon: Icons.call_outlined,
                      title: 'Connecting…',
                      detail: 'Setting up a secure Matrix call',
                    ),
                    KiteCallPhase.reconnecting => const _CallStatusBody(
                      key: Key('call-reconnecting'),
                      icon: Icons.sync_rounded,
                      title: 'Reconnecting…',
                      detail:
                          'Keeping the call open while the network recovers',
                    ),
                    KiteCallPhase.active => _ActiveCallBody(
                      coordinator: widget.coordinator,
                    ),
                    KiteCallPhase.ended => _EndedCallBody(
                      roomName: widget.roomName,
                      reason: session?.endReason,
                      onClose: widget.onClose,
                    ),
                    KiteCallPhase.idle => _EndedCallBody(
                      roomName: widget.roomName,
                      onClose: widget.onClose,
                    ),
                  },
                ),
                if (phase == KiteCallPhase.active)
                  _CallControls(
                    coordinator: widget.coordinator,
                    onMicrophoneChanged: _toggleMicrophone,
                    onCameraChanged: _toggleCamera,
                    onSwitchCamera: _switchCamera,
                    onAudioRouteSelected: _selectAudioRoute,
                    onPictureInPicture: _enterPictureInPicture,
                    onHangUp: _hangUp,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({
    required this.roomName,
    required this.phase,
    required this.onClose,
  });

  final String roomName;
  final KiteCallPhase phase;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('call-header'),
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.sm),
        child: Row(
          children: <Widget>[
            if (onClose != null)
              IconButton(
                key: const Key('call-close'),
                tooltip: 'Close call',
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back_rounded),
              )
            else
              const SizedBox(width: 48),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KiteTypography.title,
                  ),
                  const SizedBox(height: KiteSpacing.xxs),
                  Text(
                    _phaseLabel(phase),
                    key: const Key('call-phase-label'),
                    style: KiteTypography.metadata.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

class _IncomingCallBody extends StatelessWidget {
  const _IncomingCallBody({
    required this.roomName,
    required this.video,
    required this.onAccept,
    required this.onDecline,
  });

  final String roomName;
  final bool video;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(KiteSpacing.xl),
          child: Column(
            key: const Key('incoming-call'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              CircleAvatar(
                key: const Key('incoming-call-avatar'),
                radius: 52,
                child: Text(
                  roomName.characters.first.toUpperCase(),
                  style: KiteTypography.headline.copyWith(fontSize: 32),
                ),
              ),
              const SizedBox(height: KiteSpacing.xl),
              Text(
                roomName,
                textAlign: TextAlign.center,
                style: KiteTypography.headline,
              ),
              const SizedBox(height: KiteSpacing.xs),
              Text(
                video ? 'Incoming video call' : 'Incoming voice call',
                style: KiteTypography.body.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: KiteSpacing.xxl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _RoundCallButton(
                    key: const Key('call-decline'),
                    icon: Icons.call_end_rounded,
                    label: 'Decline',
                    destructive: true,
                    onPressed: () => unawaited(onDecline()),
                  ),
                  const SizedBox(width: KiteSpacing.xxl),
                  _RoundCallButton(
                    key: const Key('call-accept'),
                    icon: video ? Icons.videocam_rounded : Icons.call_rounded,
                    label: 'Accept',
                    selected: true,
                    onPressed: () => unawaited(onAccept()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveCallBody extends StatelessWidget {
  const _ActiveCallBody({required this.coordinator});

  final KiteCallCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final participants = coordinator.participants.value;
        final spotlightId = coordinator.spotlightParticipantId.value;
        final ordered = <KiteCallParticipant>[
          if (spotlightId != null)
            ...participants.where(
              (participant) => participant.participantId == spotlightId,
            ),
          ...participants.where(
            (participant) => participant.participantId != spotlightId,
          ),
        ];
        if (ordered.isEmpty) {
          return const _CallStatusBody(
            key: Key('call-active-empty'),
            icon: Icons.lock_rounded,
            title: 'Call connected',
            detail: 'Waiting for participant media',
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            return GridView.builder(
              key: const Key('call-participant-grid'),
              padding: const EdgeInsets.all(KiteSpacing.md),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: KiteSpacing.sm,
                mainAxisSpacing: KiteSpacing.sm,
                childAspectRatio: columns == 1 ? 1.45 : 1.25,
              ),
              itemCount: ordered.length,
              itemBuilder: (context, index) {
                final participant = ordered[index];
                return _ParticipantTile(
                  participant: participant,
                  spotlighted: participant.participantId == spotlightId,
                  onPressed: participant.isLocal
                      ? null
                      : () => coordinator.spotlightParticipant(
                          participant.participantId == spotlightId
                              ? null
                              : participant.participantId,
                        ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.spotlighted,
    required this.onPressed,
  });

  final KiteCallParticipant participant;
  final bool spotlighted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: onPressed != null,
      selected: spotlighted,
      label:
          '${participant.displayName}, ${participant.isMicrophoneMuted ? 'microphone muted' : 'microphone on'}',
      child: Material(
        key: Key('call-participant-${participant.participantId}'),
        color: participant.isCameraEnabled
            ? colors.surfaceContainerHighest
            : context.kiteColors.field,
        borderRadius: BorderRadius.circular(KiteRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Center(
                child: CircleAvatar(
                  radius: 38,
                  child: Text(
                    participant.displayName.characters.first.toUpperCase(),
                    style: KiteTypography.headline,
                  ),
                ),
              ),
              Positioned(
                left: KiteSpacing.sm,
                right: KiteSpacing.sm,
                bottom: KiteSpacing.sm,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        participant.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KiteTypography.title,
                      ),
                    ),
                    if (participant.isSpeaking)
                      const Padding(
                        padding: EdgeInsets.only(left: KiteSpacing.xs),
                        child: Icon(Icons.graphic_eq_rounded, size: 19),
                      ),
                    if (participant.isMicrophoneMuted)
                      const Padding(
                        padding: EdgeInsets.only(left: KiteSpacing.xs),
                        child: Icon(Icons.mic_off_rounded, size: 18),
                      ),
                  ],
                ),
              ),
              if (spotlighted)
                Positioned(
                  top: KiteSpacing.sm,
                  right: KiteSpacing.sm,
                  child: Icon(
                    Icons.push_pin_rounded,
                    color: colors.primary,
                    semanticLabel: 'Spotlighted',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.coordinator,
    required this.onMicrophoneChanged,
    required this.onCameraChanged,
    required this.onSwitchCamera,
    required this.onAudioRouteSelected,
    required this.onPictureInPicture,
    required this.onHangUp,
  });

  final KiteCallCoordinator coordinator;
  final Future<void> Function(bool muted) onMicrophoneChanged;
  final Future<void> Function(bool enabled) onCameraChanged;
  final Future<void> Function() onSwitchCamera;
  final Future<void> Function(String routeId) onAudioRouteSelected;
  final Future<void> Function() onPictureInPicture;
  final Future<void> Function() onHangUp;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final muted = coordinator.isMicrophoneMuted.value;
        final cameraEnabled = coordinator.isCameraEnabled.value;
        final video = coordinator.isVideo.value;
        final routes = coordinator.audioRoutes.value;
        final selectedRoute = coordinator.selectedAudioRouteId.value;
        final pipSupported = coordinator.isPictureInPictureSupported.value;
        return Container(
          key: const Key('call-controls'),
          height: 104,
          padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.kiteColors.navigation,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor
                    .withValues(alpha: KiteOpacity.divider),
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _RoundCallButton(
                  key: const Key('call-microphone'),
                  icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: muted ? 'Unmute' : 'Mute',
                  selected: muted,
                  onPressed: () => unawaited(onMicrophoneChanged(!muted)),
                ),
                if (video) ...<Widget>[
                  const SizedBox(width: KiteSpacing.sm),
                  _RoundCallButton(
                    key: const Key('call-camera'),
                    icon: cameraEnabled
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    label: cameraEnabled ? 'Camera off' : 'Camera on',
                    selected: !cameraEnabled,
                    onPressed: () => unawaited(onCameraChanged(!cameraEnabled)),
                  ),
                  const SizedBox(width: KiteSpacing.sm),
                  _RoundCallButton(
                    key: const Key('call-switch-camera'),
                    icon: Icons.cameraswitch_rounded,
                    label: 'Flip',
                    onPressed: cameraEnabled
                        ? () => unawaited(onSwitchCamera())
                        : null,
                  ),
                ],
                if (routes.isNotEmpty) ...<Widget>[
                  const SizedBox(width: KiteSpacing.sm),
                  PopupMenuButton<String>(
                    key: const Key('call-audio-route'),
                    tooltip: 'Audio route',
                    initialValue: selectedRoute,
                    onSelected: (routeId) =>
                        unawaited(onAudioRouteSelected(routeId)),
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      for (final route in routes)
                        PopupMenuItem<String>(
                          value: route.id,
                          child: Text(route.label),
                        ),
                    ],
                    child: const _CallMenuButton(
                      icon: Icons.volume_up_rounded,
                      label: 'Audio',
                    ),
                  ),
                ],
                if (pipSupported) ...<Widget>[
                  const SizedBox(width: KiteSpacing.sm),
                  _RoundCallButton(
                    key: const Key('call-pip'),
                    icon: Icons.picture_in_picture_alt_rounded,
                    label: 'PiP',
                    onPressed: () => unawaited(onPictureInPicture()),
                  ),
                ],
                const SizedBox(width: KiteSpacing.sm),
                _RoundCallButton(
                  key: const Key('call-hang-up'),
                  icon: Icons.call_end_rounded,
                  label: 'End',
                  destructive: true,
                  onPressed: () => unawaited(onHangUp()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = destructive
        ? colors.error
        : selected
        ? colors.primary
        : colors.surfaceContainerHighest;
    final foreground = destructive
        ? colors.onError
        : selected
        ? colors.onPrimary
        : colors.onSurface;
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton.filled(
              onPressed: onPressed,
              style: IconButton.styleFrom(
                fixedSize: const Size.square(52),
                backgroundColor: background,
                foregroundColor: foreground,
                disabledBackgroundColor: background.withValues(
                  alpha: KiteOpacity.disabled,
                ),
              ),
              icon: Icon(icon),
            ),
            const SizedBox(height: KiteSpacing.xxs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KiteTypography.metadata,
            ),
          ],
        ),
      ),
    );
  }
}

class _CallMenuButton extends StatelessWidget {
  const _CallMenuButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: 52, child: Icon(icon)),
          ),
          const SizedBox(height: KiteSpacing.xxs),
          Text(label, style: KiteTypography.metadata),
        ],
      ),
    );
  }
}

class _CallStatusBody extends StatelessWidget {
  const _CallStatusBody({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 52),
          const SizedBox(height: KiteSpacing.lg),
          Text(title, style: KiteTypography.headline),
          const SizedBox(height: KiteSpacing.xs),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: KiteTypography.body.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EndedCallBody extends StatelessWidget {
  const _EndedCallBody({
    required this.roomName,
    required this.onClose,
    this.reason,
  });

  final String roomName;
  final KiteCallEndReason? reason;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final label = switch (reason) {
      KiteCallEndReason.declined => 'Call declined',
      KiteCallEndReason.hungUp => 'Call ended',
      null => 'No active call',
    };
    return Center(
      child: Column(
        key: const Key('call-ended'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.call_end_rounded, size: 48),
          const SizedBox(height: KiteSpacing.md),
          Text(label, style: KiteTypography.headline),
          const SizedBox(height: KiteSpacing.xs),
          Text(roomName, style: KiteTypography.body),
          if (onClose != null) ...<Widget>[
            const SizedBox(height: KiteSpacing.xl),
            FilledButton(onPressed: onClose, child: const Text('Back to room')),
          ],
        ],
      ),
    );
  }
}

String _phaseLabel(KiteCallPhase phase) => switch (phase) {
  KiteCallPhase.idle => 'Call',
  KiteCallPhase.ringing => 'Ringing',
  KiteCallPhase.connecting => 'Connecting',
  KiteCallPhase.active => 'Secure call',
  KiteCallPhase.reconnecting => 'Reconnecting',
  KiteCallPhase.ended => 'Ended',
};
