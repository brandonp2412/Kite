import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

Rect _rectOf(WidgetTester tester, Finder finder) {
  final renderObject = tester.renderObject<RenderBox>(finder);
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void _expectClose(double actual, double expected) {
  expect(actual, moreOrLessEquals(expected, epsilon: 0.01));
}

void main() {
  tearDown(() {
    timelineController.reset(sendPort: DeterministicTimelineSendPort());
    selectRoom('kite');
  });

  testWidgets('formatting toolbar applies deterministic rich-text markers', (
    tester,
  ) async {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(latency: Duration.zero),
    );
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-format-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-formatting-toolbar')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('composer-format-bold')), findsOneWidget);
    expect(find.byKey(const Key('composer-format-italic')), findsOneWidget);
    expect(
      find.byKey(const Key('composer-format-strikethrough')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('composer-format-inlineCode')), findsOneWidget);
    expect(find.byKey(const Key('composer-format-quote')), findsOneWidget);
    expect(find.byKey(const Key('composer-format-codeBlock')), findsOneWidget);

    const source = 'Make stable now';
    await tester.enterText(find.byKey(const Key('composer-field')), source);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('composer-field')),
        matching: find.byType(EditableText),
      ),
    );
    editable.controller.selection = const TextSelection(
      baseOffset: 5,
      extentOffset: 11,
    );
    await tester.tap(find.byKey(const Key('composer-format-bold')));
    await tester.pump();

    expect(editable.controller.text, 'Make **stable** now');
    expect(
      editable.controller.selection.textInside(editable.controller.text),
      'stable',
    );

    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pumpAndSettle();
    final message = timelineController.messagesFor('alice').value.last;
    expect(message.body, 'Make **stable** now');
    expect(find.textContaining('stable'), findsWidgets);
  });

  testWidgets('user and room autocomplete insert stable composer tokens', (
    tester,
  ) async {
    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('composer-field'));
    await tester.enterText(field, 'Ping @a');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-autocomplete')), findsOneWidget);
    expect(
      find.byKey(const Key('composer-autocomplete-Alice')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('composer-autocomplete-Maya')), findsNothing);

    await tester.tap(find.byKey(const Key('composer-autocomplete-Alice')));
    await tester.pumpAndSettle();
    var editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, 'Ping @Alice ');
    expect(find.byKey(const Key('composer-autocomplete')), findsNothing);

    await tester.enterText(field, 'See #d');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-autocomplete-Design-Lab')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('composer-autocomplete-Design-Lab')));
    await tester.pumpAndSettle();
    editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, 'See #Design-Lab ');
  });

  testWidgets('autocomplete expansion is anchored at 120 Hz', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    selectRoom('alice');
    await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    final composer = find.byKey(const Key('composer'));
    final initial = _rectOf(tester, composer);
    await tester.enterText(find.byKey(const Key('composer-field')), '@');
    var previousHeight = initial.height;
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      final rect = _rectOf(tester, composer);
      expect(rect.height + 0.01, greaterThanOrEqualTo(previousHeight));
      _expectClose(rect.width, initial.width);
      _expectClose(rect.bottom, initial.bottom);
      previousHeight = rect.height;
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-autocomplete')), findsOneWidget);
    expect(_rectOf(tester, composer).height, 128);
  });

  testWidgets(
    'formatting toolbar expansion is monotonic and anchored at 120 Hz',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final display = tester.binding.platformDispatcher.displays.first;
      display.refreshRate = PerformanceContract.motionRefreshRateHz;
      addTearDown(display.resetRefreshRate);

      selectRoom('alice');
      await tester.pumpWidget(const KiteApp(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      final composer = find.byKey(const Key('composer'));
      final panel = find.byKey(const Key('chat-panel'));
      final initialComposer = _rectOf(tester, composer);
      final initialPanel = _rectOf(tester, panel);
      expect(initialComposer.height, 76);

      await tester.tap(find.byKey(const Key('composer-format-toggle')));
      var previousHeight = initialComposer.height;
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        final rect = _rectOf(tester, composer);
        expect(rect.height + 0.01, greaterThanOrEqualTo(previousHeight));
        _expectClose(rect.width, initialComposer.width);
        _expectClose(rect.bottom, initialComposer.bottom);
        _expectClose(_rectOf(tester, panel).width, initialPanel.width);
        _expectClose(_rectOf(tester, panel).height, initialPanel.height);
        previousHeight = rect.height;
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      final expanded = _rectOf(tester, composer);
      expect(expanded.height, 128);
      _expectClose(expanded.bottom, initialComposer.bottom);

      await tester.tap(find.byKey(const Key('composer-format-toggle')));
      previousHeight = expanded.height;
      for (var index = 0; index < PerformanceContract.motionSamples; index++) {
        await tester.pump(PerformanceContract.motionFrame);
        final rect = _rectOf(tester, composer);
        expect(rect.height, lessThanOrEqualTo(previousHeight + 0.01));
        _expectClose(rect.width, initialComposer.width);
        _expectClose(rect.bottom, initialComposer.bottom);
        previousHeight = rect.height;
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(_rectOf(tester, composer).height, 76);
    },
  );
}
