import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/timeline/platform_composer_attachment_picker.dart';
import 'package:kite/features/timeline/timeline_attachment_widgets.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

void main() {
  test(
    'picker keeps selected bytes local until Matrix attachment send',
    () async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final picker = PlatformComposerAttachmentPicker(
        selectFile: (_) async =>
            XFile.fromData(bytes, path: 'photo.png', mimeType: 'image/png'),
      );

      final attachment = await picker.pick(ComposerAttachmentSource.photos);

      expect(attachment, isNotNull);
      expect(attachment!.kind, TimelineAttachmentKind.image);
      expect(attachment.name, 'photo.png');
      expect(attachment.mimeType, 'image/png');
      expect(attachment.localBytes, orderedEquals(bytes));
      expect(attachment.contentUri, isNull);
      expect(attachment.sizeBytes, bytes.length);
    },
  );

  test('production picker exposes only sources backed by file selector', () {
    const picker = PlatformComposerAttachmentPicker();

    expect(picker.supportedSources, <ComposerAttachmentSource>{
      ComposerAttachmentSource.photos,
      ComposerAttachmentSource.videos,
      ComposerAttachmentSource.files,
    });
    expect(
      picker.supportedSources,
      isNot(contains(ComposerAttachmentSource.camera)),
    );
  });
}
