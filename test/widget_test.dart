import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';

void main() {
  testWidgets('Kite deterministic shell renders', (tester) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    expect(find.text('Kite'), findsWidgets);
    expect(find.byKey(const Key('room-alice')), findsOneWidget);
    expect(find.byKey(const Key('composer')), findsOneWidget);
  });
}
