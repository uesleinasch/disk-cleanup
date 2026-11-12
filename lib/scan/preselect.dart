import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../core/models.dart';
import '../disk/alert.dart';
import '../disk/disk_info.dart';
import '../settings/settings.dart';
import 'build_finder.dart';
import 'du_scanner.dart';

enum ConsumerKind { directory, file, docker, system }

class Consumer {
  const Consumer({
    required this.label,
    required this.path,
    required this.bytes,
    required this.kind,
  });

  final String label;
  final String path;
  final int bytes;
  final ConsumerKind kind;

  Map<String, Object?> toJson() => {
    'label': label,
    'path': path,
    'bytes': bytes,
    'kind': kind.name,
  };

  factory Consumer.fromJson(Map<String, Object?> j) => Consumer(
    label: j['label'] as String,
    path: j['path'] as String,
    bytes: j['bytes'] as int,
    kind: ConsumerKind.values.byName(j['kind'] as String),
  );
}

bool shouldPreselect(
  CleanupItem item,
  Settings s,
  DateTime now, {
  bool appRunning = false,
}) {
  if (item.risk != RiskLevel.safe || item.requiresRoot || appRunning) {
    return false;
  }
  if (item.category == CleanupCategory.build && s.protectActiveProjects) {
    final modified = item.lastModified;
    if (modified == null) return false;
    return now.difference(modified) > Duration(days: s.activeProjectDays);
  }
  return true;
}

List<Consumer> composeConsumers({
  required String home,
  required Map<String, DuResult> mapped,
  int? dockerBytes,
  Map<String, int> systemDirs = const {},
}) {
  final byPath = <String, Consumer>{};
  void add(Consumer c) {
    final key = p.normalize(c.path);
    final existing = byPath[key];
    if (existing == null || existing.bytes < c.bytes) byPath[key] = c;
  }

  final normalizedHome = p.normalize(home);
  for (final entry in mapped.entries) {
    final dir = p.normalize(entry.key);
    if (dir == normalizedHome) {
      for (final child in entry.value.entries) {
        add(
          Consumer(
            label: p.basename(child.path),
            path: child.path,
            bytes: child.bytes,
            kind: ConsumerKind.directory,
          ),
        );
      }
    } else if (!entry.value.totalUnknown && !entry.value.permissionDenied) {
      add(
        Consumer(
          label: p.basename(dir),
          path: dir,
          bytes: entry.value.total,
          kind: ConsumerKind.directory,
        ),
      );
    }
  }
  for (final entry in systemDirs.entries) {
    add(
      Consumer(
        label: entry.key,
        path: entry.key,
        bytes: entry.value,
        kind: ConsumerKind.system,
      ),
    );
  }
  if (dockerBytes != null && dockerBytes > 0) {
    add(
      Consumer(
        label: 'Docker',
        path: '/var/lib/docker',
        bytes: dockerBytes,
        kind: ConsumerKind.docker,
      ),
    );
  }
  final result = byPath.values.toList()
    ..sort((a, b) => b.bytes.compareTo(a.bytes));
  return result;
}

AlertLevel worstAlert(
  List<VolumeUsage> volumes,
  List<String> mappedDirs,
  Settings s,
) {
  final relevant = <VolumeUsage>{};
  for (final v in volumes) {
    if (v.mountPoint == '/') relevant.add(v);
  }
  for (final dir in mappedDirs) {
    VolumeUsage? best;
    for (final v in volumes) {
      final mp = v.mountPoint;
      final contains = mp == '/' || dir == mp || dir.startsWith('$mp/');
      if (contains && (best == null || mp.length > best.mountPoint.length)) {
        best = v;
      }
    }
    if (best != null) relevant.add(best);
  }
  var worst = AlertLevel.ok;
  for (final v in relevant) {
    final level = evaluateAlert(v, s);
    if (level.index > worst.index) worst = level;
  }
  return worst;
}

CleanupItem buildItem(BuildArtifact a, DateTime now) => CleanupItem(
  id: 'build:${a.path}',
  category: CleanupCategory.build,
  title: '${a.rule.dirName} · ${p.basename(a.projectDir)}',
  path: a.path,
  note: 'Projeto modificado ${formatAgo(a.projectModified, now)}',
  bytes: a.bytes,
  risk: RiskLevel.safe,
  requiresRoot: false,
  preselected: false,
  lastModified: a.projectModified,
  action: DeletePathsAction([a.path]),
);

CleanupItem withPreselected(CleanupItem i, bool value) => CleanupItem(
  id: i.id,
  category: i.category,
  title: i.title,
  path: i.path,
  note: i.note,
  bytes: i.bytes,
  risk: i.risk,
  requiresRoot: i.requiresRoot,
  preselected: value,
  lastModified: i.lastModified,
  action: i.action,
  sizeUnknown: i.sizeUnknown,
);
