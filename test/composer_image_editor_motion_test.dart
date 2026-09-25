import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/timeline/composer_image_editor.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/testing/deterministic_adapters.dart';

void main() {
  testWidgets('image edit controls stay geometry-stable at 120 Hz', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final display = tester.binding.platformDispatcher.displays.first;
    display.refreshRate = PerformanceContract.motionRefreshRateHz;
    addTearDown(display.resetRefreshRate);

    await tester.pumpWidget(
      KiteApp(
        themeMode: ThemeMode.light,
        home: ComposerImageEditor(
          attachment: TimelineAttachment(
            id: 'motion-image',
            kind: TimelineAttachmentKind.image,
            name: 'motion.png',
            sizeLabel: 'Image',
            sizeBytes: DeterministicImageFixtures.transparentPng1x1.length,
            mimeType: 'image/png',
            localBytes: DeterministicImageFixtures.transparentPng1x1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rotateLeft = find.byKey(const Key('composer-image-rotate-left'));
    final rotateRight = find.byKey(const Key('composer-image-rotate-right'));
    final apply = find.byKey(const Key('composer-image-apply'));
    final leftRect = tester.getRect(rotateLeft);
    final rightRect = tester.getRect(rotateRight);
    final applyRect = tester.getRect(apply);

    await tester.tap(rotateRight);
    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(tester.getRect(rotateLeft), leftRect);
      expect(tester.getRect(rotateRight), rightRect);
      expect(tester.getRect(apply), applyRect);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byKey(const Key('composer-image-crop-square')));
    await tester.pump(PerformanceContract.motionFrame);
    final croppedPreview = find.byKey(const Key('composer-image-preview'));
    final croppedRect = tester.getRect(croppedPreview);
    expect(croppedRect.width, closeTo(croppedRect.height, 0.01));

    for (var index = 0; index < PerformanceContract.motionSamples; index++) {
      await tester.pump(PerformanceContract.motionFrame);
      expect(tester.getRect(croppedPreview), croppedRect);
      expect(tester.getRect(rotateLeft), leftRect);
      expect(tester.getRect(rotateRight), rightRect);
      expect(tester.getRect(apply), applyRect);
      expect(tester.takeException(), isNull);
    }
  });
}
