import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/profile/platform_avatar_picker.dart';

void main() {
  test('uploads a selected image and returns the validated MXC URI', () async {
    String? uploadedMimeType;
    Uint8List? uploadedBytes;
    final picker = PlatformAvatarPicker(
      selectFile: () async => XFile.fromData(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        mimeType: 'image/png',
        name: 'avatar.png',
      ),
      uploadMedia: ({required mimeType, required bytes}) async {
        uploadedMimeType = mimeType;
        uploadedBytes = Uint8List.fromList(bytes);
        return 'mxc://example.org/avatar';
      },
    );

    final avatar = await picker.pick();

    expect(avatar, Uri.parse('mxc://example.org/avatar'));
    expect(uploadedMimeType, 'image/png');
    expect(uploadedBytes, <int>[1, 2, 3, 4]);
  });

  test(
    'infers image MIME type from filename when metadata is absent',
    () async {
      String? uploadedMimeType;
      final picker = PlatformAvatarPicker(
        selectFile: () async => XFile.fromData(
          Uint8List.fromList(<int>[7, 8]),
          path: 'avatar.JPEG',
        ),
        uploadMedia: ({required mimeType, required bytes}) async {
          uploadedMimeType = mimeType;
          return 'mxc://example.org/avatar';
        },
      );

      await picker.pick();

      expect(uploadedMimeType, 'image/jpeg');
    },
  );

  test('cancelled selection does not upload', () async {
    var uploadCalls = 0;
    final picker = PlatformAvatarPicker(
      selectFile: () async => null,
      uploadMedia: ({required mimeType, required bytes}) async {
        uploadCalls += 1;
        return 'mxc://example.org/avatar';
      },
    );

    expect(await picker.pick(), isNull);
    expect(uploadCalls, 0);
  });

  test('rejects unsupported files before upload', () async {
    var uploadCalls = 0;
    final picker = PlatformAvatarPicker(
      selectFile: () async => XFile.fromData(
        Uint8List.fromList(<int>[1]),
        mimeType: 'text/plain',
        name: 'avatar.txt',
      ),
      uploadMedia: ({required mimeType, required bytes}) async {
        uploadCalls += 1;
        return 'mxc://example.org/avatar';
      },
    );

    await expectLater(picker.pick(), throwsStateError);
    expect(uploadCalls, 0);
  });

  test('rejects malformed media upload URI', () async {
    final picker = PlatformAvatarPicker(
      selectFile: () async => XFile.fromData(
        Uint8List.fromList(<int>[1]),
        mimeType: 'image/png',
        name: 'avatar.png',
      ),
      uploadMedia: ({required mimeType, required bytes}) async =>
          'https://example.org/avatar.png',
    );

    await expectLater(picker.pick(), throwsStateError);
  });
}
