import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/process_runner.dart';
import 'backup_planner.dart';
import 'rsync_runner.dart';

enum ItemizeKind { created, changed, deleting }

class ItemizeEntry {
  const ItemizeEntry(
    this.kind,
    this.path, {
    this.isDir = false,
    this.isLink = false,
  });

  final ItemizeKind kind;
  final String path;
  final bool isDir;
  final bool isLink;

  @override
  bool operator ==(Object other) =>
      other is ItemizeEntry &&
      other.kind == kind &&
      other.path == path &&
      other.isDir == isDir &&
      other.isLink == isLink;

  @override
  int get hashCode => Object.hash(kind, path, isDir, isLink);

  @override
  String toString() => 'ItemizeEntry($kind, $path)';
}

final _rsyncEscape = RegExp(r'\\#([0-7]{3})');
final _itemize = RegExp(r'^([<>ch.])([fdLDS])([.+cstpoguaxn?]{9}) (.+)$');
final _deleting = RegExp(r'^\*deleting +(.+)$');

String unescapeRsync(String s) => s.replaceAllMapped(
  _rsyncEscape,
  (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)),
);

/// Lê a saída de `rsync -8 --itemize-changes --out-format='%i %n'`.
/// Diretórios só aparecem quando seriam apagados.
List<ItemizeEntry> parseItemize(Iterable<String> lines) {
  final out = <ItemizeEntry>[];
  for (final line in lines) {
    if (_deleting.firstMatch(line) case final m?) {
      final raw = unescapeRsync(m[1]!);
      final isDir = raw.endsWith('/');
      out.add(
        ItemizeEntry(
          ItemizeKind.deleting,
          isDir ? raw.substring(0, raw.length - 1) : raw,
          isDir: isDir,
        ),
      );
      continue;
    }
    final m = _itemize.firstMatch(line);
    if (m == null) continue;
    final type = m[2]!;
    if (type == 'd' || type == 'D' || type == 'S') continue;
    final flags = m[3]!;
    if (m[1] == '.' && !flags.contains(RegExp('[cst]'))) continue;
    out.add(
      ItemizeEntry(
        flags == '+++++++++' ? ItemizeKind.created : ItemizeKind.changed,
        unescapeRsync(m[4]!),
        isLink: type == 'L',
      ),
    );
  }
  return out;
}

class RestoreConflict {
  const RestoreConflict({
    required this.path,
    this.localSize,
    this.localModified,
    this.backupSize,
    this.backupModified,
  });

  final String path;
  final int? localSize;
  final DateTime? localModified;
  final int? backupSize;
  final DateTime? backupModified;

  bool get backupIsNewer =>
      backupModified != null &&
      (localModified == null || backupModified!.isAfter(localModified!));
}

enum ConflictAction { keepLocal, useBackup, keepBoth, newerWins }

class RestoreAnalysis {
  const RestoreAnalysis({
    required this.source,
    required this.target,
    required this.created,
    required this.conflicts,
    this.createdBytes = 0,
  });

  final String source;
  final String target;
  final List<String> created;
  final List<RestoreConflict> conflicts;
  final int createdBytes;

  bool get isEmpty => created.isEmpty && conflicts.isEmpty;
}

class RestoreDecision {
  const RestoreDecision({
    required this.copy,
    required this.replace,
    required this.duplicate,
    required this.keep,
  });

  final List<String> copy;
  final List<String> replace;
  final List<String> duplicate;
  final List<String> keep;
}

ConflictAction effectiveAction(RestoreConflict c, ConflictAction action) =>
    action == ConflictAction.newerWins
    ? (c.backupIsNewer ? ConflictAction.useBackup : ConflictAction.keepLocal)
    : action;

RestoreDecision resolveConflicts(
  RestoreAnalysis analysis,
  ConflictAction rule, {
  Map<String, ConflictAction> overrides = const {},
}) {
  final replace = <String>[];
  final duplicate = <String>[];
  final keep = <String>[];
  for (final c in analysis.conflicts) {
    switch (effectiveAction(c, overrides[c.path] ?? rule)) {
      case ConflictAction.useBackup:
        replace.add(c.path);
      case ConflictAction.keepBoth:
        duplicate.add(c.path);
      case ConflictAction.keepLocal || ConflictAction.newerWins:
        keep.add(c.path);
    }
  }
  return RestoreDecision(
    copy: analysis.created,
    replace: replace,
    duplicate: duplicate,
    keep: keep,
  );
}

String duplicateName(String path, String label) {
  final dir = p.dirname(path);
  final base = p.basename(path);
  final dot = base.lastIndexOf('.');
  final (stem, ext) = dot > 0
      ? (base.substring(0, dot), base.substring(dot))
      : (base, '');
  final name = '$stem ($label)$ext';
  return dir == '.' ? name : p.join(dir, name);
}

/// [target] precisa ficar dentro de uma das [allowedRoots] mesmo depois de
/// resolver os symlinks do maior ancestral que já existe.
Future<bool> isRestorableTarget(
  String target,
  List<String> allowedRoots,
) async {
  if (!p.isAbsolute(target)) return false;
  final normal = p.normalize(target);
  var existing = normal;
  while (!Directory(existing).existsSync() && existing != p.dirname(existing)) {
    existing = p.dirname(existing);
  }
  String real;
  try {
    real = await Directory(existing).resolveSymbolicLinks();
  } on FileSystemException {
    return false;
  }
  final resolved = p.join(real, p.relative(normal, from: existing));
  for (final root in allowedRoots) {
    final r = p.normalize(root);
    final rr = await Directory(r).resolveSymbolicLinks().catchError((_) => r);
    if ((normal == r || p.isWithin(r, normal)) &&
        (p.normalize(resolved) == rr || p.isWithin(rr, resolved))) {
      return true;
    }
  }
  return false;
}

class RestoreResult {
  const RestoreResult({
    required this.outcome,
    this.copied = 0,
    this.replaced = 0,
    this.duplicated = 0,
    this.warnings = const [],
    this.error,
  });

  final RsyncOutcome outcome;
  final int copied;
  final int replaced;
  final int duplicated;
  final List<String> warnings;
  final String? error;
}

class RestoreEngine {
  RestoreEngine(this._runner, this._rsync);

  final ProcessRunner _runner;
  final RsyncRunner _rsync;
  int _lists = 0;

  Future<File> _list(Directory tmp, String name, Iterable<String> paths) async {
    final f = File(p.join(tmp.path, '$name-${_lists++}'));
    await f.writeAsString(paths.map((x) => '$x\x00').join());
    return f;
  }

  Future<RestoreAnalysis> analyze({
    required String source,
    required String target,
    required Directory tmp,
    List<String>? subpaths,
    CancelToken? cancel,
  }) async {
    final files = subpaths == null
        ? null
        : await _list(tmp, 'analise', subpaths);
    final lines = <String>[];
    final r = await _runner.runStreaming(
      'rsync',
      [
        '-aHn',
        '-8',
        if (files != null) ...['-r', '--from0', '--files-from=${files.path}'],
        '--itemize-changes',
        '--out-format=%i %n',
        '${p.normalize(source)}/',
        '${p.normalize(target)}/',
      ],
      onLine: lines.add,
      environment: const {'LC_ALL': 'C'},
      cancel: cancel,
    );
    if (r.exitCode != 0 && r.exitCode != 23 && r.exitCode != 24) {
      throw BackupException(
        interpretRsync(r, const []).error ??
            'Não foi possível analisar o backup.',
      );
    }
    final created = <String>[];
    var createdBytes = 0;
    final conflicts = <RestoreConflict>[];
    for (final e in parseItemize(lines)) {
      final from = p.join(source, e.path);
      final to = p.join(target, e.path);
      switch (e.kind) {
        case ItemizeKind.created:
          created.add(e.path);
          createdBytes += _size(from) ?? 0;
        case ItemizeKind.changed:
          if (!e.isLink && await _sameContent(from, to)) continue;
          final local = FileStat.statSync(to);
          final backup = FileStat.statSync(from);
          conflicts.add(
            RestoreConflict(
              path: e.path,
              localSize: e.isLink ? null : local.size,
              localModified: local.modified,
              backupSize: e.isLink ? null : backup.size,
              backupModified: backup.modified,
            ),
          );
        case ItemizeKind.deleting:
          break;
      }
    }
    return RestoreAnalysis(
      source: source,
      target: target,
      created: created,
      conflicts: conflicts,
      createdBytes: createdBytes,
    );
  }

  static int? _size(String path) {
    final s = FileStat.statSync(path);
    return s.type == FileSystemEntityType.file ? s.size : null;
  }

  static Future<bool> _sameContent(String a, String b) async {
    final fa = File(a);
    final fb = File(b);
    if (!fa.existsSync() || !fb.existsSync()) return false;
    if (fa.lengthSync() != fb.lengthSync()) return false;
    final ra = await fa.open();
    final rb = await fb.open();
    try {
      const chunk = 1 << 16;
      while (true) {
        final xa = await ra.read(chunk);
        final xb = await rb.read(chunk);
        if (xa.length != xb.length) return false;
        if (xa.isEmpty) return true;
        for (var i = 0; i < xa.length; i++) {
          if (xa[i] != xb[i]) return false;
        }
      }
    } finally {
      await ra.close();
      await rb.close();
    }
  }

  Future<void> makePrivate(String dir, {CancelToken? cancel}) async {
    if (!Directory(dir).existsSync()) return;
    await _runner.run('chmod', ['-R', 'go-rwx', '--', dir], cancel: cancel);
  }

  Future<RestoreResult> execute({
    required RestoreAnalysis analysis,
    required RestoreDecision decision,
    required String replacedDir,
    required String duplicateLabel,
    required Directory tmp,
    void Function(RsyncProgress)? onProgress,
    CancelToken? cancel,
  }) async {
    final source = p.normalize(analysis.source);
    final target = p.normalize(analysis.target);
    final warnings = <String>[];
    var outcome = RsyncOutcome.ok;
    String? error;
    final transfer = [...decision.copy, ...decision.replace];
    if (transfer.isNotEmpty) {
      final files = await _list(tmp, 'copiar', transfer);
      await Directory(target).create(recursive: true);
      final r = await _rsync.run(
        [
          '-aH',
          '-8',
          '--info=progress2',
          '--no-inc-recursive',
          '--stats',
          '--from0',
          '--files-from=${files.path}',
          '--backup',
          '--backup-dir=$replacedDir',
          '$source/',
          '$target/',
        ],
        onProgress: onProgress,
        cancel: cancel,
      );
      outcome = r.outcome;
      warnings.addAll(r.warnings);
      error = r.error;
      if (r.outcome == RsyncOutcome.failed) {
        return RestoreResult(outcome: outcome, error: error);
      }
    }
    var duplicated = 0;
    for (final rel in decision.duplicate) {
      if (cancel?.isCancelled ?? false) throw const ScanCancelled();
      var name = duplicateName(rel, duplicateLabel);
      for (var n = 2; File(p.join(target, name)).existsSync(); n++) {
        name = duplicateName(rel, '$duplicateLabel $n');
      }
      final r = await _runner.run('cp', [
        '-P',
        '-p',
        '--no-clobber',
        '--',
        p.join(source, rel),
        p.join(target, name),
      ], cancel: cancel);
      if (r.exitCode == 0) {
        duplicated++;
      } else {
        outcome = RsyncOutcome.warnings;
        warnings.add('$rel: ${r.stderr.trim()}');
      }
    }
    return RestoreResult(
      outcome: outcome,
      copied: decision.copy.length,
      replaced: decision.replace.length,
      duplicated: duplicated,
      warnings: warnings,
      error: error,
    );
  }
}
