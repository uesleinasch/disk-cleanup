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
        await file.rename(await _freeBackupPath());
      } catch (_) {}
      return Settings.defaults(home);
    }
  }

  Future<String> _freeBackupPath() async {
    Future<bool> free(String path) async =>
        await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound;

    final plain = '$filePath.bak';
    if (await free(plain)) return plain;
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '-');
    final base = '$filePath.$stamp.bak';
    var candidate = base;
    for (var n = 2; !await free(candidate); n++) {
      candidate = '$base.$n';
    }
    return candidate;
  }

  static final _queues = <String, Future<void>>{};

  Future<void> save(Settings s) {
    final previous = _queues[filePath] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => _write(s));
    _queues[filePath] = next;
    return next;
  }

  Future<void> _write(Settings s) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final tmp = File('$filePath.$pid.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(s.toJson()),
      flush: true,
    );
    await tmp.rename(filePath);
  }
}
