import 'package:flutter/material.dart';

abstract final class KiteLocaleFormat {
  static String date(BuildContext context, DateTime value) {
    return MaterialLocalizations.of(context).formatMediumDate(value);
  }

  static String time(BuildContext context, DateTime value) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  static String integer(BuildContext context, int value) {
    return MaterialLocalizations.of(context).formatDecimal(value);
  }
}
