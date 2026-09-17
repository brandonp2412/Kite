import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

typedef AvatarMediaUploader = Future<String> Function({
  required String mimeType,
  required Uint8List bytes,
});

typedef AvatarFileSelector = Future<XFile?> Function();

final class PlatformAvatarPicker {
  const PlatformAvatarPicker({required this.uploadMedia, this.selectFile});

  final AvatarMediaUploader uploadMedia;
  final AvatarFileSelector? selectFile;

  Future<Uri?> pick() async {
    final file = await (selectFile?.call() ?? _selectAvatarFile());
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Selected avatar image is empty');
    }
    final mimeType = _avatarMimeType(file);
    if (mimeType == null) {
      throw StateError('Selected avatar is not a supported image');
    }

    final contentUri = await uploadMedia(mimeType: mimeType, bytes: bytes);
    final avatarUri = Uri.tryParse(contentUri);
    if (avatarUri == null ||
        avatarUri.scheme != 'mxc' ||
        avatarUri.host.isEmpty ||
        avatarUri.userInfo.isNotEmpty ||
        avatarUri.hasQuery ||
        avatarUri.hasFragment ||
        avatarUri.pathSegments.length != 1 ||
        avatarUri.pathSegments.single.isEmpty) {
      throw StateError('Matrix media upload returned an invalid avatar URI');
    }
    return avatarUri;
  }

  static Future<XFile?> _selectAvatarFile() {
    return openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'Images',
          extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'gif'],
          mimeTypes: <String>[
            'image/jpeg',
            'image/png',
            'image/webp',
            'image/gif',
          ],
          webWildCards: <String>['image/*'],
        ),
      ],
    );
  }

  static String? _avatarMimeType(XFile file) {
    final provided = file.mimeType?.trim().toLowerCase();
    if (provided != null && provided.startsWith('image/')) return provided;

    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    return null;
  }
}
