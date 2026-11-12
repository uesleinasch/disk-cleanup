import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/process_runner.dart';
import '../settings/backup_settings.dart';

const kBackupFsTypes = {
  'ext2',
  'ext3',
  'ext4',
  'btrfs',
  'xfs',
  'f2fs',
  'zfs',
  'nfs',
  'nfs4',
};

String? backupFsProblem(String? fsType) {
  if (fsType != null && kBackupFsTypes.contains(fsType)) return null;
  final name = switch (fsType) {
    'vfat' || 'msdos' => 'FAT32',
    'exfat' => 'exFAT',
    'ntfs' || 'ntfs3' || 'fuseblk' => 'NTFS',
    _ => null,
  };
  if (name == null) {
    return 'O sistema de arquivos deste disco (${fsType ?? 'desconhecido'}) '
        'não é suportado. Use um disco em ext4.';
  }
  return 'Este disco usa $name, que não guarda permissões nem links. '
      'Os projetos voltariam quebrados. Formate em ext4 para usar no backup.';
}

int? _int(Object? v) => switch (v) {
  int() => v,
  String() => int.tryParse(v),
  _ => null,
};

bool _bool(Object? v) => v == true || v == 1 || v == '1';

String? _text(Object? v) => v is String && v.isNotEmpty ? v : null;

class DiskTarget {
  const DiskTarget({
    required this.device,
    required this.mountPoint,
    this.label,
    this.uuid,
    this.fsType,
    this.hotplug = false,
    this.size = 0,
    this.available = 0,
  });

  final String device;
  final String mountPoint;
  final String? label;
  final String? uuid;
  final String? fsType;
  final bool hotplug;
  final int size;
  final int available;

  String get name => label ?? p.basename(mountPoint);

  String? get problem => backupFsProblem(fsType);
}

List<DiskTarget> parseLsblk(String json) {
  final targets = <DiskTarget>[];
  void visit(Object? node) {
    if (node is! Map) return;
    final device = _text(node['name']) ?? '';
    final mount = _text(node['mountpoint']);
    if (mount != null && _isCandidate(device, mount)) {
      targets.add(
        DiskTarget(
          device: device,
          mountPoint: mount,
          label: _text(node['label']),
          uuid: _text(node['uuid']),
          fsType: _text(node['fstype']),
          hotplug: _bool(node['hotplug']),
          size: _int(node['size']) ?? 0,
          available: _int(node['fsavail']) ?? 0,
        ),
      );
    }
    for (final child in (node['children'] as List<Object?>?) ?? const []) {
      visit(child);
    }
  }

  final root = jsonDecode(json);
  if (root is Map) {
    for (final node in (root['blockdevices'] as List<Object?>?) ?? const []) {
      visit(node);
    }
  }
  targets.sort((a, b) {
    if (a.hotplug != b.hotplug) return a.hotplug ? -1 : 1;
    return a.mountPoint.compareTo(b.mountPoint);
  });
  return targets;
}

bool _isCandidate(String device, String mount) =>
    mount.startsWith('/') &&
    mount != '/' &&
    !mount.startsWith('/boot') &&
    !mount.startsWith('/snap/') &&
    !device.contains('/loop');

class MountInfo {
  const MountInfo({
    required this.target,
    required this.source,
    this.fsType,
    this.uuid,
    this.label,
    this.available = 0,
    this.fsRoot,
  });

  final String target;
  final String source;
  final String? fsType;
  final String? uuid;
  final String? label;
  final int available;
  final String? fsRoot;

  String get id => uuid ?? source;
}

List<MountInfo> parseFindmnt(String json) {
  final root = jsonDecode(json);
  if (root is! Map) return [];
  return [
    for (final fs in (root['filesystems'] as List<Object?>?) ?? const [])
      if (fs is Map && _text(fs['target']) != null)
        MountInfo(
          target: fs['target'] as String,
          source: _text(fs['source']) ?? '',
          fsType: _text(fs['fstype']),
          uuid: _text(fs['uuid']),
          label: _text(fs['label']),
          available: _int(fs['avail']) ?? 0,
          fsRoot: _text(fs['fsroot']),
        ),
  ];
}

const _findmntColumns = 'TARGET,SOURCE,FSTYPE,UUID,LABEL,AVAIL';
const _findmntRootColumns = '$_findmntColumns,FSROOT';

class DiskTargets {
  DiskTargets(this._runner);

  final ProcessRunner _runner;

  Future<List<DiskTarget>> list() async {
    final r = await _runner.run('lsblk', const [
      '-J',
      '-b',
      '-p',
      '-o',
      'NAME,LABEL,UUID,FSTYPE,HOTPLUG,SIZE,FSAVAIL,MOUNTPOINT',
    ]);
    if (r.exitCode != 0) return [];
    return parseLsblk(r.stdoutText);
  }

  Future<MountInfo?> mountOf(String path) => _mountOf(path, _findmntColumns);

  Future<MountInfo?> _mountOf(String path, String columns) async {
    final r = await _runner.run('findmnt', [
      '-J',
      '-b',
      '--list',
      '-o',
      columns,
      '-T',
      path,
    ]);
    if (r.exitCode != 0) return null;
    return parseFindmnt(r.stdoutText).firstOrNull;
  }

  Future<BackupTarget?> targetFor(String dir) async {
    final mount = await _mountOf(dir, _findmntRootColumns);
    if (mount == null) return null;
    final rel = p.relative(p.normalize(dir), from: mount.target);
    return BackupTarget(
      id: mount.id,
      label: mount.label ?? p.basename(mount.target),
      relPath: rel == '.' ? '' : rel,
      fsRoot: mount.fsRoot ?? '/',
      mountPoint: mount.target,
    );
  }

  Future<String?> resolve(BackupTarget target) async {
    final r = await _runner.run('findmnt', const [
      '-J',
      '-b',
      '--list',
      '-o',
      _findmntRootColumns,
    ]);
    if (r.exitCode != 0) return null;
    final mounts = [
      for (final m in parseFindmnt(r.stdoutText))
        if (m.id == target.id) m,
    ];
    String withRel(String base) =>
        target.relPath.isEmpty ? base : p.join(base, target.relPath);
    final root = target.fsRoot;
    if (root == null) {
      final bases = [for (final m in mounts) m.target];
      final existing = bases.where((b) => Directory(withRel(b)).existsSync());
      final base = existing.firstOrNull ?? bases.firstOrNull;
      return base == null ? null : withRel(base);
    }
    String? best;
    var bestDepth = -1;
    var bestSameMount = false;
    for (final m in mounts) {
      final mountRoot = m.fsRoot ?? '/';
      if (mountRoot != root && !p.isWithin(mountRoot, root)) continue;
      final base = mountRoot == root
          ? m.target
          : p.join(m.target, p.relative(root, from: mountRoot));
      final depth = p.split(mountRoot).length;
      final sameMount = m.target == target.mountPoint;
      if (depth > bestDepth ||
          (depth == bestDepth && sameMount && !bestSameMount)) {
        best = base;
        bestDepth = depth;
        bestSameMount = sameMount;
      }
    }
    return best == null ? null : withRel(best);
  }

  Future<bool> isWritable(String dir) async {
    final probe = File(p.join(dir, '.disk-cleanup-$pid'));
    try {
      await probe.writeAsString('');
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> flush(String dir) => _runner.run('sync', ['-f', dir]);
}
