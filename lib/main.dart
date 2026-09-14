import 'package:flutter/material.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/design/kite_theme.dart';
import 'package:kite/features/media/media_cache_policy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  KiteMediaCachePolicy.apply();
  KiteTheme.warmUp();
  runApp(const KiteApp());
}
