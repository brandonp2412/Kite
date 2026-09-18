import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('en', 'NZ'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Kite'**
  String get appTitle;

  /// No description provided for @chatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatsTitle;

  /// No description provided for @encryptedConversation.
  ///
  /// In en, this message translates to:
  /// **'Encrypted conversation'**
  String get encryptedConversation;

  /// No description provided for @messageCopied.
  ///
  /// In en, this message translates to:
  /// **'Message copied'**
  String get messageCopied;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get messageDeleted;

  /// No description provided for @editedLabel.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get editedLabel;

  /// No description provided for @sendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get sendingLabel;

  /// No description provided for @sentLabel.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sentLabel;

  /// No description provided for @retrySendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Retry sending'**
  String get retrySendingLabel;

  /// No description provided for @messageFailedRetryLabel.
  ///
  /// In en, this message translates to:
  /// **'Message failed. Retry sending'**
  String get messageFailedRetryLabel;

  /// No description provided for @replyAction.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get replyAction;

  /// No description provided for @jumpToRepliedMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Jump to replied message'**
  String get jumpToRepliedMessageLabel;

  /// No description provided for @copyTextAction.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyTextAction;

  /// No description provided for @editMessageAction.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get editMessageAction;

  /// No description provided for @deleteMessageAction.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessageAction;

  /// No description provided for @deleteMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete message?'**
  String get deleteMessageTitle;

  /// No description provided for @deleteMessageBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the message for everyone in the room. This action cannot be undone.'**
  String get deleteMessageBody;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @addAttachmentTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get addAttachmentTooltip;

  /// No description provided for @editMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Edit message…'**
  String get editMessageHint;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageHint;

  /// No description provided for @saveEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save edit'**
  String get saveEditTooltip;

  /// No description provided for @sendMessageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessageTooltip;

  /// No description provided for @editingMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Editing message'**
  String get editingMessageLabel;

  /// No description provided for @replyingToLabel.
  ///
  /// In en, this message translates to:
  /// **'Replying to {sender}'**
  String replyingToLabel(String sender);

  /// No description provided for @cancelEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel edit'**
  String get cancelEditTooltip;

  /// No description provided for @cancelReplyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get cancelReplyTooltip;

  /// No description provided for @avatarLabel.
  ///
  /// In en, this message translates to:
  /// **'{sender} avatar'**
  String avatarLabel(String sender);

  /// No description provided for @messageCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No messages} =1{1 message} other{{count} messages}}'**
  String messageCount(int count);

  /// Number of rooms shown in a room collection.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No rooms} =1{1 room} other{{count} rooms}}'**
  String roomCount(int count);

  /// Accessibility label for the number of unread replies across a room's threads.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread thread reply} other{{count} unread thread replies}}'**
  String unreadThreadRepliesLabel(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'NZ':
            return AppLocalizationsEnNz();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
