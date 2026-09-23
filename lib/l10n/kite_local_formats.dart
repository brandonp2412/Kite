import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

abstract final class KiteLocalFormats {
  static String shortDate(BuildContext context, DateTime value) {
    return MaterialLocalizations.of(context).formatShortDate(value);
  }

  static String mediumDate(BuildContext context, DateTime value) {
    return MaterialLocalizations.of(context).formatMediumDate(value);
  }

  static String shortTime(BuildContext context, DateTime value) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  static String decimal(BuildContext context, num value) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return NumberFormat.decimalPattern(locale).format(value);
  }
}
