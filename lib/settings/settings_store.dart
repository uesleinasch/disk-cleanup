import 'dart:convert';
import 'dart:io';

import 'settings.dart';

class SettingsStore {
  SettingsStore(this.filePath);

  final String filePath;

  static String defaultPath(Map<String, String> env, String home) {
    final xdg = env['XDG_CONFIG_HOME'];
    final base = (xdg != null && xdg.isNotEmpty) ? xdg : '$home/.config';
    return '$base/disk-cleanup/settings.json';
  }

  Future<Settings> load(String home) async {
    final file = File(filePath);
    if (!await file.exists()) return Settings.defaults(home);
    try {
      final json = jsonDecode(await file.readAsString());
      return Settings.fromJson((json as Map).cast<String, Object?>(), home);
    } catch (_) {
      try {
        await file.rename('$filePath.bak');
      } catch (_) {}
      return Settings.defaults(home);
    }
  }

  Future<void> save(Settings s) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final tmp = File('$filePath.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(s.toJson()),
    );
    await tmp.rename(filePath);
  }
}
