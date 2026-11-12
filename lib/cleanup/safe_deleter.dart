import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/system_paths.dart';

enum DeleteOutcome { deleted, missing, refused, failed }

enum _Check { ok, missing, refused }

class SafeDeleter {
  SafeDeleter({
    required List<String> allowedRoots,
    required List<String> protectedPaths,
    String? home,
  }) : _allowedRoots = [
         for (final root in allowedRoots.map(p.normalize))
           if (home == null || !isForbiddenMappedDir(root, home: home)) root,
       ],
       _protectedPaths = protectedPaths.map(p.normalize).toList();

  final List<String> _allowedRoots;
  final List<String> _protectedPaths;

  Future<bool> canRemove(String path) async =>
      (await _check(path)) == _Check.ok;

  Future<_Check> _check(String path) async {
    if (!p.isAbsolute(path)) return _Check.refused;
    final target = p.normalize(p.absolute(path));
    if (!_isDeletable(target, _allowedRoots, _protectedPaths)) {
      return _Check.refused;
    }
    final String realParent;
    try {
      realParent = await Directory(p.dirname(target)).resolveSymbolicLinks();
    } on FileSystemException {
      return _Check.missing;
    }
    final realTarget = p.join(realParent, p.basename(target));
    if (!_isDeletable(
      realTarget,
      await _resolveAll(_allowedRoots),
      await _resolveAll(_protectedPaths),
    )) {
      return _Check.refused;
    }
    return _Check.ok;
  }

  Future<DeleteOutcome> delete(String path) async {
    try {
      switch (await _check(path)) {
        case _Check.refused:
          return DeleteOutcome.refused;
        case _Check.missing:
          return DeleteOutcome.missing;
        case _Check.ok:
      }
      final target = p.normalize(p.absolute(path));
      switch (FileSystemEntity.typeSync(target, followLinks: false)) {
        case FileSystemEntityType.notFound:
          return DeleteOutcome.missing;
        case FileSystemEntityType.link:
          await Link(target).delete();
        case FileSystemEntityType.directory:
          await Directory(target).delete(recursive: true);
        default:
          await File(target).delete();
      }
      return DeleteOutcome.deleted;
    } on FileSystemException {
      return DeleteOutcome.failed;
    }
  }

  static bool _isDeletable(
    String target,
    List<String> allowedRoots,
    List<String> protectedPaths,
  ) {
    if (target == '/') return false;
    for (final protected in protectedPaths) {
      if (target == protected || p.isWithin(target, protected)) return false;
    }
    return allowedRoots.any((root) => p.isWithin(root, target));
  }

  static Future<List<String>> _resolveAll(List<String> paths) async => [
    for (final path in paths)
      await Directory(path).resolveSymbolicLinks().catchError((_) => path),
  ];
}
