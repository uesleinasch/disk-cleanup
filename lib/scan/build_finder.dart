import 'dart:io';

import '../core/process_runner.dart';
import '../settings/settings.dart';
import 'du_scanner.dart';
import 'project_activity.dart';

class BuildArtifact {
  const BuildArtifact({
    required this.path,
    required this.projectDir,
    required this.rule,
    required this.bytes,
    required this.projectModified,
  });

  final String path;
  final String projectDir;
  final BuildRule rule;
  final int bytes;
  final DateTime projectModified;
}

String findPathLiteral(String path) {
  final trimmed = path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  return trimmed.replaceAllMapped(RegExp(r'[\\*?\[\]]'), (m) => '\\${m[0]}');
}

class BuildFinder {
  BuildFinder(this._runner, this._du);

  final ProcessRunner _runner;
  final DuScanner _du;

  Future<List<BuildArtifact>> find(
    List<String> roots,
    List<BuildRule> rules, {
    List<String> excludeRoots = const [],
    CancelToken? cancel,
  }) async {
    if (roots.isEmpty || rules.isEmpty) return [];
    final names = rules.map((r) => r.dirName).toSet().toList();
    final result = await _runner.run(
      'find',
      [
        ...roots,
        '-xdev',
        if (excludeRoots.isNotEmpty) ...[
          '(',
          for (var i = 0; i < excludeRoots.length; i++) ...[
            if (i > 0) '-o',
            '-path',
            findPathLiteral(excludeRoots[i]),
          ],
          ')',
          '-prune',
          '-o',
        ],
        '-type',
        'd',
        '(',
        for (var i = 0; i < names.length; i++) ...[
          if (i > 0) '-o',
          '-name',
          names[i],
        ],
        ')',
        '-prune',
        '-print0',
      ],
      cancel: cancel,
      environment: cLocaleEnvironment,
    );

    final matches = <({String path, String projectDir, BuildRule rule})>[];
    final seen = <String>{};
    for (final path in result.stdoutText.split('\x00')) {
      if (path.isEmpty || !seen.add(path)) continue;
      final slash = path.lastIndexOf('/');
      if (slash <= 0) continue;
      final name = path.substring(slash + 1);
      final projectDir = path.substring(0, slash);
      final rule = _matchingRule(projectDir, name, rules);
      if (rule != null) {
        matches.add((path: path, projectDir: projectDir, rule: rule));
      }
    }
    if (matches.isEmpty) return [];

    final sizes = await _du.sizesOf([
      for (final m in matches) m.path,
    ], cancel: cancel);
    final artifacts = <BuildArtifact>[];
    for (final m in matches) {
      final bytes = sizes[m.path];
      if (bytes == null) continue;
      artifacts.add(
        BuildArtifact(
          path: m.path,
          projectDir: m.projectDir,
          rule: m.rule,
          bytes: bytes,
          projectModified: _projectModified(m.projectDir, names),
        ),
      );
    }
    return artifacts;
  }

  static BuildRule? _matchingRule(
    String projectDir,
    String name,
    List<BuildRule> rules,
  ) {
    final candidates = rules.where((r) => r.dirName == name).toList();
    if (candidates.isEmpty) return null;
    final Set<String> files;
    try {
      files = {
        for (final e in Directory(projectDir).listSync(followLinks: false))
          if (e is File) e.uri.pathSegments.last,
      };
    } on FileSystemException {
      return null;
    }
    for (final rule in candidates) {
      if (files.any(rule.matchesMarker)) return rule;
    }
    return null;
  }

  static DateTime _projectModified(String projectDir, List<String> buildNames) {
    final newest = newestProjectModification(
      projectDir,
      extraPruned: buildNames,
    );
    if (newest != null) return newest;
    try {
      return Directory(projectDir).statSync().modified;
    } on FileSystemException {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}
