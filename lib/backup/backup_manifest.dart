import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'browser_profiles.dart';

const kManifestName = '.disk-cleanup-manifest.json';

final _secretsFile = RegExp(r'^secrets-\d{4}-\d{2}-\d{2}\.tar\.gz\.gpg$');

bool isSafePathSegment(String name) =>
    name.isNotEmpty &&
    name != '.' &&
    name != '..' &&
    !name.contains('/') &&
    !name.contains('\x00');

class ManifestSource {
  const ManifestSource({required this.path, required this.name});

  final String path;
  final String name;

  Map<String, dynamic> toJson() => {'path': path, 'name': name};

  factory ManifestSource.fromJson(Map<String, dynamic> json) => ManifestSource(
    path: json['path'] as String,
    name: json['name'] as String,
  );
}

class ManifestBrowser {
  const ManifestBrowser({
    required this.id,
    required this.label,
    required this.profilePath,
  });

  final String id;
  final String label;
  final String profilePath;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'profilePath': profilePath,
  };

  factory ManifestBrowser.fromJson(Map<String, dynamic> json) =>
      ManifestBrowser(
        id: json['id'] as String,
        label: json['label'] as String,
        profilePath: json['profilePath'] as String,
      );
}

class BackupManifest {
  const BackupManifest({
    this.version = 1,
    required this.date,
    required this.hostname,
    required this.home,
    required this.folderName,
    required this.sources,
    required this.browsers,
    this.fromManifest = true,
  });

  final int version;
  final DateTime? date;
  final String? hostname;
  final String? home;
  final String folderName;
  final List<ManifestSource> sources;
  final List<ManifestBrowser> browsers;
  final bool fromManifest;

  Map<String, dynamic> toJson() => {
    'version': version,
    'date': date?.toIso8601String(),
    'hostname': hostname,
    'home': home,
    'folderName': folderName,
    'sources': [for (final s in sources) s.toJson()],
    'browsers': [for (final b in browsers) b.toJson()],
  };

  factory BackupManifest.fromJson(Map<String, dynamic> json) => BackupManifest(
    version: json['version'] as int? ?? 1,
    date: DateTime.tryParse(json['date'] as String? ?? ''),
    hostname: json['hostname'] as String?,
    home: json['home'] as String?,
    folderName: json['folderName'] as String,
    sources: [
      for (final s in json['sources'] as List? ?? const [])
        ManifestSource.fromJson((s as Map).cast<String, dynamic>()),
    ].where((s) => isSafePathSegment(s.name)).toList(),
    browsers: [
      for (final b in json['browsers'] as List? ?? const [])
        ManifestBrowser.fromJson((b as Map).cast<String, dynamic>()),
    ].where(_knownBrowser).toList(),
  );

  static bool _knownBrowser(ManifestBrowser b) =>
      isSafePathSegment(b.label) &&
      kBrowserCatalog.any((spec) => spec.id == b.id);

  static Future<void> write(String backupDir, BackupManifest manifest) async {
    final file = File(p.join(backupDir, kManifestName));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// [knownSources] cobre backups feitos antes do manifesto: cada pasta
  /// do backup é casada pelo basename com as fontes configuradas.
  static Future<BackupManifest?> load(
    String backupDir, {
    List<String> knownSources = const [],
    String? home,
  }) async {
    final dir = Directory(backupDir);
    if (!dir.existsSync()) return null;
    final file = File(p.join(backupDir, kManifestName));
    if (file.existsSync()) {
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          return BackupManifest.fromJson(json.cast<String, dynamic>());
        }
      } on FormatException {
        // Manifesto corrompido: cai no modo sem manifesto.
      } on TypeError {
        // Manifesto com campos de tipo errado: cai no modo sem manifesto.
      }
    }
    final byName = {for (final s in knownSources) p.basename(s): s};
    final sources = <ManifestSource>[];
    final browsers = <ManifestBrowser>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! Directory) continue;
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (name == kBrowserFolder) continue;
      sources.add(ManifestSource(path: byName[name] ?? '', name: name));
    }
    final browserDir = Directory(p.join(backupDir, kBrowserFolder));
    if (browserDir.existsSync() && home != null) {
      for (final spec in kBrowserCatalog) {
        if (Directory(p.join(browserDir.path, spec.id)).existsSync()) {
          browsers.add(
            ManifestBrowser(
              id: spec.id,
              label: spec.label,
              profilePath: p.join(home, spec.paths.first),
            ),
          );
        }
      }
    }
    sources.sort((a, b) => a.name.compareTo(b.name));
    return BackupManifest(
      date: null,
      hostname: null,
      home: home,
      folderName: p.basename(backupDir),
      sources: sources,
      browsers: browsers,
      fromManifest: false,
    );
  }
}

/// Pacotes de segredos em [destination], do mais recente para o mais antigo.
List<String> listSecretsFiles(String destination) {
  final dir = Directory(destination);
  if (!dir.existsSync()) return const [];
  final names = [
    for (final e in dir.listSync(followLinks: false))
      if (e is File && _secretsFile.hasMatch(p.basename(e.path)))
        p.basename(e.path),
  ]..sort((a, b) => b.compareTo(a));
  return names;
}
