import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/process_runner.dart';
import '../scan/du_scanner.dart';

const _exdev = 18;

class TrashedEntry {
  const TrashedEntry({required this.originalPath, required this.trashedName});

  final String originalPath;
  final String trashedName;
}

class TrashListing {
  const TrashListing({
    required this.name,
    required this.originalPath,
    required this.deletedAt,
    required this.bytes,
  });

  final String name;
  final String originalPath;
  final DateTime deletedAt;
  final int? bytes;
}

class TrashService {
  TrashService({
    required this.trashDir,
    required this.runner,
    required this.du,
    Future<void> Function(String from, String to)? renameFn,
  }) : _rename = renameFn ?? _renameEntity;

  final String trashDir;
  final ProcessRunner runner;
  final DuScanner du;
  final Future<void> Function(String from, String to) _rename;

  String get _filesDir => p.join(trashDir, 'files');
  String get _infoDir => p.join(trashDir, 'info');

  Future<TrashedEntry?> moveToTrash(String path) async {
    await Directory(_filesDir).create(recursive: true);
    await Directory(_infoDir).create(recursive: true);

    final absolute = p.normalize(p.absolute(path));
    final content = _trashInfo(absolute, DateTime.now());
    final (name, infoFile) = await _reserveName(p.basename(absolute), content);

    try {
      await _rename(absolute, p.join(_filesDir, name));
    } on FileSystemException catch (e) {
      await _deleteQuietly(infoFile);
      if (e.osError?.errorCode != _exdev) rethrow;
      final r = await runner.run('gio', ['trash', absolute]);
      if (r.exitCode != 0) {
        throw FileSystemException('gio trash falhou: ${r.stderr}', absolute);
      }
      return null;
    } catch (_) {
      await _deleteQuietly(infoFile);
      rethrow;
    }
    return TrashedEntry(originalPath: absolute, trashedName: name);
  }

  Future<void> restore(TrashedEntry e) async {
    _checkName(e.trashedName);
    final source = p.join(_filesDir, e.trashedName);
    final target = e.originalPath;
    if (FileSystemEntity.typeSync(target, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('Destino já existe', target);
    }
    await Directory(p.dirname(target)).create(recursive: true);
    await _rename(source, target);
    await _deleteQuietly(File(_infoPath(e.trashedName)));
  }

  Future<List<TrashListing>> list() async {
    final infoDir = Directory(_infoDir);
    if (!await infoDir.exists()) return [];
    final parsed = <({String name, String path, DateTime date})>[];
    await for (final entity in infoDir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.trashinfo')) continue;
      final base = p.basename(entity.path);
      final name = base.substring(0, base.length - '.trashinfo'.length);
      if (FileSystemEntity.typeSync(
            p.join(_filesDir, name),
            followLinks: false,
          ) ==
          FileSystemEntityType.notFound) {
        continue;
      }
      final String text;
      try {
        text = await entity.readAsString();
      } on FileSystemException {
        continue;
      }
      final info = _parseInfo(text);
      if (info == null) continue;
      parsed.add((name: name, path: info.path, date: info.date));
    }
    final sizes = await du.sizesOf([
      for (final i in parsed) p.join(_filesDir, i.name),
    ]);
    return [
      for (final i in parsed)
        TrashListing(
          name: i.name,
          originalPath: i.path,
          deletedAt: i.date,
          bytes: sizes[p.join(_filesDir, i.name)],
        ),
    ];
  }

  Future<int> empty() async {
    var failed = 0;
    for (final dir in [_filesDir, _infoDir]) {
      final d = Directory(dir);
      try {
        if (!await d.exists()) {
          await d.create(recursive: true);
          continue;
        }
        final entries = await d.list(followLinks: false).toList();
        for (final entity in entries) {
          try {
            await _deleteEntity(entity.path);
          } on FileSystemException {
            failed++;
          }
        }
      } on FileSystemException {
        failed++;
      }
    }
    return failed;
  }

  Future<void> deleteFromTrash(List<String> names) async {
    names.forEach(_checkName);
    for (final name in names) {
      await _deleteEntity(p.join(_filesDir, name));
      await _deleteEntity(_infoPath(name));
    }
  }

  String _infoPath(String name) => p.join(_infoDir, '$name.trashinfo');

  Future<(String, File)> _reserveName(String base, String content) async {
    final ext = p.extension(base);
    final stem = base.substring(0, base.length - ext.length);
    for (var n = 1; ; n++) {
      final name = n == 1 ? base : '$stem.$n$ext';
      if (FileSystemEntity.typeSync(
            p.join(_filesDir, name),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      final info = File(_infoPath(name));
      try {
        await info.create(exclusive: true);
      } on PathExistsException {
        continue;
      }
      try {
        await info.writeAsString(content);
      } catch (_) {
        await _deleteQuietly(info);
        rethrow;
      }
      return (name, info);
    }
  }

  static void _checkName(String name) {
    if (name.isEmpty || name.contains('/') || name == '..' || name == '.') {
      throw ArgumentError.value(name, 'name', 'Nome inválido na lixeira');
    }
  }

  static Future<void> _deleteEntity(String path) async {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.link:
        await Link(path).delete();
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: true);
      default:
        await File(path).delete();
    }
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      await f.delete();
    } on FileSystemException {
      return;
    }
  }

  static Future<void> _renameEntity(String from, String to) async {
    switch (FileSystemEntity.typeSync(from, followLinks: false)) {
      case FileSystemEntityType.link:
        await Link(from).rename(to);
      case FileSystemEntityType.directory:
        await Directory(from).rename(to);
      default:
        await File(from).rename(to);
    }
  }

  static String _trashInfo(String absolutePath, DateTime when) {
    final encoded = absolutePath.split('/').map(Uri.encodeComponent).join('/');
    return '[Trash Info]\nPath=$encoded\nDeletionDate=${_format(when)}\n';
  }

  static String _format(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
        'T${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  static ({String path, DateTime date})? _parseInfo(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty || lines.first.trim() != '[Trash Info]') return null;
    String? path;
    DateTime? date;
    for (final line in lines.skip(1)) {
      if (line.startsWith('Path=')) {
        try {
          path = Uri.decodeComponent(line.substring(5).trim());
        } on FormatException {
          return null;
        } on ArgumentError {
          return null;
        }
      } else if (line.startsWith('DeletionDate=')) {
        date = DateTime.tryParse(line.substring(13).trim());
      }
    }
    if (path == null || date == null) return null;
    return (path: path, date: date);
  }
}
