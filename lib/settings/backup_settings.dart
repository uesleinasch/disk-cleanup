bool _listEquals(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class BackupTarget {
  const BackupTarget({
    required this.id,
    required this.label,
    this.relPath = '',
  });

  final String id;
  final String label;
  final String relPath;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'relPath': relPath,
  };

  factory BackupTarget.fromJson(Map<String, Object?> json) => BackupTarget(
    id: json['id']! as String,
    label: json['label'] as String? ?? '',
    relPath: json['relPath'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is BackupTarget &&
      other.id == id &&
      other.label == label &&
      other.relPath == relPath;

  @override
  int get hashCode => Object.hash(id, label, relPath);
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

bool _mapEquals(
  Map<String, SourceInclusions> a,
  Map<String, SourceInclusions> b,
) =>
    a.length == b.length &&
    a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);

class SourceInclusions {
  const SourceInclusions({this.kinds = const {}, this.paths = const {}});

  final Set<String> kinds;
  final Set<String> paths;

  bool get isEmpty => kinds.isEmpty && paths.isEmpty;

  Map<String, Object?> toJson() => {
    'kinds': kinds.toList()..sort(),
    'paths': paths.toList()..sort(),
  };

  factory SourceInclusions.fromJson(Map<String, Object?> json) =>
      SourceInclusions(
        kinds: {...?(json['kinds'] as List<Object?>?)?.cast<String>()},
        paths: {...?(json['paths'] as List<Object?>?)?.cast<String>()},
      );

  @override
  bool operator ==(Object other) =>
      other is SourceInclusions &&
      _setEquals(other.kinds, kinds) &&
      _setEquals(other.paths, paths);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(kinds),
    Object.hashAllUnordered(paths),
  );
}

class BackupSettings {
  const BackupSettings({
    this.sources = const [],
    this.target,
    this.folderName = 'backup',
    this.browsers,
    this.secretsEnabled = true,
    this.secretItems,
    this.mirror = false,
    this.lastBackupAt,
    this.reminderDays = 7,
    this.autoSyncOnConnect = false,
    this.autoSyncHours = 0,
    this.included = const {},
  });

  final List<String> sources;
  final BackupTarget? target;
  final String folderName;
  final List<String>? browsers;
  final bool secretsEnabled;
  final List<String>? secretItems;
  final bool mirror;
  final DateTime? lastBackupAt;
  final int reminderDays;
  final bool autoSyncOnConnect;
  final int autoSyncHours;
  final Map<String, SourceInclusions> included;

  BackupSettings copyWith({
    List<String>? sources,
    BackupTarget? target,
    String? folderName,
    List<String>? browsers,
    bool? secretsEnabled,
    List<String>? secretItems,
    bool? mirror,
    DateTime? lastBackupAt,
    int? reminderDays,
    bool? autoSyncOnConnect,
    int? autoSyncHours,
    Map<String, SourceInclusions>? included,
    bool clearTarget = false,
  }) => BackupSettings(
    sources: sources ?? this.sources,
    target: clearTarget ? null : target ?? this.target,
    folderName: folderName ?? this.folderName,
    browsers: browsers ?? this.browsers,
    secretsEnabled: secretsEnabled ?? this.secretsEnabled,
    secretItems: secretItems ?? this.secretItems,
    mirror: mirror ?? this.mirror,
    lastBackupAt: lastBackupAt ?? this.lastBackupAt,
    reminderDays: reminderDays ?? this.reminderDays,
    autoSyncOnConnect: autoSyncOnConnect ?? this.autoSyncOnConnect,
    autoSyncHours: autoSyncHours ?? this.autoSyncHours,
    included: included ?? this.included,
  );

  Map<String, Object?> toJson() => {
    'sources': sources,
    'target': target?.toJson(),
    'folderName': folderName,
    'browsers': browsers,
    'secretsEnabled': secretsEnabled,
    'secretItems': secretItems,
    'mirror': mirror,
    'lastBackupAt': lastBackupAt?.toIso8601String(),
    'reminderDays': reminderDays,
    'autoSyncOnConnect': autoSyncOnConnect,
    'autoSyncHours': autoSyncHours,
    'included': {
      for (final MapEntry(:key, :value) in included.entries)
        key: value.toJson(),
    },
  };

  factory BackupSettings.fromJson(Map<String, Object?> json) {
    const d = BackupSettings();
    final target = json['target'] as Map<String, Object?>?;
    final last = json['lastBackupAt'] as String?;
    final included = json['included'] as Map<String, Object?>?;
    return BackupSettings(
      sources: (json['sources'] as List<Object?>?)?.cast<String>() ?? d.sources,
      target: target == null ? null : BackupTarget.fromJson(target),
      folderName: json['folderName'] as String? ?? d.folderName,
      browsers: (json['browsers'] as List<Object?>?)?.cast<String>(),
      secretsEnabled: json['secretsEnabled'] as bool? ?? d.secretsEnabled,
      secretItems: (json['secretItems'] as List<Object?>?)?.cast<String>(),
      mirror: json['mirror'] as bool? ?? d.mirror,
      lastBackupAt: last == null ? null : DateTime.parse(last),
      reminderDays: json['reminderDays'] as int? ?? d.reminderDays,
      autoSyncOnConnect:
          json['autoSyncOnConnect'] as bool? ?? d.autoSyncOnConnect,
      autoSyncHours: json['autoSyncHours'] as int? ?? d.autoSyncHours,
      included: {
        for (final MapEntry(:key, :value) in (included ?? const {}).entries)
          key: SourceInclusions.fromJson(value! as Map<String, Object?>),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackupSettings &&
      _listEquals(other.sources, sources) &&
      other.target == target &&
      other.folderName == folderName &&
      _listEquals(other.browsers, browsers) &&
      other.secretsEnabled == secretsEnabled &&
      _listEquals(other.secretItems, secretItems) &&
      other.mirror == mirror &&
      other.lastBackupAt == lastBackupAt &&
      other.reminderDays == reminderDays &&
      other.autoSyncOnConnect == autoSyncOnConnect &&
      other.autoSyncHours == autoSyncHours &&
      _mapEquals(other.included, included);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(sources),
    target,
    folderName,
    browsers == null ? null : Object.hashAll(browsers!),
    secretsEnabled,
    secretItems == null ? null : Object.hashAll(secretItems!),
    mirror,
    lastBackupAt,
    reminderDays,
    autoSyncOnConnect,
    autoSyncHours,
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in included.entries)
        Object.hash(key, value),
    ]),
  );
}
