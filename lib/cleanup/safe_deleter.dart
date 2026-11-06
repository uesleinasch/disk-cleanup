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
    if (!_isDeletable(target)) return DeleteOutcome.refused;

    try {
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

  bool _isDeletable(String target) {
    if (target == '/') return false;
    for (final protected in _protectedPaths) {
      if (target == protected || p.isWithin(target, protected)) return false;
    }
    return _allowedRoots.any((root) => p.isWithin(root, target));
  }
}
