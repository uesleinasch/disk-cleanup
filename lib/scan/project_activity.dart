import 'dart:io';

import 'package:path/path.dart' as p;

const kPrunedProjectDirs = <String>{
  '.git',
  'node_modules',
  'target',
  'build',
  'dist',
  '.gradle',
  '.dart_tool',
  '.angular',
  '.stack-work',
  'dist-newstyle',
  '.next',
  '.nuxt',
  '.cache',
  '.venv',
  'venv',
  '__pycache__',
  '.tox',
  '.mypy_cache',
  '.pytest_cache',
};

const kMaxProjectEntries = 20000;

Set<String>? _mountPointsCache;

Set<String> _mountPoints() => _mountPointsCache ??= _readMountPoints();

Set<String> _readMountPoints() {
  try {
    return {
      for (final line in File('/proc/self/mounts').readAsLinesSync())
        if (line.split(' ') case [_, final mp, ...]) _unescapeMount(mp),
    };
  } on FileSystemException {
    return const {};
  }
}

String _unescapeMount(String s) => s.replaceAllMapped(
  RegExp(r'\\([0-7]{3})'),
  (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)),
);

DateTime? newestProjectModification(
  String projectDir, {
  Iterable<String> extraPruned = const [],
  int maxEntries = kMaxProjectEntries,
  Set<String>? mountPoints,
}) {
  final pruned = {...kPrunedProjectDirs, ...extraPruned};
  final mounts = mountPoints ?? _mountPoints();
  final root = p.normalize(projectDir);
  DateTime? newest;
  void consider(DateTime m) {
    if (newest == null || m.isAfter(newest!)) newest = m;
  }

  for (final name in const ['index', 'HEAD']) {
    final stat = FileStat.statSync(p.join(root, '.git', name));
    if (stat.type != FileSystemEntityType.notFound) consider(stat.modified);
  }

  final pending = <String>[root];
  var seen = 0;
  while (pending.isNotEmpty && seen < maxEntries) {
    final dir = pending.removeLast();
    final List<FileSystemEntity> children;
    try {
      children = Directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      if (dir == root) return null;
      continue;
    }
    for (final e in children) {
      if (++seen > maxEntries) break;
      if (e is Link) continue;
      if (e is Directory && pruned.contains(p.basename(e.path))) continue;
      try {
        consider(e.statSync().modified);
      } on FileSystemException {
        continue;
      }
      if (e is Directory && !mounts.contains(p.normalize(e.path))) {
        pending.add(e.path);
      }
    }
  }
  return newest;
}
