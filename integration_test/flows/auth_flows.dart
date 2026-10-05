// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:material_ui/material_ui.dart';

import '../data/environment_constants.dart';
import '../utils/kite_tester.dart';

Future<void> finalLogout(WidgetTester widgetTester) =>
    widgetTester.startKiteTest().then((tester) => tester.logout());

extension AuthFlows on KiteTester {
  Future<void> initCryptoIdentity({String username = user1Name}) async {
    final passphrase = userPassphrases[username];
    if (passphrase != null) {
      await waitFor('Restore Crypto Identity');
      await enterText(TextField, passphrase);
      await tapOn('Unlock');
    } else {
      await waitFor('Set Up Crypto Identity');
      await enterText(TextField, passphrase1, index: 0);
      await enterText(TextField, passphrase1, index: 1);
      await tapOn('Continue');
      await tapOn('Continue');
      userPassphrases[username] = passphrase1;
    }
  }

  Future<void> login({
    String username = user1Name,
    String password = user1Pw,
  }) async {
    await waitFor('Sign in');
    await tapOn('Sign in', pumpAndSettle: false);
    final homeserverField = find.byWidgetPredicate(
      (widget) => widget is TextField && !widget.readOnly,
    );
    await waitFor(homeserverField);
    await enterText(
      homeserverField,
      'http://$homeserver',
      pumpAndSettle: false,
    );
    final homeserverOption = find.widgetWithText(
      RadioListTile<PublicHomeserverData>,
      'http://$homeserver',
    );
    await waitFor(homeserverOption);
    await tapOn(homeserverOption);
    await waitFor('Continue');
    await tapOn('Continue', pumpAndSettle: false);
    await waitFor('Log in to http://$homeserver');
    await enterText(TextField, username, index: 0, pumpAndSettle: false);
    await enterText(TextField, password, index: 1, pumpAndSettle: false);
    await tapOn('Login', pumpAndSettle: false);
  }

  Future<void> logout() async {
    await ensureLoggedIn();
    await tapOn(Key('account_settings_button'));
    await waitFor(Key('SettingsListViewContent'));
    await scrollUntilVisible('Logout');
    await tapOn('Logout');
    await tapOn(Key('ok_cancel_alert_dialog_ok_button'));
    await waitFor('Sign in');
  }

  Future<void> skipNoNotificationsDialog() async {
    if (await isVisible('Push notifications not available')) {
      await tapOn('Do not show again');
    }
  }

  static final Map<String, String> userPassphrases = {};

  Future<bool> ensureLoggedIn({bool initializeCryptoIdentity = true}) async {
    if (await isVisible('Sign in') == false) return false;

    await login();
    if (initializeCryptoIdentity) {
      await initCryptoIdentity();
    }

    await skipNoNotificationsDialog();
    return true;
  }
}
