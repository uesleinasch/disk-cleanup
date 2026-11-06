import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services.dart';
import 'settings/settings.dart';
import 'settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = Services.system();
  final settings = SettingsController(services.settingsStore, services.home);
  await settings.load();
  final window = WindowManager.instance.getCurrent();
  if (window != null) {
    window.title = 'Disk Cleanup';
    window.minimumSize = const Size(720, 560).toNative();
    final saved = settings.value.window;
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
    _persistGeometry(window, settings);
  }
  runApp(DiskCleanupApp(services: services, settings: settings));
}

void _persistGeometry(Window window, SettingsController settings) {
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
          final previous = settings.value.window;
          final rect = maximized && previous != null
              ? Rect.fromLTWH(
                  previous.x,
                  previous.y,
                  previous.width,
                  previous.height,
                )
              : window.bounds.toRect();
          unawaited(
            settings.update(
              (s) => s.copyWith(
                window: WindowBounds(
                  x: rect.left,
                  y: rect.top,
                  width: rect.width,
                  height: rect.height,
                  maximized: maximized,
                ),
              ),
            ),
          );
        });
      default:
        break;
    }
  });
}
