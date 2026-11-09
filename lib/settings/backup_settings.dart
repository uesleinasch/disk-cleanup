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
  };

  factory BackupSettings.fromJson(Map<String, Object?> json) {
    const d = BackupSettings();
    final target = json['target'] as Map<String, Object?>?;
    final last = json['lastBackupAt'] as String?;
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
      other.reminderDays == reminderDays;

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
  );
}
