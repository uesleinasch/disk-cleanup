const _systemRoots = <String>[
  '/bin',
  '/boot',
  '/dev',
  '/etc',
  '/lib',
  '/lib32',
  '/lib64',
  '/libx32',
  '/opt',
  '/proc',
  '/root',
  '/run',
  '/sbin',
  '/snap',
  '/srv',
  '/sys',
  '/tmp',
  '/usr',
  '/var',
];

String _normalize(String path) {
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return '/${parts.join('/')}';
}

bool _isWithin(String path, String root) =>
    path == root || path.startsWith('$root/');

bool isForbiddenMappedDir(String path, {required String home}) {
  if (path.trim().isEmpty || !path.startsWith('/')) return true;
  final p = _normalize(path);
  if (p == '/') return true;
  final h = _normalize(home);
  if (h != '/' && p != h && _isWithin(h, p)) return true;
  if (h != '/' && _isWithin(p, h)) return false;
  if (_isWithin(p, '/run/media') && p != '/run/media') return false;
  for (final root in _systemRoots) {
    if (_isWithin(p, root)) return true;
  }
  return false;
}

List<String> allowedMappedDirs(Iterable<String> dirs, {required String home}) =>
    [
      for (final d in dirs)
        if (!isForbiddenMappedDir(d, home: home)) d,
    ];
