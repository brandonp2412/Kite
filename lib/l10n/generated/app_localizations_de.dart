// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Kite';

  @override
  String get chatsTitle => 'Chats';

  @override
  String get encryptedConversation => 'Encrypted conversation';

  @override
  String get messageCopied => 'Message copied';

  @override
  String get messageDeleted => 'Message deleted';

  @override
  String get editedLabel => 'edited';

  @override
  String get sendingLabel => 'Sending';

  @override
  String get sentLabel => 'Sent';

  @override
  String get retrySendingLabel => 'Retry sending';

  @override
  String get messageFailedRetryLabel => 'Message failed. Retry sending';

  @override
  String get replyAction => 'Reply';

  @override
  String get copyTextAction => 'Copy text';

  @override
  String get editMessageAction => 'Edit message';

  @override
  String get deleteMessageAction => 'Delete message';

  @override
  String get deleteMessageTitle => 'Delete message?';

  @override
  String get deleteMessageBody =>
      'This removes the message for everyone in the room. This action cannot be undone.';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get deleteAction => 'Delete';

  @override
  String get addAttachmentTooltip => 'Add attachment';

  @override
  String get editMessageHint => 'Edit message…';

  @override
  String get messageHint => 'Nachricht';

  @override
  String get saveEditTooltip => 'Save edit';

  @override
  String get sendMessageTooltip => 'Send message';

  @override
  String get editingMessageLabel => 'Editing message';

  @override
  String replyingToLabel(String sender) {
    return 'Replying to $sender';
  }

  @override
  String get cancelEditTooltip => 'Cancel edit';

  @override
  String get cancelReplyTooltip => 'Cancel reply';

  @override
  String avatarLabel(String sender) {
    return '$sender avatar';
  }

  @override
  String messageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
      zero: 'No messages',
    );
    return '$_temp0';
  }

  @override
  String roomCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Räume',
      one: '1 Raum',
      zero: 'Keine Räume',
    );
    return '$_temp0';
  }

  @override
  String unreadThreadRepliesLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ungelesene Thread-Antworten',
      one: '1 ungelesene Thread-Antwort',
    );
    return '$_temp0';
  }
}
