import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/features/media/media_viewer.dart';
import 'package:kite/features/timeline/platform_timeline_media_action_port.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TimelineMessage remoteImage({
    String name = 'photo.jpg',
    Uint8List? localBytes,
  }) {
    return TimelineMessage(
      id: 'event',
      sender: 'Alice',
      body: 'Evening walk',
      mine: false,
      timeLabel: '10:00',
      attachment: TimelineAttachment(
        id: 'image',
        kind: TimelineAttachmentKind.image,
        name: name,
        sizeLabel: '2 MB · Photo',
        mimeType: 'image/jpeg',
        localBytes: localBytes,
        contentUri: 'mxc://kite.test/photo',
        encryptedFile: const <String, Object?>{
          'url': 'mxc://kite.test/photo',
          'v': 'v2',
        },
      ),
    );
  }

  test('playback loads original encrypted Matrix media bytes', () async {
    var loadCalls = 0;
    final port = PlatformTimelineMediaActionPort(
      loadOriginalMedia: (attachment) async {
        loadCalls += 1;
        expect(attachment.contentUri, 'mxc://kite.test/photo');
        expect(attachment.encryptedFile?['v'], 'v2');
        return Uint8List.fromList(<int>[8, 6, 7, 5]);
      },
    );

    final bytes = await port.loadOriginal(
      roomId: '!room:kite.test',
      message: remoteImage(),
    );

    expect(loadCalls, 1);
    expect(bytes, <int>[8, 6, 7, 5]);
  });

  test(
    'Android save downloads original bytes and writes public media payload',
    () async {
      var loadCalls = 0;
      Uint8List? savedBytes;
      String? savedName;
      String? savedMimeType;
      final port = PlatformTimelineMediaActionPort(
        platformOverride: TargetPlatform.android,
        webOverride: false,
        loadOriginalMedia: (attachment) async {
          loadCalls += 1;
          expect(attachment.contentUri, 'mxc://kite.test/photo');
          return Uint8List.fromList(<int>[1, 2, 3, 4]);
        },
        androidMediaSaver:
            ({required bytes, required name, required mimeType}) async {
              savedBytes = Uint8List.fromList(bytes);
              savedName = name;
              savedMimeType = mimeType;
            },
      );

      await port.save(roomId: '!room:kite.test', message: remoteImage());

      expect(loadCalls, 1);
      expect(savedBytes, <int>[1, 2, 3, 4]);
      expect(savedName, 'photo.jpg');
      expect(savedMimeType, 'image/jpeg');
    },
  );

  test('older Android save falls back to the OS export surface', () async {
    var shareCalls = 0;
    final port = PlatformTimelineMediaActionPort(
      platformOverride: TargetPlatform.android,
      webOverride: false,
      loadOriginalMedia: (_) async => Uint8List.fromList(<int>[4, 5, 6]),
      androidMediaSaver:
          ({required bytes, required name, required mimeType}) async {
            throw PlatformException(
              code: 'media_save_unsupported',
              message: 'Requires Android 10',
            );
          },
      shareLauncher:
          ({
            required bytes,
            required name,
            required mimeType,
            required caption,
            required downloadFallbackEnabled,
          }) async {
            shareCalls += 1;
            expect(bytes, <int>[4, 5, 6]);
            expect(name, 'photo.jpg');
            expect(downloadFallbackEnabled, isFalse);
            return const ShareResult('share', ShareResultStatus.success);
          },
    );

    await port.save(roomId: '!room:kite.test', message: remoteImage());

    expect(shareCalls, 1);
  });

  test('local attachment bytes are reused without a Matrix download', () async {
    var loadCalls = 0;
    Uint8List? savedBytes;
    final port = PlatformTimelineMediaActionPort(
      platformOverride: TargetPlatform.android,
      webOverride: false,
      loadOriginalMedia: (_) async {
        loadCalls += 1;
        return Uint8List.fromList(<int>[9]);
      },
      androidMediaSaver:
          ({required bytes, required name, required mimeType}) async {
            savedBytes = Uint8List.fromList(bytes);
          },
    );

    await port.save(
      roomId: '!room:kite.test',
      message: remoteImage(localBytes: Uint8List.fromList(<int>[7, 8])),
    );

    expect(loadCalls, 0);
    expect(savedBytes, <int>[7, 8]);
  });

  test(
    'desktop save sanitizes the filename and writes the selected file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kite-media-save-',
      );
      addTearDown(() => directory.delete(recursive: true));
      late String suggestedName;
      final target = '${directory.path}/saved.jpg';
      final port = PlatformTimelineMediaActionPort(
        platformOverride: TargetPlatform.linux,
        webOverride: false,
        loadOriginalMedia: (_) async => Uint8List.fromList(<int>[5, 6, 7]),
        saveLocationSelector: (name) async {
          suggestedName = name;
          return FileSaveLocation(target);
        },
      );

      await port.save(
        roomId: '!room:kite.test',
        message: remoteImage(name: '../bad/name.jpg'),
      );

      expect(suggestedName, '.._bad_name.jpg');
      expect(await File(target).readAsBytes(), <int>[5, 6, 7]);
    },
  );

  test('dismissed save picker is treated as cancellation', () async {
    final port = PlatformTimelineMediaActionPort(
      platformOverride: TargetPlatform.linux,
      webOverride: false,
      loadOriginalMedia: (_) async => Uint8List.fromList(<int>[1]),
      saveLocationSelector: (_) async => null,
    );

    await expectLater(
      port.save(roomId: '!room:kite.test', message: remoteImage()),
      throwsA(isA<MediaViewerActionCancelled>()),
    );
  });

  test(
    'share exports original bytes with caption and sanitized filename',
    () async {
      late Uint8List sharedBytes;
      late String sharedName;
      late String sharedMimeType;
      String? sharedCaption;
      final port = PlatformTimelineMediaActionPort(
        platformOverride: TargetPlatform.android,
        webOverride: false,
        loadOriginalMedia: (_) async => Uint8List.fromList(<int>[3, 2, 1]),
        shareLauncher:
            ({
              required bytes,
              required name,
              required mimeType,
              required caption,
              required downloadFallbackEnabled,
            }) async {
              sharedBytes = Uint8List.fromList(bytes);
              sharedName = name;
              sharedMimeType = mimeType;
              sharedCaption = caption;
              expect(downloadFallbackEnabled, isFalse);
              return const ShareResult('share', ShareResultStatus.success);
            },
      );

      await port.share(
        roomId: '!room:kite.test',
        message: remoteImage(name: 'photo/unsafe.jpg'),
      );

      expect(sharedBytes, <int>[3, 2, 1]);
      expect(sharedName, 'photo_unsafe.jpg');
      expect(sharedMimeType, 'image/jpeg');
      expect(sharedCaption, 'Evening walk');
    },
  );

  test('dismissed share surface is treated as cancellation', () async {
    final port = PlatformTimelineMediaActionPort(
      platformOverride: TargetPlatform.iOS,
      webOverride: false,
      loadOriginalMedia: (_) async => Uint8List.fromList(<int>[1]),
      shareLauncher: ({
        required bytes,
        required name,
        required mimeType,
        required caption,
        required downloadFallbackEnabled,
      }) async => const ShareResult('dismissed', ShareResultStatus.dismissed),
    );

    await expectLater(
      port.share(roomId: '!room:kite.test', message: remoteImage()),
      throwsA(isA<MediaViewerActionCancelled>()),
    );
  });
}
