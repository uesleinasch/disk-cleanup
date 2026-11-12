import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'backup_planner.dart';
import 'restore_planner.dart';

enum PendingKind { diskNewer, wouldDelete }

class PendingItem {
  const PendingItem({
    required this.kind,
    required this.source,
    required this.rel,
    this.isDir = false,
    this.localSize,
    this.localModified,
    this.diskSize,
    this.diskModified,
  });

  final PendingKind kind;
  final String source;
  final String rel;
  final bool isDir;
  final int? localSize;
  final DateTime? localModified;
  final int? diskSize;
  final DateTime? diskModified;

  String get key => '$source/$rel';

  String get rule => '- /${rsyncLiteral(key)}${isDir ? '/' : ''}';

  RestoreConflict asConflict() => RestoreConflict(
    path: key,
    localSize: localSize,
    localModified: localModified,
    backupSize: diskSize,
    backupModified: diskModified,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'source': source,
    'rel': rel,
    if (isDir) 'isDir': true,
    'localSize': localSize,
    'localModified': localModified?.toIso8601String(),
    'diskSize': diskSize,
    'diskModified': diskModified?.toIso8601String(),
  };

  factory PendingItem.fromJson(Map<String, Object?> json) => PendingItem(
    kind: PendingKind.values.byName(json['kind'] as String),
    source: json['source'] as String,
    rel: json['rel'] as String,
    isDir: json['isDir'] as bool? ?? false,
    localSize: json['localSize'] as int?,
    localModified: DateTime.tryParse(json['localModified'] as String? ?? ''),
    diskSize: json['diskSize'] as int?,
    diskModified: DateTime.tryParse(json['diskModified'] as String? ?? ''),
  );
}

class PendingState {
  const PendingState({this.items = const [], this.keepOnDisk = const {}});

  final List<PendingItem> items;
  final Set<String> keepOnDisk;
}

class PendingStore {
  PendingStore(this.path);

  final String path;

  Future<Map<String, Object?>> _readAll() async {
    final f = File(path);
    if (!f.existsSync()) return {};
    try {
      final json = jsonDecode(await f.readAsString());
      return json is Map ? json.cast<String, Object?>() : {};
    } on FormatException {
      return {};
    }
  }

  Future<PendingState> load(String targetId) async {
    final entry = (await _readAll())[targetId];
    if (entry is! Map) return const PendingState();
    return PendingState(
      items: [
        for (final i in entry['items'] as List? ?? const [])
          PendingItem.fromJson((i as Map).cast<String, Object?>()),
      ],
      keepOnDisk: {
        for (final k in entry['keepOnDisk'] as List? ?? const []) k as String,
      },
    );
  }

  static final _queues = <String, Future<void>>{};

  Future<void> save(String targetId, PendingState state) {
    final previous = _queues[path] ?? Future<void>.value();
    final next = previous.then((_) => _save(targetId, state));
    final settled = next.then<void>((_) {}, onError: (Object _) {});
    _queues[path] = settled;
    settled.then((_) {
      if (identical(_queues[path], settled)) _queues.remove(path);
    });
    return next;
  }

  Future<void> _save(String targetId, PendingState state) async {
    final all = await _readAll();
    all[targetId] = {
      'items': [for (final i in state.items) i.toJson()],
      'keepOnDisk': state.keepOnDisk.toList()..sort(),
    };
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(all),
      flush: true,
    );
    await tmp.rename(path);
  }
}

/// O primeiro trecho de cada caminho do rsync é o basename da origem,
/// que é também o nome da pasta dela dentro de [backupDir].
Future<List<PendingItem>> classifySyncChanges({
  required Iterable<ItemizeEntry> entries,
  required List<String> sources,
  required String backupDir,
}) async {
  final byName = {for (final s in sources) p.basename(s): s};
  final out = <PendingItem>[];
  for (final e in entries) {
    final slash = e.path.indexOf('/');
    if (slash <= 0) continue;
    final name = e.path.substring(0, slash);
    final rel = e.path.substring(slash + 1);
    final source = byName[name];
    if (source == null || rel.isEmpty) continue;
    final disk = FileStat.statSync(p.join(backupDir, e.path));
    final onDisk = disk.type != FileSystemEntityType.notFound;
    switch (e.kind) {
      case ItemizeKind.created:
        break;
      case ItemizeKind.changed:
        if (e.isLink) continue;
        final localPath = p.join(source, rel);
        final local = FileStat.statSync(localPath);
        if (!disk.modified.isAfter(local.modified)) continue;
        if (await sameFileContent(localPath, p.join(backupDir, e.path))) {
          continue;
        }
        out.add(
          PendingItem(
            kind: PendingKind.diskNewer,
            source: name,
            rel: rel,
            localSize: local.size,
            localModified: local.modified,
            diskSize: disk.size,
            diskModified: disk.modified,
          ),
        );
      case ItemizeKind.deleting:
        out.add(
          PendingItem(
            kind: PendingKind.wouldDelete,
            source: name,
            rel: rel,
            isDir: e.isDir,
            diskSize: onDisk && !e.isDir ? disk.size : null,
            diskModified: onDisk ? disk.modified : null,
          ),
        );
    }
  }
  final deletedDirs = [
    for (final i in out)
      if (i.kind == PendingKind.wouldDelete && i.isDir) i.key,
  ];
  return [
    for (final i in out)
      if (!deletedDirs.any((d) => p.isWithin(d, i.key))) i,
  ];
}
