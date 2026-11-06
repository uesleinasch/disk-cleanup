import 'dart:io';

import 'package:path/path.dart' as p;

import '../cleanup/privileged_runner.dart';
import '../core/models.dart';
import '../core/process_runner.dart';
import 'du_scanner.dart';

class CacheDef {
  const CacheDef({
    required this.id,
    required this.title,
    required this.relPath,
    required this.note,
    this.processName,
  });

  final String id;
  final String title;
  final String relPath;
  final String note;
  final String? processName;
}

const _browserNote = 'Páginas e imagens; logins e histórico ficam';

const List<CacheDef> kCacheCatalog = [
  CacheDef(
    id: 'uv',
    title: 'Cache do uv',
    relPath: '.cache/uv',
    note: 'Pacotes Python baixados',
  ),
  CacheDef(
    id: 'pip',
    title: 'Cache do pip',
    relPath: '.cache/pip',
    note: 'Pacotes Python baixados',
  ),
  CacheDef(
    id: 'npm',
    title: 'Cache do npm',
    relPath: '.npm/_cacache',
    note: 'Pacotes Node baixados',
  ),
  CacheDef(
    id: 'yarn',
    title: 'Cache do yarn',
    relPath: '.cache/yarn',
    note: 'Pacotes Node baixados',
  ),
  CacheDef(
    id: 'pnpm',
    title: 'Cache do pnpm',
    relPath: '.local/share/pnpm/store',
    note: 'Pacotes Node baixados',
  ),
  CacheDef(
    id: 'bun',
    title: 'Cache do bun',
    relPath: '.bun/install/cache',
    note: 'Pacotes Node baixados',
  ),
  CacheDef(
    id: 'gradle',
    title: 'Cache do Gradle',
    relPath: '.gradle/caches',
    note: 'Dependências Android e Java',
  ),
  CacheDef(
    id: 'nuget',
    title: 'Cache do NuGet',
    relPath: '.nuget/packages',
    note: 'Pacotes .NET baixados',
  ),
  CacheDef(
    id: 'pub',
    title: 'Cache do pub',
    relPath: '.pub-cache/hosted',
    note: 'Pacotes Dart e Flutter baixados',
  ),
  CacheDef(
    id: 'cabal',
    title: 'Cache do cabal',
    relPath: '.cabal/packages',
    note: 'Pacotes Haskell baixados',
  ),
  CacheDef(
    id: 'stack',
    title: 'Cache do stack',
    relPath: '.stack/pantry',
    note: 'Pacotes Haskell baixados',
  ),
  CacheDef(
    id: 'cargo',
    title: 'Cache do cargo',
    relPath: '.cargo/registry/cache',
    note: 'Pacotes Rust baixados',
  ),
  CacheDef(
    id: 'chrome',
    title: 'Cache do Google Chrome',
    relPath: '.cache/google-chrome',
    note: _browserNote,
    processName: 'chrome',
  ),
  CacheDef(
    id: 'chromium',
    title: 'Cache do Chromium',
    relPath: '.cache/chromium',
    note: _browserNote,
    processName: 'chromium',
  ),
  CacheDef(
    id: 'brave',
    title: 'Cache do Brave',
    relPath: '.cache/BraveSoftware',
    note: _browserNote,
    processName: 'brave',
  ),
  CacheDef(
    id: 'firefox',
    title: 'Cache do Firefox',
    relPath: '.cache/mozilla/firefox',
    note: _browserNote,
    processName: 'firefox',
  ),
  CacheDef(
    id: 'playwright',
    title: 'Navegadores do Playwright',
    relPath: '.cache/ms-playwright',
    note: 'Baixados de novo no próximo teste',
  ),
];

class CacheInventory {
  CacheInventory(this._runner, this._du);

  final ProcessRunner _runner;
  final DuScanner _du;

  Future<List<CleanupItem>> scan(String home) async {
    final paths = {
      for (final def in kCacheCatalog) def.id: p.join(home, def.relPath),
    };
    final sizes = await _du.sizesOf(paths.values.toList());

    final found = <(CacheDef, String, int)>[
      for (final def in kCacheCatalog)
        if ((sizes[paths[def.id]!] ?? 0) > 0)
          (def, paths[def.id]!, sizes[paths[def.id]!]!),
    ];

    final running = <String, bool>{};
    for (final name in {
      for (final (def, _, _) in found)
        if (def.processName != null) def.processName!,
    }) {
      running[name] = (await _runner.run('pgrep', ['-x', name])).exitCode == 0;
    }

    return [
      for (final (def, path, bytes) in found)
        _item(def, path, bytes, running[def.processName] ?? false),
    ];
  }

  static CleanupItem _item(CacheDef def, String path, int bytes, bool open) {
    final app = def.title.replaceFirst('Cache do ', '');
    return CleanupItem(
      id: 'cache:${def.id}',
      category: CleanupCategory.cache,
      title: def.title,
      path: path,
      note: open ? '$app está aberto: feche para limpar' : def.note,
      bytes: bytes,
      risk: RiskLevel.safe,
      requiresRoot: false,
      preselected: !open,
      action: DeletePathsAction([path]),
    );
  }
}

int? _statSize(String path) {
  final file = File(path);
  return file.existsSync() ? file.lengthSync() : null;
}

class SystemInventory {
  SystemInventory(this._runner, this._du, {this.fileSize = _statSize});

  static const _journalPath = '/var/log/journal';
  static const _aptPath = '/var/cache/apt/archives';
  static const _minBytes = 1000000;

  final ProcessRunner _runner;
  final DuScanner _du;
  final int? Function(String path) fileSize;

  Future<List<CleanupItem>> scan() async {
    final sizes = await _du.sizesOf([_journalPath, _aptPath]);
    return [
      if ((sizes[_journalPath] ?? 0) >= _minBytes)
        _item(
          id: 'system:journal',
          title: 'Logs do sistema (journal)',
          path: _journalPath,
          note: 'Mantém os últimos 500 MB',
          bytes: sizes[_journalPath]!,
          command: JournalVacuum(),
        ),
      if ((sizes[_aptPath] ?? 0) >= _minBytes)
        _item(
          id: 'system:apt',
          title: 'Cache do apt',
          path: _aptPath,
          note: 'Pacotes .deb baixados',
          bytes: sizes[_aptPath]!,
          command: AptClean(),
        ),
      ...await _snapItems(),
    ];
  }

  Future<List<CleanupItem>> _snapItems() async {
    final result = await _runner.run('snap', ['list', '--all']);
    if (result.exitCode != 0) return [];
    final items = <CleanupItem>[];
    for (final line in result.stdoutText.split('\n')) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 6 || !cols.last.split(',').contains('disabled')) {
        continue;
      }
      final name = cols[0];
      final revision = cols[2];
      final path = '/var/lib/snapd/snaps/${name}_$revision.snap';
      final bytes = fileSize(path);
      if (bytes == null) continue;
      final SnapRemoveRevision command;
      try {
        command = SnapRemoveRevision(name, revision);
      } on ArgumentError {
        continue;
      }
      items.add(
        _item(
          id: 'system:snap:$name:$revision',
          title: 'Snap $name (revisão $revision desativada)',
          path: path,
          note: 'Versão antiga do snap, já substituída',
          bytes: bytes,
          command: command,
        ),
      );
    }
    return items;
  }

  static CleanupItem _item({
    required String id,
    required String title,
    required String path,
    required String note,
    required int bytes,
    required RootCommand command,
  }) => CleanupItem(
    id: id,
    category: CleanupCategory.system,
    title: title,
    path: path,
    note: note,
    bytes: bytes,
    risk: RiskLevel.safe,
    requiresRoot: true,
    preselected: false,
    action: RootAction([command]),
  );
}
