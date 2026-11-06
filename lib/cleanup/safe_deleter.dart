import 'dart:io';

import 'package:path/path.dart' as p;

enum DeleteOutcome { deleted, missing, refused, failed }

class SafeDeleter {
  SafeDeleter({
    required List<String> allowedRoots,
    required List<String> protectedPaths,
  }) : _allowedRoots = allowedRoots.map(p.normalize).toList(),
       _protectedPaths = protectedPaths.map(p.normalize).toList();

  final List<String> _allowedRoots;
  final List<String> _protectedPaths;

  Future<DeleteOutcome> delete(String path) async {
    if (!p.isAbsolute(path)) return DeleteOutcome.refused;
    final target = p.normalize(p.absolute(path));
    if (!_isDeletable(target, _allowedRoots, _protectedPaths)) {
      return DeleteOutcome.refused;
    }

    try {
      final String realParent;
      try {
        realParent = await Directory(p.dirname(target)).resolveSymbolicLinks();
      } on FileSystemException {
        return DeleteOutcome.missing;
      }
      final realTarget = p.join(realParent, p.basename(target));
      if (!_isDeletable(
        realTarget,
        await _resolveAll(_allowedRoots),
        await _resolveAll(_protectedPaths),
      )) {
        return DeleteOutcome.refused;
      }

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
