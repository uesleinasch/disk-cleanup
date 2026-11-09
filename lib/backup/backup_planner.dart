import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/process_runner.dart';

const kBackupAlwaysExcluded = [
  'node_modules',
  '.angular',
  '.stack-work',
  'dist-newstyle',
  '.venv',
  'venv',
  '.terraform',
  '.gradle',
  '.dart_tool',
  'obj',
  '__pycache__',
  '.next',
  '.nuxt',
  '.cache',
  '.pytest_cache',
  '.mypy_cache',
  '.turbo',
  '.parcel-cache',
  'coverage',
];

const kBackupBuildDirs = ['dist', 'build', 'bin', 'target', 'out'];

const _rsyncOkCodes = {0, 23, 24};
const _gitChunk = 200;

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

String rsyncLiteral(String pattern) => pattern.contains(RegExp(r'[*?\[]'))
    ? pattern.replaceAllMapped(RegExp(r'[\\*?\[]'), (m) => '\\${m[0]}')
    : pattern;

class BackupFilter {
  const BackupFilter({
    required this.sources,
    this.ignoredBuilds = const [],
    this.protectedPaths = const [],
  });

  final List<String> sources;
  final List<String> ignoredBuilds;
  final List<String> protectedPaths;

  List<String> get rules => [
    for (final name in kBackupAlwaysExcluded) '- $name/',
    for (final dir in ignoredBuilds)
      if (_anchor(dir) case final a?) '- $a/',
    for (final path in protectedPaths)
      if (_anchor(path) case final a?) '- $a',
  ];

  String? _anchor(String path) {
    for (final source in sources) {
      if (p.isWithin(source, path)) {
        final rel = p.relative(path, from: source);
        return rsyncLiteral('/${p.basename(source)}/$rel');
      }
    }
    return null;
  }

  Future<void> writeTo(File file) => file.writeAsString(rules.join('\x00'));
}

List<String> backupRsyncArgs({
  required String filterFile,
  required List<String> sources,
  required String destination,
  bool mirror = false,
  bool dryRun = false,
}) => [
  '-aH',
  if (dryRun) '-n' else ...['--info=progress2', '--no-inc-recursive'],
  '--stats',
  if (mirror) '--delete',
  '--from0',
  '--exclude-from=$filterFile',
  for (final s in sources) p.normalize(s),
  '${p.normalize(destination)}/',
];

int? _number(String text) => int.tryParse(text.replaceAll(',', ''));

class RsyncStats {
  const RsyncStats({
    required this.files,
    required this.totalBytes,
    required this.transferredFiles,
    required this.transferredBytes,
  });

  final int files;
  final int totalBytes;
  final int transferredFiles;
  final int transferredBytes;

  static final _files = RegExp(
    r'^Number of files: ([\d,]+)(?:.*reg: ([\d,]+))?',
  );
  static final _transferredFiles = RegExp(
    r'^Number of regular files transferred: ([\d,]+)',
  );
  static final _total = RegExp(r'^Total file size: ([\d,]+) bytes');
  static final _transferred = RegExp(
    r'^Total transferred file size: ([\d,]+) bytes',
  );

  static RsyncStats? parse(Iterable<String> lines) {
    int? files, total, transferredFiles, transferred;
    for (final line in lines) {
      if (_files.firstMatch(line) case final m?) {
        files = _number(m[2] ?? m[1]!);
      } else if (_transferredFiles.firstMatch(line) case final m?) {
        transferredFiles = _number(m[1]!);
      } else if (_total.firstMatch(line) case final m?) {
        total = _number(m[1]!);
      } else if (_transferred.firstMatch(line) case final m?) {
        transferred = _number(m[1]!);
      }
    }
    if (files == null || total == null || transferred == null) return null;
    return RsyncStats(
      files: files,
      totalBytes: total,
      transferredFiles: transferredFiles ?? 0,
      transferredBytes: transferred,
    );
  }
}

class BackupEstimate {
  const BackupEstimate(this.bySource);

  final Map<String, RsyncStats> bySource;

  int get totalBytes => _sum((s) => s.totalBytes);
  int get transferBytes => _sum((s) => s.transferredBytes);
  int get files => _sum((s) => s.files);

  int _sum(int Function(RsyncStats) f) =>
      bySource.values.fold(0, (acc, s) => acc + f(s));
}

class BackupPlanner {
  BackupPlanner(this._runner);

  final ProcessRunner _runner;

  Future<BackupFilter> plan(
    List<String> sources, {
    List<String> protectedPaths = const [],
    CancelToken? cancel,
  }) async => BackupFilter(
    sources: sources,
    ignoredBuilds: await findIgnoredBuilds(sources, cancel: cancel),
    protectedPaths: protectedPaths,
  );

  Future<List<String>> findIgnoredBuilds(
    List<String> sources, {
    CancelToken? cancel,
  }) async {
    if (sources.isEmpty) return [];
    final result = await _runner.run('find', [
      ...sources,
      '-type',
      'd',
      ..._nameGroup([...kBackupAlwaysExcluded, '.git']),
      '-prune',
      '-o',
      '-type',
      'd',
      ..._nameGroup(kBackupBuildDirs),
      '-prune',
      '-print0',
    ], cancel: cancel);

    final byRepo = <String, List<String>>{};
    final roots = <String, String?>{};
    for (final dir in result.stdoutText.split('\x00')) {
      if (dir.isEmpty) continue;
      final root = _repoRoot(p.dirname(dir), roots);
      if (root == null) continue;
      byRepo.putIfAbsent(root, () => []).add(p.relative(dir, from: root));
    }

    final ignored = <String>[];
    for (final MapEntry(key: root, value: dirs) in byRepo.entries) {
      for (var i = 0; i < dirs.length; i += _gitChunk) {
        final chunk = dirs.sublist(i, (i + _gitChunk).clamp(0, dirs.length));
        for (final rel in await _gitIgnored(root, chunk, cancel)) {
          ignored.add(p.join(root, rel));
        }
      }
    }
    ignored.sort();
    return ignored;
  }

  // dist/build/bin podem ser versionados (vendor/bin, wwwroot/lib/*/dist):
  // excluir pelo nome perderia código. O check-ignore consulta o índice e
  // não marca pasta com arquivo rastreado. Na dúvida (erro, nome escapado
  // pelo git), a pasta fica no backup.
  Future<List<String>> _gitIgnored(
    String root,
    List<String> dirs,
    CancelToken? cancel,
  ) async {
    final r = await _runner.run('git', [
      '-c',
      'core.quotePath=false',
      '-C',
      root,
      'check-ignore',
      '--',
      for (final d in dirs) '$d/',
    ], cancel: cancel);
    if (r.exitCode > 1) return [];
    final reported = {
      for (final line in r.stdoutText.split('\n'))
        if (line.endsWith('/')) line.substring(0, line.length - 1),
    };
    return [
      for (final d in dirs)
        if (reported.contains(d)) d,
    ];
  }

  static List<String> _nameGroup(List<String> names) => [
    '(',
    for (var i = 0; i < names.length; i++) ...[
      if (i > 0) '-o',
      '-name',
      names[i],
    ],
    ')',
  ];

  static String? _repoRoot(String dir, Map<String, String?> cache) {
    final visited = <String>[];
    var current = dir;
    String? root;
    while (true) {
      if (cache.containsKey(current)) {
        root = cache[current];
        break;
      }
      visited.add(current);
      final git = p.join(current, '.git');
      if (FileSystemEntity.typeSync(git, followLinks: false) !=
          FileSystemEntityType.notFound) {
        root = current;
        break;
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    for (final v in visited) {
      cache[v] = root;
    }
    return root;
  }

  Future<BackupEstimate> estimate({
    required String filterFile,
    required List<String> sources,
    required String destination,
    bool mirror = false,
    CancelToken? cancel,
  }) async {
    final bySource = <String, RsyncStats>{};
    for (final source in sources) {
      final lines = <String>[];
      final r = await _runner.runStreaming(
        'rsync',
        backupRsyncArgs(
          filterFile: filterFile,
          sources: [source],
          destination: destination,
          mirror: mirror,
          dryRun: true,
        ),
        onLine: lines.add,
        environment: const {'LC_ALL': 'C'},
        cancel: cancel,
      );
      if (r.exitCode == 127) {
        throw const BackupException(
          'O rsync não está instalado. Instale o pacote rsync.',
        );
      }
      final stats = RsyncStats.parse(lines);
      if (!_rsyncOkCodes.contains(r.exitCode) || stats == null) {
        throw BackupException(
          'Não foi possível calcular o tamanho de $source: ${r.stderr.trim()}',
        );
      }
      bySource[source] = stats;
    }
    return BackupEstimate(bySource);
  }
}
