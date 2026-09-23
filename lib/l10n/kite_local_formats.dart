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

  static String decimal(BuildContext context, num value, {int? decimalDigits}) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatter = NumberFormat.decimalPattern(locale);
    if (decimalDigits != null) {
      formatter.minimumFractionDigits = decimalDigits;
      formatter.maximumFractionDigits = decimalDigits;
    }
    return formatter.format(value);
  }

  static String binaryByteSize(BuildContext context, int bytes) {
    if (bytes < 1024) return '${decimal(context, bytes)} B';
    final kib = bytes / 1024;
    if (kib < 1024) {
      return '${decimal(context, kib, decimalDigits: 1)} KiB';
    }
    final mib = kib / 1024;
    if (mib < 1024) {
      return '${decimal(context, mib, decimalDigits: 1)} MiB';
    }
    return '${decimal(context, mib / 1024, decimalDigits: 1)} GiB';
  }
}
