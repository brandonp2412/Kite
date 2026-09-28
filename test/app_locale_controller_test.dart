// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:kite/utils/app_locale_controller.dart';

void main() {
  test('locale override resolves only shipped locales', () {
    expect(AppLocaleController.localeForTag(''), isNull);
    expect(AppLocaleController.localeForTag('de')?.languageCode, 'de');
    expect(AppLocaleController.localeForTag('pt-BR')?.countryCode, 'BR');
    expect(AppLocaleController.localeForTag('zh-Hant')?.scriptCode, 'Hant');
    expect(AppLocaleController.localeForTag('not-a-locale'), isNull);
  });
}
