import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_location_card.dart';

Future<void> showComposerLocationShareSheet(
  BuildContext context, {
  required String roomId,
  required TimelineLocationKind kind,
  required TimelineLocationShareDelegate controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.kiteColors.canvas,
    constraints: const BoxConstraints(maxWidth: 440),
    builder: (_) => ComposerLocationShareSheet(
      roomId: roomId,
      kind: kind,
      controller: controller,
    ),
  );
}

class ComposerLocationShareSheet extends StatefulWidget {
  const ComposerLocationShareSheet({
    super.key,
    required this.roomId,
    required this.kind,
    required this.controller,
  });

  final String roomId;
  final TimelineLocationKind kind;
  final TimelineLocationShareDelegate controller;

  @override
  State<ComposerLocationShareSheet> createState() =>
      _ComposerLocationShareSheetState();
}

class _ComposerLocationShareSheetState
    extends State<ComposerLocationShareSheet> {
  TimelineLocationPreparation? _preparation;
  bool _loading = true;
  bool _sending = false;

  bool get _live => widget.kind == TimelineLocationKind.liveLocation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _preparation = null;
      });
    }
    final preparation = await widget.controller.prepareLocation(widget.kind);
    if (!mounted) return;
    setState(() {
      _preparation = preparation;
      _loading = false;
    });
  }

  void _share() {
    final location = _preparation?.location;
    if (_sending || location == null) return;
    setState(() => _sending = true);
    widget.controller.sendLocation(widget.roomId, location);
    Navigator.of(context).pop();
  }

  Future<void> _openSettings() async {
    await widget.controller.openLocationSettings();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final permission = _preparation?.permission;
    final ready = !_loading && (_preparation?.isReady ?? false);
    final permanentlyDenied =
        permission == TimelineLocationPermission.permanentlyDenied;

    return SizedBox(
      key: const Key('location-share-sheet'),
      height: 382,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KiteSpacing.lg,
          0,
          KiteSpacing.lg,
          KiteSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _live ? 'Share live location' : 'Share location',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: KiteSpacing.xs),
            Text(
              _live
                  ? 'Share updates from your current location until you stop sharing.'
                  : 'Share your current location as a fixed point in the timeline.',
              style: KiteTypography.body.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: KiteSpacing.md),
            SizedBox(
              key: const Key('location-share-state-slot'),
              height: 166,
              width: double.infinity,
              child: _loading
                  ? _LocationLoadingState(live: _live)
                  : ready
                  ? Center(
                      child: TimelineLocationCard(
                        messageId: 'composer-preview',
                        location: _preparation!.location!,
                      ),
                    )
                  : _LocationPermissionState(
                      permanentlyDenied: permanentlyDenied,
                    ),
            ),
            const Spacer(),
            if (ready)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  key: const Key('location-share-confirm'),
                  onPressed: _sending ? null : _share,
                  icon: Icon(
                    _live
                        ? Icons.my_location_rounded
                        : Icons.location_on_rounded,
                  ),
                  label: Text(_live ? 'Start sharing' : 'Share location'),
                ),
              )
            else
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('location-share-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: KiteSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      key: Key(
                        permanentlyDenied
                            ? 'location-share-open-settings'
                            : 'location-share-retry',
                      ),
                      onPressed: _loading
                          ? null
                          : permanentlyDenied
                          ? _openSettings
                          : _load,
                      child: Text(
                        permanentlyDenied ? 'Open settings' : 'Try again',
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationLoadingState extends StatelessWidget {
  const _LocationLoadingState({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(KiteRadii.md),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.7),
          width: KiteStroke.hairline,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox.square(
              dimension: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: KiteSpacing.sm),
            Text(
              live ? 'Finding your live location…' : 'Finding your location…',
              style: KiteTypography.metadata.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationPermissionState extends StatelessWidget {
  const _LocationPermissionState({required this.permanentlyDenied});

  final bool permanentlyDenied;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: permanentlyDenied
          ? 'Location permission blocked. Open system settings to continue.'
          : 'Location permission required. Try again to allow access.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(KiteRadii.md),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.7),
            width: KiteStroke.hairline,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KiteSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.location_off_outlined,
                  size: 30,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(height: KiteSpacing.sm),
                Text(
                  permanentlyDenied
                      ? 'Location access is blocked'
                      : 'Allow location access',
                  textAlign: TextAlign.center,
                  style: KiteTypography.body.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: KiteSpacing.xxs),
                Text(
                  permanentlyDenied
                      ? 'Enable location permission in system settings to share where you are.'
                      : 'Kite needs location permission only when you choose to share a location.',
                  textAlign: TextAlign.center,
                  style: KiteTypography.metadata.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
