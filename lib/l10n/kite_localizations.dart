import 'package:flutter/widgets.dart';
import 'package:kite/l10n/generated/app_localizations.dart' as generated;

abstract final class AppLocalizations {
  static generated.AppLocalizations of(BuildContext context) {
    return Localizations.of<generated.AppLocalizations>(
          context,
          generated.AppLocalizations,
        ) ??
        generated.lookupAppLocalizations(
          Localizations.maybeLocaleOf(context) ?? const Locale('en'),
        );
  }
}
