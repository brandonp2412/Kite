import 'package:flutter/material.dart';

abstract final class SettingsLayout {
  static const double maxContentWidth = 720;
  static const double bottomPadding = 24;

  static EdgeInsets listPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width > maxContentWidth
        ? (width - maxContentWidth) / 2
        : 0.0;
    return EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottomPadding);
  }
}
