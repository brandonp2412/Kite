import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';

abstract final class SettingsLayout {
  static const double maxContentWidth = KiteLayout.readableContentMaxWidth;
  static const double bottomPadding = 24;

  static EdgeInsets listPadding(BuildContext context) {
    final horizontal = KiteLayout.centeredHorizontalInset(context);
    return EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottomPadding);
  }
}
