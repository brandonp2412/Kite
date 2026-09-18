import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadGoldenTestFonts() async {
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    flutterRoot = flutterRoot.parent;
  }
  final materialFonts = Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  );
  final roboto = File('${materialFonts.path}/Roboto-Regular.ttf');
  final materialIcons = File('${materialFonts.path}/MaterialIcons-Regular.otf');
  if (!roboto.existsSync()) {
    throw StateError('Flutter Roboto font not found at ${roboto.path}');
  }
  if (!materialIcons.existsSync()) {
    throw StateError(
      'Flutter Material Icons font not found at ${materialIcons.path}',
    );
  }

  final robotoData = ByteData.sublistView(await roboto.readAsBytes());
  for (final family in <String>['Ahem', 'Roboto']) {
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(robotoData));
    await loader.load();
  }

  final materialIconsData = ByteData.sublistView(
    await materialIcons.readAsBytes(),
  );
  final materialIconsLoader = FontLoader('MaterialIcons')
    ..addFont(Future<ByteData>.value(materialIconsData));
  await materialIconsLoader.load();
}
