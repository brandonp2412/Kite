import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

class TimelineLocationCard extends StatelessWidget {
  const TimelineLocationCard({
    super.key,
    required this.messageId,
    required this.location,
  });

  final String messageId;
  final TimelineLocation location;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLive = location.kind == TimelineLocationKind.liveLocation;
    final statusLabel = switch ((isLive, location.isLiveActive)) {
      (false, _) => 'Location',
      (true, true) => 'Live location',
      (true, false) => 'Live location ended',
    };
    final coordinateLabel =
        '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';

    return Semantics(
      label: '$statusLabel: ${location.label}, $coordinateLabel',
      child: SizedBox(
        key: Key('message-location-$messageId'),
        width: 250,
        height: 138,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(KiteRadii.sm),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.7),
                width: KiteStroke.hairline,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomPaint(
                  key: Key('message-location-map-$messageId'),
                  painter: _DeterministicMapPainter(
                    lineColor: colors.outlineVariant.withValues(alpha: 0.52),
                    accentColor: colors.primary.withValues(alpha: 0.24),
                  ),
                ),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 3),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: SizedBox.square(
                      dimension: 42,
                      child: Icon(
                        isLive && location.isLiveActive
                            ? Icons.my_location_rounded
                            : Icons.location_on_rounded,
                        size: 22,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: KiteSpacing.sm,
                  top: KiteSpacing.sm,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(KiteRadii.pill),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KiteSpacing.sm,
                        vertical: KiteSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            isLive && location.isLiveActive
                                ? Icons.radio_button_checked_rounded
                                : Icons.place_outlined,
                            size: 13,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: KiteSpacing.xxs),
                          Text(
                            statusLabel,
                            key: Key('message-location-status-$messageId'),
                            style: KiteTypography.metadata.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.94),
                    ),
                    child: SizedBox(
                      height: 45,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KiteSpacing.sm,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    location.label,
                                    key: Key(
                                      'message-location-label-$messageId',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: KiteTypography.body.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    coordinateLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: KiteTypography.metadata.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 19),
                          ],
                        ),
                      ),
                    ),
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

class _DeterministicMapPainter extends CustomPainter {
  const _DeterministicMapPainter({
    required this.lineColor,
    required this.accentColor,
  });

  final Color lineColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final accentPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final horizontalGap = size.height / 5;
    for (var index = 1; index < 5; index++) {
      final y = horizontalGap * index;
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 4), linePaint);
    }

    final verticalGap = size.width / 6;
    for (var index = 1; index < 6; index++) {
      final x = verticalGap * index;
      canvas.drawLine(Offset(x, 0), Offset(x - 7, size.height), linePaint);
    }

    final path = Path()
      ..moveTo(-10, size.height * 0.67)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.31,
        size.width * 0.54,
        size.height * 0.87,
        size.width + 12,
        size.height * 0.34,
      );
    canvas.drawPath(path, accentPaint);

    final secondary = Path()
      ..moveTo(size.width * 0.08, -8)
      ..quadraticBezierTo(
        size.width * 0.47,
        size.height * 0.55,
        size.width * 0.92,
        size.height + 8,
      );
    canvas.drawPath(secondary, linePaint);

    final radius = math.min(size.width, size.height) * 0.03;
    canvas.drawCircle(
      Offset(size.width * 0.24, size.height * 0.28),
      radius,
      Paint()..color = lineColor.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _DeterministicMapPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.accentColor != accentColor;
}
