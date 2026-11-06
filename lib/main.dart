import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'settings/settings.dart';
import 'settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final home = Platform.environment['HOME'] ?? '/';
  final store = SettingsStore(
    SettingsStore.defaultPath(Platform.environment, home),
  );
  var settings = await store.load(home);
  final window = WindowManager.instance.getCurrent();
  if (window != null) {
    window.title = 'Disk Cleanup';
    window.minimumSize = const Size(720, 560).toNative();
    final saved = settings.window;
    if (saved == null) {
      window.setSize(const Size(1280, 800).toNative(), false);
      window.center();
    } else {
      window.bounds = Rect.fromLTWH(
        saved.x,
        saved.y,
        saved.width < 720 ? 720 : saved.width,
        saved.height < 560 ? 560 : saved.height,
      ).toNative();
      if (saved.maximized) window.maximize();
    }
    window.show();
    _persistGeometry(window, store, () => settings, (s) => settings = s);
  }
  runApp(const DiskCleanupApp());
}

void _persistGeometry(
  Window window,
  SettingsStore store,
  Settings Function() current,
  void Function(Settings) update,
) {
  Timer? debounce;
  WindowManager.instance.addListener((event) {
    switch (event) {
      case WindowResizedEvent():
      case WindowMovedEvent():
      case WindowMaximizedEvent():
      case WindowRestoredEvent():
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 500), () {
          final maximized = window.isMaximized;
          final previous = current().window;
          final rect = maximized && previous != null
              ? Rect.fromLTWH(
                  previous.x,
                  previous.y,
                  previous.width,
                  previous.height,
                )
              : window.bounds.toRect();
          final next = current().copyWith(
            window: WindowBounds(
              x: rect.left,
              y: rect.top,
              width: rect.width,
              height: rect.height,
              maximized: maximized,
            ),
          );
          update(next);
          unawaited(store.save(next));
        });
      default:
        break;
    }
  });
}
