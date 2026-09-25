import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/features/home/home_screen.dart';
import 'package:kite/features/timeline/timeline_attachment_widgets.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

import 'performance_benchmark_harness.dart';

final class _ProfileImagePicker implements ComposerAttachmentPicker {
  _ProfileImagePicker(this.attachment);

  final TimelineAttachment attachment;

  @override
  Set<ComposerAttachmentSource> get supportedSources =>
      const <ComposerAttachmentSource>{ComposerAttachmentSource.photos};

  @override
  Future<TimelineAttachment?> pick(ComposerAttachmentSource source) async =>
      source == ComposerAttachmentSource.photos ? attachment : null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const virtualizedBenchmark = bool.fromEnvironment(
    'KITE_VIRTUALIZED_BENCHMARK',
  );
  final enforceTotalSpan = virtualizedBenchmark
      ? PerformanceContract.gateVirtualizedTotalSpan
      : PerformanceContract.gatePhysicalTotalSpan;

  tearDown(() {
    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(),
    );
    selectRoom('kite');
  });

  testWidgets('image crop and rotate stays within the frame contract', (
    tester,
  ) async {
    final source = img.Image(width: 640, height: 360);
    final bytes = Uint8List.fromList(img.encodePng(source));
    final attachment = TimelineAttachment(
      id: 'profile-image-edit',
      kind: TimelineAttachmentKind.image,
      name: 'profile-image.png',
      sizeLabel: 'Image',
      sizeBytes: bytes.length,
      mimeType: 'image/png',
      localBytes: bytes,
    );

    timelineController.reset(
      sendPort: DeterministicTimelineSendPort(),
      attachmentSendPort: const DeterministicTimelineAttachmentSendPort(
        latency: Duration.zero,
      ),
    );
    selectRoom('alice');
    await tester.pumpWidget(
      KiteApp(
        themeMode: ThemeMode.dark,
        home: HomeScreen(
          composerAttachmentPicker: _ProfileImagePicker(attachment),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-option-photo-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-attachment-edit')), findsOneWidget);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final result = await measureFrames(
      binding: binding,
      action: () async {
        await tester.tap(find.byKey(const Key('composer-attachment-edit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('composer-image-rotate-right')));
        await tester.tap(find.byKey(const Key('composer-image-crop-square')));
        await tester.pump();
        await tester.drag(
          find.byKey(const Key('composer-image-preview')),
          const Offset(-48, 0),
        );
        await tester.tap(find.byKey(const Key('composer-image-apply')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('composer-image-editor')), findsNothing);
        await tester.tap(find.byKey(const Key('composer-send')));
        await tester.pumpAndSettle();
      },
      enforceTotalSpan: enforceTotalSpan,
    );

    final sent = timelineController.messagesFor('alice').value.last;
    expect(sent.attachment?.kind, TimelineAttachmentKind.image);
    final edited = img.decodeImage(sent.attachment?.localBytes ?? Uint8List(0));
    expect(
      edited,
      isNull,
      reason: 'timeline rows must not retain local attachment payload bytes',
    );
    expect(sent.sendState.value, TimelineSendState.sent);

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['composer_image_edit'] = <String, dynamic>{
      'journey': 'composer_image_crop_rotate_send',
      'fixture': 'deterministic_composer_image_v1',
      ...result,
      'result': 'PASS',
    };
  });
}
