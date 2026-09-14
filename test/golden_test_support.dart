import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadGoldenTestFonts() async {
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    flutterRoot = flutterRoot.parent;
  }
  final roboto = File(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  );
  if (!roboto.existsSync()) {
    throw StateError('Flutter Roboto font not found at ${roboto.path}');
  }

  final bytes = await roboto.readAsBytes();
  final data = ByteData.sublistView(bytes);
  for (final family in <String>['Ahem', 'Roboto']) {
    final loader = FontLoader(family)..addFont(Future<ByteData>.value(data));
    await loader.load();
  }
}
