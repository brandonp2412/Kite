import 'package:flutter/widgets.dart';
import 'package:kite/features/auth/authentication_gateway.dart';

typedef AuthenticatedAccountSignOut = Future<void> Function();

class AuthenticatedAccountScope extends InheritedWidget {
  const AuthenticatedAccountScope({
    required this.session,
    required this.signOut,
    required super.child,
    super.key,
  });

  final AuthenticatedSession session;
  final AuthenticatedAccountSignOut signOut;

  static AuthenticatedAccountScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthenticatedAccountScope>();

  @override
  bool updateShouldNotify(AuthenticatedAccountScope oldWidget) =>
      session.userId != oldWidget.session.userId ||
      session.deviceId != oldWidget.session.deviceId ||
      session.homeserver.uri != oldWidget.session.homeserver.uri ||
      !identical(signOut, oldWidget.signOut);
}
