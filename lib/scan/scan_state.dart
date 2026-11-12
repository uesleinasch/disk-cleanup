import '../cleanup/docker_service.dart';
import '../core/models.dart';
import '../disk/alert.dart';
import '../disk/disk_info.dart';
import 'du_scanner.dart';
import 'large_files.dart';
import 'preselect.dart';

class ScanProgressInfo {
  const ScanProgressInfo({
    this.currentDir = '',
    this.doneDirs = 0,
    this.totalDirs = 0,
    this.running = false,
  });

  final String currentDir;
  final int doneDirs;
  final int totalDirs;
  final bool running;
}

class ScanState {
  const ScanState({
    this.updatedAt,
    this.volumes = const [],
    this.alert = AlertLevel.ok,
    this.consumers = const [],
    this.mappedDirs = const {},
    this.weeklyDeltas = const {},
    this.lockedDirs = const {},
    this.items = const [],
    this.docker,
    this.largeFiles = const [],
    this.progress = const ScanProgressInfo(),
  });

  final DateTime? updatedAt;
  final List<VolumeUsage> volumes;
  final AlertLevel alert;
  final List<Consumer> consumers;
  final Map<String, DuResult> mappedDirs;
  final Map<String, int?> weeklyDeltas;
  final Set<String> lockedDirs;
  final List<CleanupItem> items;
  final DockerInventory? docker;
  final List<LargeFile> largeFiles;
  final ScanProgressInfo progress;

  VolumeUsage? get systemVolume {
    for (final v in volumes) {
      if (v.mountPoint == '/') return v;
    }
    return null;
  }

  int get safeReclaimableBytes =>
      items.where((i) => i.preselected).fold(0, (a, i) => a + i.bytes);

  int get recoverableBytes => items
      .where((i) => i.risk != RiskLevel.danger)
      .fold(0, (a, i) => a + i.bytes);

  ScanState copyWith({
    ScanProgressInfo? progress,
    List<CleanupItem>? items,
    DockerInventory? docker,
    Set<String>? lockedDirs,
    Map<String, DuResult>? mappedDirs,
    List<Consumer>? consumers,
  }) => ScanState(
    updatedAt: updatedAt,
    volumes: volumes,
    alert: alert,
    consumers: consumers ?? this.consumers,
    mappedDirs: mappedDirs ?? this.mappedDirs,
    weeklyDeltas: weeklyDeltas,
    lockedDirs: lockedDirs ?? this.lockedDirs,
    items: items ?? this.items,
    docker: docker ?? this.docker,
    largeFiles: largeFiles,
    progress: progress ?? this.progress,
  );

  Map<String, Object?> toJson() => {
    'updatedAt': updatedAt?.toIso8601String(),
    'volumes': [for (final v in volumes) _volumeToJson(v)],
    'alert': alert.name,
    'consumers': [for (final c in consumers) c.toJson()],
    'mappedDirs': {
      for (final e in mappedDirs.entries) e.key: _duToJson(e.value),
    },
    'weeklyDeltas': weeklyDeltas,
    'lockedDirs': lockedDirs.toList(),
    'items': [for (final i in items) i.toJson()],
    'docker': docker == null ? null : _dockerToJson(docker!),
    'largeFiles': [for (final f in largeFiles) _largeFileToJson(f)],
  };

  factory ScanState.fromJson(Map<String, Object?> json) {
    List<Map<String, Object?>> maps(Object? v) => [
      for (final e in (v as List? ?? const []))
        Map<String, Object?>.from(e as Map),
    ];
    final updated = json['updatedAt'] as String?;
    final docker = json['docker'];
    return ScanState(
      updatedAt: updated == null ? null : DateTime.parse(updated),
      volumes: maps(json['volumes']).map(_volumeFromJson).toList(),
      alert: AlertLevel.values.byName(json['alert'] as String? ?? 'ok'),
      consumers: maps(json['consumers']).map(Consumer.fromJson).toList(),
      mappedDirs: {
        for (final e in (json['mappedDirs'] as Map? ?? const {}).entries)
          e.key as String: _duFromJson(
            Map<String, Object?>.from(e.value as Map),
          ),
      },
      weeklyDeltas: {
        for (final e in (json['weeklyDeltas'] as Map? ?? const {}).entries)
          e.key as String: e.value as int?,
      },
      lockedDirs: {
        for (final d in (json['lockedDirs'] as List? ?? const [])) d as String,
      },
      items: maps(json['items']).map(CleanupItem.fromJson).toList(),
      docker: docker == null
          ? null
          : _dockerFromJson(Map<String, Object?>.from(docker as Map)),
      largeFiles: maps(json['largeFiles']).map(_largeFileFromJson).toList(),
    );
  }
}

Map<String, Object?> _volumeToJson(VolumeUsage v) => {
  'device': v.device,
  'fsType': v.fsType,
  'mountPoint': v.mountPoint,
  'size': v.size,
  'used': v.used,
  'available': v.available,
};

VolumeUsage _volumeFromJson(Map<String, Object?> j) => VolumeUsage(
  device: j['device'] as String,
  fsType: j['fsType'] as String,
  mountPoint: j['mountPoint'] as String,
  size: j['size'] as int,
  used: j['used'] as int,
  available: j['available'] as int,
);

Map<String, Object?> _duToJson(DuResult r) => {
  'entries': [
    for (final e in r.entries) {'path': e.path, 'bytes': e.bytes},
  ],
  'total': r.total,
  'errors': r.errors,
  'permissionDenied': r.permissionDenied,
  'totalUnknown': r.totalUnknown,
};

DuResult _duFromJson(Map<String, Object?> j) => DuResult(
  entries: [
    for (final e in (j['entries'] as List))
      DirEntrySize((e as Map)['path'] as String, e['bytes'] as int),
  ],
  total: j['total'] as int,
  errors: j['errors'] as int,
  permissionDenied: j['permissionDenied'] as bool,
  totalUnknown: j['totalUnknown'] as bool? ?? false,
);

Map<String, Object?> _largeFileToJson(LargeFile f) => {
  'path': f.path,
  'bytes': f.bytes,
  'lastAccess': f.lastAccess.toIso8601String(),
  'modified': f.modified.toIso8601String(),
};

LargeFile _largeFileFromJson(Map<String, Object?> j) => LargeFile(
  path: j['path'] as String,
  bytes: j['bytes'] as int,
  lastAccess: DateTime.parse(j['lastAccess'] as String),
  modified: DateTime.parse(j['modified'] as String),
);

Map<String, Object?> _dockerToJson(DockerInventory d) => {
  'available': d.available,
  'needsRoot': d.needsRoot,
  'imagesBytes': d.imagesBytes,
  'containersBytes': d.containersBytes,
  'volumesBytes': d.volumesBytes,
  'buildCacheBytes': d.buildCacheBytes,
  'buildCacheReclaimable': d.buildCacheReclaimable,
  'stopped': [
    for (final c in d.stopped)
      {
        'id': c.id,
        'name': c.name,
        'image': c.image,
        'status': c.status,
        'bytes': c.bytes,
      },
  ],
  'unusedImages': [
    for (final i in d.unusedImages)
      {'id': i.id, 'repoTag': i.repoTag, 'bytes': i.bytes},
  ],
  'unusedVolumes': [
    for (final v in d.unusedVolumes) {'name': v.name, 'bytes': v.bytes},
  ],
};

DockerInventory _dockerFromJson(Map<String, Object?> j) {
  List<Map> list(String k) => (j[k] as List? ?? const []).cast<Map>();
  return DockerInventory(
    available: j['available'] as bool,
    needsRoot: j['needsRoot'] as bool,
    imagesBytes: j['imagesBytes'] as int,
    containersBytes: j['containersBytes'] as int,
    volumesBytes: j['volumesBytes'] as int,
    buildCacheBytes: j['buildCacheBytes'] as int,
    buildCacheReclaimable: j['buildCacheReclaimable'] as int,
    stopped: [
      for (final c in list('stopped'))
        DockerContainer(
          id: c['id'] as String,
          name: c['name'] as String,
          image: c['image'] as String,
          status: c['status'] as String,
          bytes: c['bytes'] as int,
        ),
    ],
    unusedImages: [
      for (final i in list('unusedImages'))
        DockerImage(
          id: i['id'] as String,
          repoTag: i['repoTag'] as String,
          bytes: i['bytes'] as int,
        ),
    ],
    unusedVolumes: [
      for (final v in list('unusedVolumes'))
        DockerVolume(name: v['name'] as String, bytes: v['bytes'] as int),
    ],
  );
}
