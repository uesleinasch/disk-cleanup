import 'package:flutter/material.dart';

class BuildRule {
  const BuildRule(this.dirName, this.marker);

  final String dirName;
  final String marker;

  bool matchesMarker(String fileName) {
    if (!marker.contains('*')) return fileName == marker;
    final pattern = marker.split('*').map(RegExp.escape).join('.*');
    return RegExp('^$pattern\$').hasMatch(fileName);
  }

  Map<String, Object?> toJson() => {'dirName': dirName, 'marker': marker};

  factory BuildRule.fromJson(Map<String, Object?> json) =>
      BuildRule(json['dirName']! as String, json['marker']! as String);

  @override
  bool operator ==(Object other) =>
      other is BuildRule && other.dirName == dirName && other.marker == marker;

  @override
  int get hashCode => Object.hash(dirName, marker);
}

const kDefaultBuildRules = <BuildRule>[
  BuildRule('node_modules', 'package.json'),
  BuildRule('.angular', 'angular.json'),
  BuildRule('target', 'Cargo.toml'),
  BuildRule('.stack-work', 'stack.yaml'),
  BuildRule('dist-newstyle', '*.cabal'),
  BuildRule('build', 'pubspec.yaml'),
  BuildRule('build', 'build.gradle'),
  BuildRule('build', 'build.gradle.kts'),
  BuildRule('.dart_tool', 'pubspec.yaml'),
  BuildRule('bin', '*.csproj'),
  BuildRule('obj', '*.csproj'),
];

class WindowBounds {
  const WindowBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.maximized = false,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final bool maximized;

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'maximized': maximized,
  };

  factory WindowBounds.fromJson(Map<String, Object?> json) => WindowBounds(
    x: (json['x']! as num).toDouble(),
    y: (json['y']! as num).toDouble(),
    width: (json['width']! as num).toDouble(),
    height: (json['height']! as num).toDouble(),
    maximized: json['maximized'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is WindowBounds &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.maximized == maximized;

  @override
  int get hashCode => Object.hash(x, y, width, height, maximized);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class Settings {
  const Settings({
    required this.mappedDirs,
    this.warnPercent = 15,
    this.warnBytes = 20000000000,
    this.critPercent = 5,
    this.critBytes = 5000000000,
    this.protectActiveProjects = true,
    this.activeProjectDays = 14,
    this.buildRules = kDefaultBuildRules,
    this.themeMode = ThemeMode.system,
    this.bannerSnoozedUntil,
    this.window,
  });

  factory Settings.defaults(String home) => Settings(mappedDirs: [home]);

  final List<String> mappedDirs;
  final int warnPercent;
  final int warnBytes;
  final int critPercent;
  final int critBytes;
  final bool protectActiveProjects;
  final int activeProjectDays;
  final List<BuildRule> buildRules;
  final ThemeMode themeMode;
  final DateTime? bannerSnoozedUntil;
  final WindowBounds? window;

  Settings copyWith({
    List<String>? mappedDirs,
    int? warnPercent,
    int? warnBytes,
    int? critPercent,
    int? critBytes,
    bool? protectActiveProjects,
    int? activeProjectDays,
    List<BuildRule>? buildRules,
    ThemeMode? themeMode,
    DateTime? bannerSnoozedUntil,
    WindowBounds? window,
  }) => Settings(
    mappedDirs: mappedDirs ?? this.mappedDirs,
    warnPercent: warnPercent ?? this.warnPercent,
    warnBytes: warnBytes ?? this.warnBytes,
    critPercent: critPercent ?? this.critPercent,
    critBytes: critBytes ?? this.critBytes,
    protectActiveProjects: protectActiveProjects ?? this.protectActiveProjects,
    activeProjectDays: activeProjectDays ?? this.activeProjectDays,
    buildRules: buildRules ?? this.buildRules,
    themeMode: themeMode ?? this.themeMode,
    bannerSnoozedUntil: bannerSnoozedUntil ?? this.bannerSnoozedUntil,
    window: window ?? this.window,
  );

  Map<String, Object?> toJson() => {
    'mappedDirs': mappedDirs,
    'warnPercent': warnPercent,
    'warnBytes': warnBytes,
    'critPercent': critPercent,
    'critBytes': critBytes,
    'protectActiveProjects': protectActiveProjects,
    'activeProjectDays': activeProjectDays,
    'buildRules': [for (final r in buildRules) r.toJson()],
    'themeMode': themeMode.name,
    'bannerSnoozedUntil': bannerSnoozedUntil?.toIso8601String(),
    'window': window?.toJson(),
  };

  factory Settings.fromJson(Map<String, Object?> json, String home) {
    final defaults = Settings.defaults(home);
    final snoozed = json['bannerSnoozedUntil'] as String?;
    final window = json['window'] as Map<String, Object?>?;
    final rules = json['buildRules'] as List<Object?>?;
    final dirs = json['mappedDirs'] as List<Object?>?;
    return Settings(
      mappedDirs: dirs == null ? defaults.mappedDirs : dirs.cast<String>(),
      warnPercent: json['warnPercent'] as int? ?? defaults.warnPercent,
      warnBytes: json['warnBytes'] as int? ?? defaults.warnBytes,
      critPercent: json['critPercent'] as int? ?? defaults.critPercent,
      critBytes: json['critBytes'] as int? ?? defaults.critBytes,
      protectActiveProjects:
          json['protectActiveProjects'] as bool? ??
          defaults.protectActiveProjects,
      activeProjectDays:
          json['activeProjectDays'] as int? ?? defaults.activeProjectDays,
      buildRules: rules == null
          ? defaults.buildRules
          : [
              for (final r in rules)
                BuildRule.fromJson((r! as Map).cast<String, Object?>()),
            ],
      themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ??
          defaults.themeMode,
      bannerSnoozedUntil: snoozed == null ? null : DateTime.parse(snoozed),
      window: window == null ? null : WindowBounds.fromJson(window),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      _listEquals(other.mappedDirs, mappedDirs) &&
      other.warnPercent == warnPercent &&
      other.warnBytes == warnBytes &&
      other.critPercent == critPercent &&
      other.critBytes == critBytes &&
      other.protectActiveProjects == protectActiveProjects &&
      other.activeProjectDays == activeProjectDays &&
      _listEquals(other.buildRules, buildRules) &&
      other.themeMode == themeMode &&
      other.bannerSnoozedUntil == bannerSnoozedUntil &&
      other.window == window;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(mappedDirs),
    warnPercent,
    warnBytes,
    critPercent,
    critBytes,
    protectActiveProjects,
    activeProjectDays,
    Object.hashAll(buildRules),
    themeMode,
    bannerSnoozedUntil,
    window,
  );
}
