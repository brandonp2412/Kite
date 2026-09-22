import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Moves common Kite paint pipelines into startup instead of first interaction.
class KiteShaderWarmUp extends ShaderWarmUp {
  const KiteShaderWarmUp();

  @override
  ui.Size get size => const ui.Size(256, 256);

  @override
  Future<void> warmUpOnCanvas(ui.Canvas canvas) async {
    final fill = ui.Paint()..color = const ui.Color(0xFF6750A4);
    final surface = ui.Paint()..color = const ui.Color(0xFFF7F2FA);
    final stroke = ui.Paint()
      ..color = const ui.Color(0xFF49454F)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 256, 256), surface);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(12, 12, 232, 56),
        const ui.Radius.circular(18),
      ),
      fill,
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(12, 80, 108, 72),
        const ui.Radius.circular(12),
      ),
      stroke,
    );
    canvas.drawCircle(const ui.Offset(184, 116), 32, fill);

    final path = ui.Path()
      ..moveTo(20, 188)
      ..lineTo(64, 164)
      ..lineTo(108, 204)
      ..lineTo(152, 172)
      ..lineTo(236, 220);
    canvas.drawPath(path, stroke);

    const layerRect = ui.Rect.fromLTWH(132, 76, 112, 112);
    canvas.saveLayer(layerRect, ui.Paint()..color = const ui.Color(0xBFFFFFFF));
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(140, 84, 96, 96),
        const ui.Radius.circular(16),
      ),
      fill,
    );
    canvas.drawCircle(const ui.Offset(188, 132), 28, surface);
    canvas.restore();

    final paragraph =
        (ui.ParagraphBuilder(
            ui.ParagraphStyle(fontSize: 22),
          )..addText('Aa 123 ✓ 🔐 🙂')).build()
          ..layout(const ui.ParagraphConstraints(width: 220));
    canvas.drawParagraph(paragraph, const ui.Offset(18, 222));
  }
}
