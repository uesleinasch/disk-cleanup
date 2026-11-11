import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/process_runner.dart';
import '../services.dart';
import '../settings/settings_controller.dart';
import 'backup_controller.dart';
import 'backup_manifest.dart';
import 'backup_planner.dart';
import 'backup_services.dart';
import 'browser_profiles.dart';
import 'restore_planner.dart';
import 'rsync_runner.dart';
import 'secrets_archiver.dart';

enum RestoreKind { secrets, folder, browser }

enum RestorePhase { idle, loading, analyzing, reviewing, running, finished }

enum RestoreDestination { original, separate }

class RestoreChoice {
  const RestoreChoice({
    required this.kind,
    required this.id,
    required this.label,
    required this.backupPath,
    required this.originalPath,
  });

  final RestoreKind kind;
  final String id;
  final String label;
  final String backupPath;
  final String? originalPath;
}

class RestoreItem {
  RestoreItem(this.choice, {this.subpaths});

  final RestoreChoice choice;
  final List<String>? subpaths;
  String? target;
  String? source;
  RestoreAnalysis? analysis;
  Map<String, ConflictAction> overrides = {};
  BackupStepStatus status = BackupStepStatus.pending;
  String? message;
  List<String> warnings = const [];
  RestoreResult? result;
}

class RestoreTotals {
  const RestoreTotals({
    this.created = 0,
    this.replace = 0,
    this.duplicate = 0,
    this.keep = 0,
    this.conflicts = 0,
    this.createdBytes = 0,
  });

  final int created;
  final int replace;
  final int duplicate;
  final int keep;
  final int conflicts;
  final int createdBytes;
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _stamp(DateTime d) =>
    '${_date(d)}-${d.hour.toString().padLeft(2, '0')}'
    '${d.minute.toString().padLeft(2, '0')}'
    '${d.second.toString().padLeft(2, '0')}';

class RestoreController extends ChangeNotifier {
  RestoreController(
    this.services,
    this.settings,
    this.backup, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Services services;
  final SettingsController settings;
  final BackupController backup;
  final DateTime Function() _now;

  BackupServices get _b => services.backup;
  RestoreEngine get _engine => _b.restore;
  String get home => services.home;

  RestorePhase phase = RestorePhase.idle;
  String? backupDir;
  BackupManifest? manifest;
  List<RestoreChoice> choices = const [];
  List<String> secretsFiles = const [];
  String? loadError;

  final Set<String> selected = {};
  final Map<String, List<String>> subpaths = {};
  final Map<String, String> customTargets = {};
  RestoreDestination destination = RestoreDestination.original;
  ConflictAction rule = ConflictAction.newerWins;
  String? secretsFile;
  Map<String, String> _secretsPaths = const {};

  List<RestoreItem> items = const [];
  int? current;
  RsyncProgress? progress;
  String? replacedDir;
  String? error;
  CancelToken? _cancel;
  Directory? _tmp;
  Directory? _staging;
  DateTime? _runDate;

  bool get busyElsewhere => _b.lock.heldByOther(this);

  bool get busy =>
      phase == RestorePhase.analyzing || phase == RestorePhase.running;

  String get separateRoot => p.join(home, 'Restaurado-${_date(_now())}');

  String get duplicateLabel {
    final d = manifest?.date;
    return d == null ? 'backup' : 'backup ${_date(d)}';
  }

  Future<void> load({String? dir}) async {
    if (busy) return;
    final target = dir ?? backup.backupDir;
    phase = RestorePhase.loading;
    loadError = null;
    notifyListeners();
    try {
      final resolved = target == null ? null : _locateBackupDir(target);
      if (resolved == null) {
        backupDir = null;
        manifest = null;
        choices = const [];
        secretsFiles = const [];
        _secretsPaths = const {};
        loadError = target == null
            ? 'Conecte o disco do backup ou abra uma pasta de backup.'
            : 'Não há backup em $target.';
        return;
      }
      backupDir = resolved;
      manifest = await BackupManifest.load(
        resolved,
        knownSources: backup.config.sources,
        home: home,
      );
      final parent = p.dirname(resolved);
      _secretsPaths = {
        for (final n in listSecretsFiles(parent)) n: p.join(parent, n),
        for (final n in listSecretsFiles(resolved)) n: p.join(resolved, n),
      };
      secretsFiles = _secretsPaths.keys.toList()
        ..sort((a, b) => b.compareTo(a));
      secretsFile = secretsFiles.firstOrNull;
      choices = _choicesFrom(manifest!, resolved);
      selected.removeWhere((id) => !choices.any((c) => c.id == id));
    } finally {
      phase = RestorePhase.idle;
      notifyListeners();
    }
  }

  String? _locateBackupDir(String dir) {
    if (!Directory(dir).existsSync()) return null;
    if (File(p.join(dir, kManifestName)).existsSync()) return dir;
    final configured = p.join(dir, backup.config.folderName);
    for (final candidate in [configured, p.join(dir, 'backup')]) {
      if (File(p.join(candidate, kManifestName)).existsSync()) {
        return candidate;
      }
    }
    for (final e in Directory(dir).listSync(followLinks: false)) {
      if (e is Directory && File(p.join(e.path, kManifestName)).existsSync()) {
        return e.path;
      }
    }
    if (File(p.join(dir, 'LEIA-ME-RESTAURAR.md')).existsSync() &&
        Directory(configured).existsSync()) {
      return configured;
    }
    if (p.basename(dir) == backup.config.folderName ||
        Directory(p.join(dir, kBrowserFolder)).existsSync()) {
      return dir;
    }
    return null;
  }

  List<RestoreChoice> _choicesFrom(BackupManifest m, String dir) => [
    if (secretsFiles.isNotEmpty)
      RestoreChoice(
        kind: RestoreKind.secrets,
        id: 'segredos',
        label: 'Chaves e configurações',
        backupPath: _secretsPaths[secretsFiles.first]!,
        originalPath: home,
      ),
    for (final s in m.sources)
      if (Directory(p.join(dir, s.name)).existsSync())
        RestoreChoice(
          kind: RestoreKind.folder,
          id: 'pasta:${s.name}',
          label: s.name,
          backupPath: p.join(dir, s.name),
          originalPath: s.path.isEmpty ? null : _rehome(s.path, m.home),
        ),
    for (final b in m.browsers)
      if (Directory(p.join(dir, kBrowserFolder, b.id)).existsSync())
        RestoreChoice(
          kind: RestoreKind.browser,
          id: 'navegador:${b.id}',
          label: b.label,
          backupPath: p.join(dir, kBrowserFolder, b.id),
          originalPath: _rehome(b.profilePath, m.home),
        ),
  ];

  String _rehome(String path, String? oldHome) {
    if (oldHome == null || oldHome == home) return path;
    if (path == oldHome) return home;
    if (p.isWithin(oldHome, path)) {
      return p.join(home, p.relative(path, from: oldHome));
    }
    return path;
  }

  RestoreChoice? choice(String id) =>
      choices.where((c) => c.id == id).firstOrNull;

  void toggle(String id) {
    selected.contains(id) ? selected.remove(id) : selected.add(id);
    notifyListeners();
  }

  void selectAll() {
    selected.addAll(choices.map((c) => c.id));
    notifyListeners();
  }

  void setSubpaths(String id, List<String>? paths) {
    if (paths == null || paths.isEmpty) {
      subpaths.remove(id);
    } else {
      subpaths[id] = [...paths]..sort();
      selected.add(id);
    }
    notifyListeners();
  }

  void setCustomTarget(String id, String? path) {
    if (path == null) {
      customTargets.remove(id);
    } else {
      customTargets[id] = p.normalize(path);
    }
    notifyListeners();
  }

  void setDestination(RestoreDestination d) {
    destination = d;
    notifyListeners();
  }

  void setSecretsFile(String name) {
    secretsFile = name;
    choices = [
      for (final c in choices)
        c.kind == RestoreKind.secrets
            ? RestoreChoice(
                kind: c.kind,
                id: c.id,
                label: c.label,
                backupPath: _secretsPaths[name]!,
                originalPath: c.originalPath,
              )
            : c,
    ];
    notifyListeners();
  }

  String? targetFor(RestoreChoice c) {
    if (customTargets[c.id] case final custom?) return custom;
    if (destination == RestoreDestination.separate) {
      return switch (c.kind) {
        RestoreKind.secrets => p.join(separateRoot, 'segredos'),
        RestoreKind.folder => p.join(separateRoot, c.label),
        RestoreKind.browser => p.join(
          separateRoot,
          kBrowserFolder,
          c.id.split(':').last,
        ),
      };
    }
    return c.originalPath;
  }

  List<String> get problems {
    final out = <String>[];
    if (busyElsewhere) out.add('Espere o backup terminar para restaurar.');
    if (selected.isEmpty) out.add('Escolha o que restaurar.');
    for (final id in selected) {
      final c = choice(id);
      if (c != null && targetFor(c) == null) {
        out.add('Escolha para onde restaurar ${c.label}.');
      }
    }
    return out;
  }

  bool get canAnalyze =>
      problems.isEmpty &&
      (phase == RestorePhase.idle || phase == RestorePhase.reviewing);

  Future<void> analyze() async {
    if (!canAnalyze || !_b.lock.acquire(this)) return;
    await _discard();
    phase = RestorePhase.analyzing;
    error = null;
    final cancel = _cancel = CancelToken();
    final ordered = [
      for (final kind in RestoreKind.values)
        for (final c in choices)
          if (c.kind == kind && selected.contains(c.id))
            RestoreItem(c, subpaths: subpaths[c.id]),
    ];
    items = ordered;
    notifyListeners();
    _tmp = await Directory.systemTemp.createTemp('disk-cleanup-');
    try {
      for (final (i, item) in ordered.indexed) {
        current = i;
        item.status = BackupStepStatus.running;
        notifyListeners();
        await _analyzeItem(item, cancel);
        notifyListeners();
      }
      phase = RestorePhase.reviewing;
    } on ScanCancelled {
      await _discard();
      phase = RestorePhase.idle;
    } finally {
      current = null;
      _cancel = null;
      _b.lock.release(this);
      notifyListeners();
    }
  }

  Future<void> _analyzeItem(RestoreItem item, CancelToken cancel) async {
    final c = item.choice;
    final target = targetFor(c)!;
    item.target = target;
    final roots = [home, ...settings.value.mappedDirs];
    if (!await isRestorableTarget(target, roots)) {
      item
        ..status = BackupStepStatus.failed
        ..message = 'Só dá para restaurar dentro da sua pasta pessoal.';
      return;
    }
    if (c.kind == RestoreKind.browser &&
        destination == RestoreDestination.original &&
        customTargets[c.id] == null) {
      final id = c.id.split(':').last;
      final install = _b.browsers
          .detect()
          .where((b) => b.spec.id == id)
          .firstOrNull;
      if (install != null && _b.browsers.isOpen(install)) {
        item
          ..status = BackupStepStatus.failed
          ..message = 'Feche o ${c.label} antes de restaurar o perfil.';
        return;
      }
    }
    var source = c.backupPath;
    if (c.kind == RestoreKind.secrets) {
      final staging = _staging ??= await Directory(services.runtimeDir)
          .createTemp('disk-cleanup-restaurar-');
      final r = await _b.secrets.extract(
        file: c.backupPath,
        staging: staging.path,
        cancel: cancel,
      );
      if (r.outcome == SecretsOutcome.failed ||
          r.outcome == SecretsOutcome.cancelled) {
        item
          ..status = r.outcome == SecretsOutcome.cancelled
              ? BackupStepStatus.skipped
              : BackupStepStatus.failed
          ..message = r.message;
        return;
      }
      source = staging.path;
    }
    item.source = source;
    try {
      final analysis = await _engine.analyze(
        source: source,
        target: target,
        tmp: _tmp!,
        subpaths: item.subpaths,
        cancel: cancel,
      );
      item
        ..analysis = analysis
        ..status = BackupStepStatus.pending
        ..message = analysis.isEmpty
            ? 'Nada a restaurar: já está igual.'
            : null;
    } on BackupException catch (e) {
      item
        ..status = BackupStepStatus.failed
        ..message = e.message;
    }
  }

  void setRule(ConflictAction action) {
    rule = action;
    notifyListeners();
  }

  void setOverride(RestoreItem item, String path, ConflictAction? action) {
    if (action == null) {
      item.overrides.remove(path);
    } else {
      item.overrides[path] = action;
    }
    notifyListeners();
  }

  RestoreDecision decisionFor(RestoreItem item) =>
      resolveConflicts(item.analysis!, rule, overrides: item.overrides);

  RestoreTotals get totals {
    var created = 0, replace = 0, duplicate = 0, keep = 0, bytes = 0;
    var conflicts = 0;
    for (final item in items) {
      final a = item.analysis;
      if (a == null) continue;
      final d = decisionFor(item);
      created += d.copy.length;
      replace += d.replace.length;
      duplicate += d.duplicate.length;
      keep += d.keep.length;
      conflicts += a.conflicts.length;
      bytes += a.createdBytes;
    }
    return RestoreTotals(
      created: created,
      replace: replace,
      duplicate: duplicate,
      keep: keep,
      conflicts: conflicts,
      createdBytes: bytes,
    );
  }

  bool get canRun =>
      phase == RestorePhase.reviewing &&
      !busyElsewhere &&
      items.any((i) => i.analysis != null && !i.analysis!.isEmpty);

  Future<void> start() async {
    if (!canRun || !_b.lock.acquire(this)) return;
    phase = RestorePhase.running;
    _runDate = _now();
    replacedDir = p.join(services.dataDir, 'substituidos', _stamp(_runDate!));
    final cancel = _cancel = CancelToken();
    notifyListeners();
    final pending = [
      for (final (i, item) in items.indexed)
        if (item.analysis != null) i,
    ];
    try {
      while (pending.isNotEmpty) {
        final i = pending.removeAt(0);
        final item = items[i];
        current = i;
        progress = null;
        if (item.analysis!.isEmpty) {
          item.status = BackupStepStatus.done;
          continue;
        }
        item.status = BackupStepStatus.running;
        notifyListeners();
        await _runItem(item, cancel);
        notifyListeners();
      }
    } on ScanCancelled {
      for (final item in items) {
        if (item.status == BackupStepStatus.running ||
            (item.status == BackupStepStatus.pending &&
                item.analysis != null)) {
          item.status = BackupStepStatus.cancelled;
        }
      }
    } finally {
      await _discard();
      current = null;
      progress = null;
      _cancel = null;
      _b.lock.release(this);
      phase = RestorePhase.finished;
      notifyListeners();
    }
  }

  Future<void> _runItem(RestoreItem item, CancelToken cancel) async {
    final r = await _engine.execute(
      analysis: item.analysis!,
      decision: decisionFor(item),
      replacedDir: p.join(replacedDir!, item.choice.id.replaceAll(':', '-')),
      duplicateLabel: duplicateLabel,
      tmp: _tmp!,
      onProgress: (x) {
        progress = x;
        notifyListeners();
      },
      cancel: cancel,
    );
    item
      ..result = r
      ..warnings = r.warnings
      ..status = switch (r.outcome) {
        RsyncOutcome.ok => BackupStepStatus.done,
        RsyncOutcome.warnings => BackupStepStatus.warnings,
        RsyncOutcome.failed => BackupStepStatus.failed,
      }
      ..message = r.outcome == RsyncOutcome.failed ? r.error : _resultText(r);
    if (item.choice.kind == RestoreKind.secrets &&
        r.outcome != RsyncOutcome.failed) {
      await _tightenSecrets(item.target!, cancel);
    }
  }

  Future<void> _tightenSecrets(String target, CancelToken cancel) async {
    for (final rel in ['.ssh', '.gnupg']) {
      await _engine.makePrivate(p.join(target, rel), cancel: cancel);
    }
  }

  static String _resultText(RestoreResult r) {
    final parts = [
      if (r.copied > 0) '${r.copied} ${r.copied == 1 ? 'novo' : 'novos'}',
      if (r.replaced > 0)
        '${r.replaced} ${r.replaced == 1 ? 'substituído' : 'substituídos'}',
      if (r.duplicated > 0)
        '${r.duplicated} ${r.duplicated == 1 ? 'cópia' : 'cópias'} '
            'com o sufixo do backup',
    ];
    return parts.isEmpty ? 'Nada mudou.' : parts.join(', ');
  }

  bool get replacedSomething => items.any((i) => (i.result?.replaced ?? 0) > 0);

  BackupStepStatus get outcome {
    final s = items.map((i) => i.status).toSet();
    if (s.contains(BackupStepStatus.failed)) return BackupStepStatus.failed;
    if (s.contains(BackupStepStatus.cancelled)) {
      return BackupStepStatus.cancelled;
    }
    if (s.contains(BackupStepStatus.warnings) ||
        s.contains(BackupStepStatus.skipped)) {
      return BackupStepStatus.warnings;
    }
    return BackupStepStatus.done;
  }

  void cancel() => _cancel?.cancel();

  Future<void> openReplaced() async {
    final dir = replacedDir;
    if (dir == null || !Directory(dir).existsSync()) return;
    await services.runner.run('gio', ['open', dir]);
  }

  Future<void> _discard() async {
    for (final d in [_staging, _tmp]) {
      if (d != null && d.existsSync()) await d.delete(recursive: true);
    }
    _staging = null;
    _tmp = null;
  }

  Future<void> back() async {
    if (busy) return;
    await _discard();
    items = const [];
    phase = RestorePhase.idle;
    notifyListeners();
  }

  Future<void> dismiss() async {
    items = const [];
    replacedDir = null;
    phase = RestorePhase.idle;
    await load(dir: backupDir);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    final staging = _staging;
    if (staging != null && staging.existsSync()) {
      staging.deleteSync(recursive: true);
    }
    super.dispose();
  }
}
