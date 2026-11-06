import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(720, 560),
      title: 'Disk Cleanup',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(const DiskCleanupApp());
}
