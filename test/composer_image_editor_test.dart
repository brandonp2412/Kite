import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/timeline/composer_image_editor.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  test(
    'image editor crops from the requested focal position off-isolate',
    () async {
      final attachment = _imageAttachment();

      final edited = await processComposerImageEdit(
        attachment: attachment,
        quarterTurns: 0,
        cropAspect: ComposerImageCropAspect.square,
        focus: const Offset(1, 0.5),
      );

      final decoded = img.decodeImage(edited.localBytes!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 2);
      expect(decoded.height, 2);
      expect(decoded.getPixel(0, 0).b, greaterThan(200));
      expect(decoded.getPixel(0, 0).r, lessThan(40));
      expect(edited.mimeType, 'image/png');
      expect(edited.name, 'photo.png');
      expect(edited.sizeBytes, edited.localBytes!.length);
    },
  );

  test('image editor rotates local image bytes by quarter turns', () async {
    final edited = await processComposerImageEdit(
      attachment: _imageAttachment(),
      quarterTurns: 1,
      cropAspect: ComposerImageCropAspect.original,
      focus: const Offset(0.5, 0.5),
    );

    final decoded = img.decodeImage(edited.localBytes!);
    expect(decoded, isNotNull);
    expect(decoded!.width, 2);
    expect(decoded.height, 4);
  });

  test(
    'no-op edit preserves original attachment without recompression',
    () async {
      final attachment = _imageAttachment();

      final edited = await processComposerImageEdit(
        attachment: attachment,
        quarterTurns: 4,
        cropAspect: ComposerImageCropAspect.original,
        focus: const Offset(0.5, 0.5),
      );

      expect(identical(edited, attachment), isTrue);
    },
  );

  testWidgets('editor returns selected rotation crop and focal position', (
    tester,
  ) async {
    final attachment = _imageAttachment();
    int? capturedQuarterTurns;
    ComposerImageCropAspect? capturedCropAspect;
    Offset? capturedFocus;
    TimelineAttachment? result;

    await tester.pumpWidget(
      KiteApp(
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await showComposerImageEditor(
                  context,
                  attachment: attachment,
                  processor:
                      ({
                        required attachment,
                        required quarterTurns,
                        required cropAspect,
                        required focus,
                      }) async {
                        capturedQuarterTurns = quarterTurns;
                        capturedCropAspect = cropAspect;
                        capturedFocus = focus;
                        return attachment;
                      },
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-image-editor')), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-image-rotate-right')));
    await tester.tap(find.byKey(const Key('composer-image-crop-square')));
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('composer-image-preview')),
      const Offset(-36, 0),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('composer-image-apply')));
    await tester.pumpAndSettle();

    expect(capturedQuarterTurns, 1);
    expect(capturedCropAspect, ComposerImageCropAspect.square);
    expect(capturedFocus, isNotNull);
    expect(capturedFocus!.dx, greaterThan(0.5));
    expect(result, same(attachment));
    expect(find.byKey(const Key('composer-image-editor')), findsNothing);
  });
}

TimelineAttachment _imageAttachment() {
  final image = img.Image(width: 4, height: 2);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (x < 2) {
        image.setPixelRgba(x, y, 255, 0, 0, 255);
      } else {
        image.setPixelRgba(x, y, 0, 0, 255, 255);
      }
    }
  }
  final bytes = Uint8List.fromList(img.encodePng(image));
  return TimelineAttachment(
    id: 'local-image',
    kind: TimelineAttachmentKind.image,
    name: 'photo.png',
    sizeLabel: 'Image',
    sizeBytes: bytes.length,
    mimeType: 'image/png',
    localBytes: bytes,
  );
}
