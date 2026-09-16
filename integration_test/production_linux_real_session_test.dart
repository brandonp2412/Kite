import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Linux session paginates the selected Matrix timeline', (
    tester,
  ) async {
    await app.main();

    for (var i = 0; i < 80; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byKey(const Key('home-search')).evaluate().isNotEmpty) break;
    }

    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(find.text('Matrix runtime is unavailable.'), findsNothing);
    expect(find.text('Could not start Matrix sync.'), findsNothing);

    final uptime = find.text('Uptime');
    expect(uptime, findsWidgets);
    await tester.tap(uptime.first);
    await tester.pump(const Duration(milliseconds: 500));

    final messageList = find.byKey(const Key('message-list'));
    expect(messageList, findsOneWidget);

    var listView = tester.widget<ListView>(messageList);
    final initialCount = listView.childrenDelegate.estimatedChildCount ?? 0;
    expect(initialCount, greaterThan(0));

    var position = listView.controller!.position;
    final initialExtentAfter = position.extentAfter;
    expect(initialExtentAfter, greaterThan(0));

    listView.controller!.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 500));
    listView = tester.widget<ListView>(messageList);
    position = listView.controller!.position;
    expect(position.extentAfter, lessThanOrEqualTo(520));

    for (var i = 0; i < 48; i += 1) {
      await tester.pump(const Duration(milliseconds: 250));
      listView = tester.widget<ListView>(messageList);
      if ((listView.childrenDelegate.estimatedChildCount ?? 0) > initialCount) {
        break;
      }
    }

    listView = tester.widget<ListView>(messageList);
    final finalCount = listView.childrenDelegate.estimatedChildCount ?? 0;
    expect(finalCount, greaterThan(initialCount));
    expect(
      find.textContaining('Matrix Rust SDK back-pagination failed'),
      findsNothing,
    );
  });
}
