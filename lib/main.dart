import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/app/production_kite_runtime.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/media_cache_policy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  KiteMediaCachePolicy.apply();
  KiteTheme.warmUp();
  try {
    runApp(await ProductionKiteRuntime.create());
  } catch (_) {
    runApp(
      const KiteApp(
        home: Scaffold(
          body: Center(child: Text('Matrix runtime is unavailable.')),
        ),
      ),
    );
  }
}
