import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final window = WindowManager.instance.getCurrent();
  if (window != null) {
    window.title = 'Disk Cleanup';
    window.minimumSize = const Size(720, 560).toNative();
    window.setSize(const Size(1280, 800).toNative(), false);
    window.center();
    window.show();
  }
  runApp(const DiskCleanupApp());
}
