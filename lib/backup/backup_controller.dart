import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../cleanup/safe_deleter.dart';
import '../core/process_runner.dart';
import '../services.dart';
import '../settings/settings.dart';
import '../settings/settings_controller.dart';
import 'backup_manifest.dart';
import 'backup_planner.dart';
import 'backup_services.dart';
import 'browser_profiles.dart';
import 'disk_targets.dart';
import 'pending_store.dart';
import 'restore_planner.dart';
import 'restore_readme.dart';
import 'rsync_runner.dart';
import 'secrets_archiver.dart';

enum BackupStepKind { prepare, secrets, folders, browser, guide }

enum BackupStepStatus {
  pending,
  running,
  done,
  warnings,
  skipped,
  failed,
  cancelled,
}

class BackupStep {
  const BackupStep(
    this.kind,
    this.label, {
    this.status = BackupStepStatus.pending,
    this.bytes,
    this.message,
    this.warnings = const [],
    this.browserId,
    this.retryable = false,
  });

  final BackupStepKind kind;
  final String label;
  final BackupStepStatus status;
  final int? bytes;
  final String? message;
  final List<String> warnings;
  final String? browserId;
  final bool retryable;

  BackupStep copyWith({
    BackupStepStatus? status,
    int? bytes,
    String? message,
    List<String>? warnings,
    bool? retryable,
  }) => BackupStep(
    kind,
    label,
    status: status ?? this.status,
    bytes: bytes ?? this.bytes,
    message: message ?? this.message,
    warnings: warnings ?? this.warnings,
    browserId: browserId,
    retryable: retryable ?? this.retryable,
  );
}

enum BackupPhase { idle, estimating, running, finished }

enum PendingAction {
  later,
  sendLocal,
  bringFromDisk,
  keepBoth,
  deleteFromDisk,
  keepOnDisk,
}

const _replacementChar = '\u{FFFD}';

String _stamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}-'
      '${two(d.hour)}${two(d.minute)}${two(d.second)}';
}

bool validBackupFolderName(String name) =>
    name.trim().isNotEmpty &&
    !name.contains('/') &&
    name != '.' &&
    name != '..';

class ExclusionScan {
  const ExclusionScan(this.dirs) : loading = false, failed = false;
  const ExclusionScan.loading()
    : dirs = const [],
      loading = true,
      failed = false;
  const ExclusionScan.failed()
    : dirs = const [],
      loading = false,
      failed = true;

  final List<ExcludedDir> dirs;
  final bool loading;
  final bool failed;
}

class BackupController extends ChangeNotifier {
  BackupController(this.services, this.settings, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Services services;
  final SettingsController settings;
  final DateTime Function() _now;

  BackupServices get _b => services.backup;
  BackupSettings get config => settings.value.backup;
  String get home => services.home;

  bool loading = false;
  List<DiskTarget> disks = const [];
  String? destination;
  MountInfo? destinationMount;
  bool destinationWritable = false;
  Map<String, MountInfo?> _sourceMounts = const {};
  List<BrowserInstall> browsers = const [];
  Set<String> openBrowsers = const {};
  List<String> detectedSecrets = const [];
  List<PendingItem> pending = const [];
  Set<String> keepOnDisk = const {};
  bool resolving = false;
  Map<String, ExclusionScan> exclusions = const {};

  BackupPhase phase = BackupPhase.idle;
  BackupEstimate? estimate;
  String? estimateError;
  int ignoredBuilds = 0;
  List<BackupStep> steps = const [];
  int? currentStep;
  RsyncProgress? progress;
  CancelToken? _cancel;

  DateTime? _runDate;
  String? _runDestination;
  String? _runBackupDir;
  List<String> _runSecretItems = const [];
  SecretsResult? _secretsResult;
  String? _rulesFile;

  String? get backupDir =>
      destination == null ? null : p.join(destination!, config.folderName);

  String? get readmePath =>
      _runBackupDir == null ? null : p.join(_runBackupDir!, kRestoreReadmeName);

  String? get runBackupDir => _runBackupDir;

  List<String> get selectedBrowserIds =>
      config.browsers ?? [for (final b in browsers) b.spec.id];

  List<String> get secretChoices => [
    ...detectedSecrets,
    for (final s in config.secretItems ?? const <String>[])
      if (!detectedSecrets.contains(s) && _existsInHome(s)) s,
  ];

  List<String> get selectedSecrets => [
    for (final s in config.secretItems ?? detectedSecrets)
      if (_existsInHome(s)) s,
  ];

  bool _existsInHome(String rel) =>
      FileSystemEntity.typeSync(p.join(home, rel), followLinks: false) !=
      FileSystemEntityType.notFound;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      disks = await _b.disks.list();
      await _resolveDestination();
      browsers = _b.browsers.detect();
      openBrowsers = {
        for (final b in browsers)
          if (_b.browsers.isOpen(b)) b.spec.id,
      };
      detectedSecrets = await _b.secrets.detect();
      _sourceMounts = {
        for (final s in config.sources) s: await _b.disks.mountOf(s),
      };
      await _loadPending();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _resolveDestination() async {
    final target = config.target;
    destination = target == null ? null : await _b.disks.resolve(target);
    destinationMount = destination == null
        ? null
        : await _b.disks.mountOf(destination!);
    destinationWritable =
        destination != null &&
        Directory(destination!).existsSync() &&
        await _b.disks.isWritable(destination!);
  }

  Future<void> _update(BackupSettings Function(BackupSettings) change) async {
    estimate = null;
    estimateError = null;
    await settings.update((s) => s.copyWith(backup: change(s.backup)));
    notifyListeners();
  }

  Future<String?> chooseDestination(String path) async {
    final target = await _b.disks.targetFor(p.normalize(path));
    if (target == null) return 'Não foi possível identificar o disco de $path.';
    await _update((b) => b.copyWith(target: target));
    await _resolveDestination();
    notifyListeners();
    return null;
  }

  List<String> _protectedPaths() => {
    for (final rel in [...kSecretCatalog, ...secretChoices]) p.join(home, rel),
    for (final spec in kBrowserCatalog)
      for (final rel in spec.paths) p.join(home, rel),
  }.toList();

  Future<String?> addSource(String path) async {
    final dir = p.normalize(path);
    final name = p.basename(dir);
    final sources = config.sources;
    if (!Directory(dir).existsSync()) return 'Essa pasta não existe.';
    if (sources.contains(dir)) return 'Essa pasta já está na lista.';
    if (name == kBrowserFolder) {
      return 'O nome "$kBrowserFolder" é reservado para os perfis dos navegadores.';
    }
    if (sources.any((s) => p.basename(s) == name)) {
      return 'Já existe uma pasta chamada "$name" na lista. '
          'No backup, cada pasta vira uma pasta com o mesmo nome.';
    }
    if (sources.any((s) => p.isWithin(s, dir) || p.isWithin(dir, s))) {
      return 'Essa pasta está dentro de outra da lista, ou contém uma delas.';
    }
    if (_protectedPaths().any((x) => x == dir || p.isWithin(x, dir))) {
      return 'Essa pasta tem chaves ou perfis de navegador. '
          'Eles entram pelas seções próprias, com proteção.';
    }
    await _update((b) => b.copyWith(sources: [...sources, dir]));
    _sourceMounts = {..._sourceMounts, dir: await _b.disks.mountOf(dir)};
    notifyListeners();
    return null;
  }

  Future<void> removeSource(String dir) {
    exclusions = {...exclusions}..remove(dir);
    return _update(
      (b) => b.copyWith(
        sources: [...b.sources]..remove(dir),
        included: {...b.included}..remove(dir),
      ),
    );
  }

  Future<void> loadExclusions(String source, {bool force = false}) async {
    final current = exclusions[source];
    if (current != null && (current.loading || !force)) return;
    exclusions = {...exclusions, source: const ExclusionScan.loading()};
    notifyListeners();
    ExclusionScan next;
    try {
      next = ExclusionScan(await _b.planner.scanExclusions(source));
    } on Object {
      next = const ExclusionScan.failed();
    }
    if (!config.sources.contains(source)) return;
    exclusions = {...exclusions, source: next};
    notifyListeners();
  }

  List<(String, String)> protectedIn(String source) => [
    for (final rel in {...kSecretCatalog, ...secretChoices})
      if (_existsWithin(source, p.join(home, rel)))
        (p.join(home, rel), 'Chaves e configurações'),
    for (final spec in kBrowserCatalog)
      for (final rel in spec.paths)
        if (_existsWithin(source, p.join(home, rel)))
          (p.join(home, rel), 'Navegadores'),
  ];

  bool _existsWithin(String source, String path) =>
      p.isWithin(source, path) &&
      FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound;

  SourceInclusions inclusionsOf(String source) =>
      config.included[source] ?? const SourceInclusions();

  bool isIncluded(String source, ExcludedDir dir) {
    final inc = inclusionsOf(source);
    return inc.kinds.contains(dir.kind) ||
        inc.paths.contains(p.relative(dir.path, from: source));
  }

  bool? kindState(String source, String kind) {
    final inc = inclusionsOf(source);
    if (inc.kinds.contains(kind)) return true;
    final dirs = exclusions[source]?.dirs ?? const <ExcludedDir>[];
    return dirs.any((d) => d.kind == kind && isIncluded(source, d))
        ? null
        : false;
  }

  Future<void> setKindIncluded(String source, String kind, bool included) {
    final inc = inclusionsOf(source);
    final paths = {
      for (final rel in inc.paths)
        if (p.basename(rel) != kind) rel,
    };
    final kinds = {...inc.kinds}..remove(kind);
    if (included) kinds.add(kind);
    return _setInclusions(source, SourceInclusions(kinds: kinds, paths: paths));
  }

  Future<void> setPathIncluded(String source, ExcludedDir dir, bool included) {
    final inc = inclusionsOf(source);
    final rel = p.relative(dir.path, from: source);
    final kinds = {...inc.kinds};
    final paths = {...inc.paths};
    if (kinds.remove(dir.kind)) {
      for (final d in exclusions[source]?.dirs ?? const <ExcludedDir>[]) {
        if (d.kind == dir.kind) paths.add(p.relative(d.path, from: source));
      }
    }
    if (included) {
      paths.add(rel);
    } else {
      paths.remove(rel);
    }
    return _setInclusions(source, SourceInclusions(kinds: kinds, paths: paths));
  }

  Future<void> _setInclusions(String source, SourceInclusions inc) =>
      _update((b) {
        final included = {...b.included}..remove(source);
        if (!inc.isEmpty) included[source] = inc;
        return b.copyWith(included: included);
      });

  Future<void> setFolderName(String name) =>
      _update((b) => b.copyWith(folderName: name.trim()));

  Future<void> setMirror(bool mirror) =>
      _update((b) => b.copyWith(mirror: mirror));

  Future<void> setAutoSyncOnConnect(bool on) =>
      _update((b) => b.copyWith(autoSyncOnConnect: on));

  Future<void> setAutoSyncHours(int hours) =>
      _update((b) => b.copyWith(autoSyncHours: hours));

  Future<void> toggleBrowser(String id) {
    final ids = [...selectedBrowserIds];
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    return _update((b) => b.copyWith(browsers: ids));
  }

  Future<void> setSecretsEnabled(bool enabled) =>
      _update((b) => b.copyWith(secretsEnabled: enabled));

  Future<void> toggleSecret(String rel) {
    final items = [...selectedSecrets];
    items.contains(rel) ? items.remove(rel) : items.add(rel);
    return _update((b) => b.copyWith(secretItems: items));
  }

  Future<String?> addSecret(String path) async {
    final rel = _b.secrets.relativeToHome(path);
    if (rel == null) {
      return 'Só dá para incluir itens de dentro da sua pasta pessoal.';
    }
    if (!_existsInHome(rel)) return 'Esse item não existe.';
    for (final c in secretChoices) {
      if (c == rel || p.isWithin(c, rel)) return 'Já está incluído em $c.';
    }
    await _update((b) => b.copyWith(secretItems: [...selectedSecrets, rel]));
    return null;
  }

  List<String> get problems {
    final out = <String>[];
    final target = config.target;
    final dest = destination;
    if (target == null) {
      out.add('Escolha onde salvar o backup.');
    } else if (dest == null) {
      out.add('Conecte o disco ${target.label} para fazer o backup.');
    } else {
      if (backupFsProblem(destinationMount?.fsType) case final problem?) {
        out.add(problem);
      }
      if (!destinationWritable) out.add('Não é possível gravar em $dest.');
    }
    if (config.sources.isEmpty) out.add('Adicione ao menos uma pasta.');
    for (final s in config.sources) {
      if (!Directory(s).existsSync()) out.add('A pasta $s não existe mais.');
      if (dest != null && (s == dest || p.isWithin(s, dest))) {
        out.add('O destino fica dentro de $s.');
      }
      if (dest != null && p.isWithin(dest, s)) {
        out.add('A pasta $s fica dentro do destino.');
      }
    }
    if (!validBackupFolderName(config.folderName)) {
      out.add('O nome da pasta do backup não pode ser vazio nem ter "/".');
    }
    if (busyElsewhere) {
      out.add('Espere a restauração terminar para fazer o backup.');
    }
    return out;
  }

  List<String> get notices {
    final out = <String>[];
    final destId = destinationMount?.id;
    final same = [
      for (final s in config.sources)
        if (destId != null && _sourceMounts[s]?.id == destId) p.basename(s),
    ];
    if (same.isNotEmpty) {
      out.add(
        'O backup está no mesmo disco de ${same.join(', ')}. '
        'Ele não protege contra falha do disco.',
      );
    }
    final ids = selectedBrowserIds;
    for (final b in browsers) {
      if (ids.contains(b.spec.id) && openBrowsers.contains(b.spec.id)) {
        out.add(
          'Feche o ${b.spec.label} para incluir o perfil. '
          'Copiar com ele aberto pode corromper o histórico.',
        );
      }
    }
    const keyringDir = '.local/share/keyrings';
    final keyring =
        config.secretsEnabled &&
        selectedSecrets.any(
          (s) =>
              s == keyringDir ||
              p.isWithin(s, keyringDir) ||
              p.isWithin(keyringDir, s),
        );
    if (browsers.any((b) => ids.contains(b.spec.id)) && !keyring) {
      out.add('Sem o keyring, os perfis voltam sem as senhas salvas.');
    }
    return out;
  }

  bool get busyElsewhere => _b.lock.heldByOther(this);

  bool get canRun =>
      problems.isEmpty &&
      phase == BackupPhase.idle &&
      !resolving &&
      !busyElsewhere;

  Future<Directory> _createTmp() =>
      Directory.systemTemp.createTemp('disk-cleanup-');

  Future<void> _deleteTmp(Directory? tmp) async {
    try {
      await tmp?.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  }

  Future<(BackupFilter, String)> _plan(
    Directory tmp,
    CancelToken cancel,
  ) async {
    final filter = await _b.planner.plan(
      config.sources,
      protectedPaths: _protectedPaths(),
      included: config.included,
      cancel: cancel,
    );
    final rules = File(p.join(tmp.path, 'regras'));
    await filter.writeTo(rules);
    return (filter, rules.path);
  }

  Future<BackupEstimate> _estimate(String rules, CancelToken cancel) =>
      _b.planner.estimate(
        filterFile: rules,
        sources: config.sources,
        destination: backupDir!,
        mirror: config.mirror,
        cancel: cancel,
      );

  Future<void> calculate() async {
    if (!canRun || !_b.lock.acquire(this)) return;
    phase = BackupPhase.estimating;
    estimateError = null;
    final cancel = _cancel = CancelToken();
    notifyListeners();
    Directory? tmp;
    try {
      tmp = await _createTmp();
      final (filter, rules) = await _plan(tmp, cancel);
      estimate = await _estimate(rules, cancel);
      ignoredBuilds = filter.keptBuilds.length;
    } on BackupException catch (e) {
      estimateError = e.message;
    } on ScanCancelled {
      estimate = null;
    } on FileSystemException catch (e) {
      estimateError = '${e.message}: ${e.path}';
    } finally {
      await _deleteTmp(tmp);
      _cancel = null;
      _b.lock.release(this);
      phase = BackupPhase.idle;
      notifyListeners();
    }
  }

  void cancel() => _cancel?.cancel();

  void _set(int i, BackupStep step) {
    steps = [...steps]..[i] = step;
    notifyListeners();
  }

  void _onProgress(RsyncProgress p) {
    progress = p;
    notifyListeners();
  }

  bool runIsAuto = false;

  Future<void> start({bool auto = false}) async {
    if (!canRun || !_b.lock.acquire(this)) return;
    try {
      _setUpRun(auto);
    } on Object {
      _b.lock.release(this);
      rethrow;
    }
    phase = BackupPhase.running;
    await _execute(List.generate(steps.length, (i) => i));
  }

  void _setUpRun(bool auto) {
    final chosen = selectedBrowserIds;
    runIsAuto = auto;
    _runSecretItems = config.secretsEnabled ? selectedSecrets : const [];
    _runDate = _now();
    _runDestination = destination;
    _runBackupDir = backupDir;
    _secretsResult = null;
    steps = [
      const BackupStep(BackupStepKind.prepare, 'Preparando'),
      if (_runSecretItems.isNotEmpty && !auto)
        const BackupStep(BackupStepKind.secrets, 'Chaves e configurações'),
      const BackupStep(BackupStepKind.folders, 'Pastas'),
      for (final b in browsers)
        if (chosen.contains(b.spec.id))
          BackupStep(
            BackupStepKind.browser,
            b.spec.label,
            browserId: b.spec.id,
          ),
      const BackupStep(BackupStepKind.guide, 'Guia de restauração'),
    ];
  }

  Future<void> retry(int index) async {
    if (phase != BackupPhase.finished ||
        resolving ||
        !steps[index].retryable ||
        !_b.lock.acquire(this)) {
      return;
    }
    phase = BackupPhase.running;
    if (steps[index].kind == BackupStepKind.browser) {
      browsers = _b.browsers.detect();
      openBrowsers = {
        for (final b in browsers)
          if (_b.browsers.isOpen(b)) b.spec.id,
      };
    }
    final guide = steps.indexWhere((s) => s.kind == BackupStepKind.guide);
    await _execute([index, guide]);
  }

  Future<void> _execute(List<int> order) async {
    final cancel = _cancel = CancelToken();
    final pending = [...order];
    Directory? tmp;
    try {
      tmp = await _createTmp();
      while (pending.isNotEmpty) {
        final i = pending.removeAt(0);
        currentStep = i;
        progress = null;
        _set(
          i,
          steps[i].copyWith(status: BackupStepStatus.running, retryable: false),
        );
        final result = await _runStep(steps[i], tmp, cancel);
        _set(i, result);
        if (result.kind == BackupStepKind.prepare &&
            result.status == BackupStepStatus.failed) {
          for (final j in pending) {
            _set(j, steps[j].copyWith(status: BackupStepStatus.skipped));
          }
          pending.clear();
        }
      }
    } on ScanCancelled {
      for (final i in [?currentStep, ...pending]) {
        _set(i, steps[i].copyWith(status: BackupStepStatus.cancelled));
      }
    } on FileSystemException catch (e) {
      for (final i in [?currentStep, ...pending]) {
        _set(
          i,
          steps[i].copyWith(
            status: BackupStepStatus.failed,
            message: '${e.message}: ${e.path}',
          ),
        );
      }
    } finally {
      await _deleteTmp(tmp);
      _b.lock.release(this);
      _cancel = null;
      currentStep = null;
      progress = null;
      phase = BackupPhase.finished;
      notifyListeners();
    }
  }

  Future<BackupStep> _runStep(
    BackupStep step,
    Directory tmp,
    CancelToken cancel,
  ) async {
    try {
      return switch (step.kind) {
        BackupStepKind.prepare => await _prepare(step, tmp, cancel),
        BackupStepKind.secrets => await _secrets(step, cancel),
        BackupStepKind.folders => await _folders(step, tmp, cancel),
        BackupStepKind.browser => await _browser(step, tmp, cancel),
        BackupStepKind.guide => await _guide(step),
      };
    } on BackupException catch (e) {
      return step.copyWith(status: BackupStepStatus.failed, message: e.message);
    } on FileSystemException catch (e) {
      return step.copyWith(
        status: BackupStepStatus.failed,
        message: '${e.message}: ${e.path}',
      );
    } on ScanCancelled {
      rethrow;
    } on Object catch (e) {
      return step.copyWith(
        status: BackupStepStatus.failed,
        message: 'Erro inesperado: $e',
      );
    }
  }

  Future<BackupStep> _prepare(
    BackupStep step,
    Directory tmp,
    CancelToken cancel,
  ) async {
    final (filter, rules) = await _plan(tmp, cancel);
    _rulesFile = rules;
    ignoredBuilds = filter.keptBuilds.length;
    final est = estimate = await _estimate(rules, cancel);
    final free = (await _b.disks.mountOf(_runDestination!))?.available ?? 0;
    if (est.transferBytes > free) {
      return step.copyWith(
        status: BackupStepStatus.failed,
        message:
            'Falta espaço no destino: o backup precisa copiar '
            '${formatBytes(est.transferBytes)} e há ${formatBytes(free)} livres.',
      );
    }
    return step.copyWith(
      status: BackupStepStatus.done,
      bytes: est.totalBytes,
      message:
          '${formatBytes(est.totalBytes)} no backup, '
          '${formatBytes(est.transferBytes)} a copiar agora',
    );
  }

  Future<BackupStep> _secrets(BackupStep step, CancelToken cancel) async {
    await Directory(_runBackupDir!).create(recursive: true);
    final r = await _b.secrets.archive(
      items: _runSecretItems,
      destination: _runBackupDir!,
      date: _runDate!,
      cancel: cancel,
    );
    return switch (r.outcome) {
      SecretsOutcome.ok || SecretsOutcome.warnings => () {
        _secretsResult = r;
        return step.copyWith(
          status: r.outcome == SecretsOutcome.ok
              ? BackupStepStatus.done
              : BackupStepStatus.warnings,
          bytes: r.bytes,
          message: p.basename(r.path!),
          warnings: r.warnings,
        );
      }(),
      SecretsOutcome.cancelled => step.copyWith(
        status: BackupStepStatus.skipped,
        message: r.message,
        retryable: true,
      ),
      SecretsOutcome.failed => step.copyWith(
        status: BackupStepStatus.failed,
        message: r.message,
        retryable: true,
      ),
    };
  }

  BackupStep _fromRsync(BackupStep step, RsyncResult r) => switch (r.outcome) {
    RsyncOutcome.ok => step.copyWith(
      status: BackupStepStatus.done,
      bytes: r.stats?.totalBytes,
    ),
    RsyncOutcome.warnings => step.copyWith(
      status: BackupStepStatus.warnings,
      bytes: r.stats?.totalBytes,
      message: '${r.warnings.length} arquivos não foram copiados',
      warnings: r.warnings,
    ),
    RsyncOutcome.failed => step.copyWith(
      status: BackupStepStatus.failed,
      message: r.error,
    ),
  };

  Future<String> _rules(Directory tmp, CancelToken cancel) async {
    if (_rulesFile != null && File(_rulesFile!).existsSync()) {
      return _rulesFile!;
    }
    return (await _plan(tmp, cancel)).$2;
  }

  PendingStore get _pendingStore =>
      PendingStore(p.join(services.dataDir, 'pendentes.json'));

  Future<void> loadPending() async {
    await _loadPending();
    notifyListeners();
  }

  Future<void> _loadPending() async {
    final id = config.target?.id;
    final state = id == null
        ? const PendingState()
        : await _pendingStore.load(id);
    pending = state.items;
    keepOnDisk = state.keepOnDisk;
  }

  bool _keptOnDisk(String key) =>
      keepOnDisk.any((k) => k == key || p.isWithin(k, key));

  Set<String> _undecodable(List<String> lines) {
    final names = {for (final s in config.sources) p.basename(s)};
    final out = <String>{};
    for (final line in lines) {
      if (!line.contains(_replacementChar)) continue;
      final path = line.startsWith('*deleting')
          ? line.replaceFirst(RegExp(r'^\*deleting +'), '')
          : (line.length > 12 ? line.substring(12) : '');
      final name = path.split('/').first;
      if (!names.contains(name)) return names;
      out.add(name);
    }
    return out;
  }

  Future<(String, Set<String>)> _holdConflicts(
    String rules,
    Directory tmp,
    CancelToken cancel,
  ) async {
    final dir = _runBackupDir!;
    if (!Directory(dir).existsSync()) return (rules, const <String>{});
    final args = backupRsyncArgs(
      filterFile: rules,
      sources: config.sources,
      destination: dir,
      mirror: config.mirror,
      dryRun: true,
    );
    final lines = <String>[];
    final r = await _b.rsync.runner.runStreaming(
      'rsync',
      [
        args.first,
        '-8',
        '--itemize-changes',
        '--out-format=%i %n',
        ...args.skip(1),
      ],
      onLine: lines.add,
      environment: const {'LC_ALL': 'C'},
      cancel: cancel,
    );
    if (r.exitCode != 0 && r.exitCode != 23 && r.exitCode != 24) {
      throw BackupException(
        interpretRsync(r, const []).error ??
            'Não foi possível comparar com o backup.',
      );
    }
    final undecodable = _undecodable(lines);
    final found = await classifySyncChanges(
      entries: [
        for (final e in parseItemize(lines))
          if (!e.path.contains(_replacementChar)) e,
      ],
      sources: config.sources,
      backupDir: dir,
    );
    await _loadPending();
    pending = [
      for (final i in found)
        if (!(i.kind == PendingKind.wouldDelete && _keptOnDisk(i.key))) i,
    ];
    await _pendingStore.save(
      config.target!.id,
      PendingState(items: pending, keepOnDisk: keepOnDisk),
    );
    notifyListeners();
    final holds = [
      for (final i in found) i.rule,
      for (final k in keepOnDisk) ...[
        'P /${rsyncLiteral(k)}',
        'P /${rsyncEscape(k)}/***',
      ],
      for (final name in undecodable) 'P /${rsyncEscape(name)}/***',
    ];
    if (holds.isEmpty) return (rules, undecodable);
    final out = File(p.join(tmp.path, 'regras-sync'));
    final base = await File(rules).readAsBytes();
    // Pendentes antes do filtro: um "+" de pasta incluída não pode furá-los.
    await out.writeAsBytes([
      ...utf8.encode(holds.join('\x00')),
      if (base.isNotEmpty) ...[0, ...base],
    ]);
    return (out.path, undecodable);
  }

  Future<BackupStep> _folders(
    BackupStep step,
    Directory tmp,
    CancelToken cancel,
  ) async {
    final (rules, undecodable) = await _holdConflicts(
      await _rules(tmp, cancel),
      tmp,
      cancel,
    );
    final r = await _b.rsync.copy(
      filterFile: rules,
      sources: config.sources,
      destination: _runBackupDir!,
      mirror: config.mirror,
      update: undecodable.isNotEmpty,
      onProgress: _onProgress,
      cancel: cancel,
    );
    if (r.outcome != RsyncOutcome.failed) {
      await settings.update(
        (s) => s.copyWith(backup: s.backup.copyWith(lastBackupAt: _runDate)),
      );
    }
    var result = _fromRsync(step, r);
    if (undecodable.isNotEmpty && result.status != BackupStepStatus.failed) {
      final notes = [
        for (final name in undecodable)
          config.mirror
              ? 'Há nomes de arquivo com codificação inválida em $name; '
                    'o espelhamento foi pulado nesta pasta e o que está '
                    'mais novo no disco foi mantido.'
              : 'Há nomes de arquivo com codificação inválida em $name; '
                    'o que está mais novo no disco foi mantido.',
      ];
      result = result.copyWith(
        status: BackupStepStatus.warnings,
        message: result.status == BackupStepStatus.done ? notes.first : null,
        warnings: [...notes, ...result.warnings],
      );
    }
    if (pending.isEmpty || result.status != BackupStepStatus.done) {
      return result;
    }
    return result.copyWith(
      status: BackupStepStatus.warnings,
      message:
          '${pending.length} '
          '${pending.length == 1 ? 'item espera' : 'itens esperam'} '
          'sua decisão em Pendentes',
    );
  }

  String? _sourceDir(String name) =>
      config.sources.where((s) => p.basename(s) == name).firstOrNull;

  Future<String?> resolvePending(Map<String, PendingAction> decisions) async {
    final dir = backupDir;
    final id = config.target?.id;
    if (dir == null || id == null) {
      return 'Conecte o disco do backup para resolver os pendentes.';
    }
    if (phase != BackupPhase.idle || resolving || !_b.lock.acquire(this)) {
      return 'Espere o backup ou a restauração terminar.';
    }
    resolving = true;
    notifyListeners();
    final now = _now();
    final done = <String>{};
    final errors = <String>[];
    final kept = {...keepOnDisk};
    Directory? tmp;
    try {
      tmp = await _createTmp();
      final byKey = {for (final i in pending) i.key: i};
      final groups = <(PendingAction, String), List<PendingItem>>{};
      for (final MapEntry(:key, :value) in decisions.entries) {
        final item = byKey[key];
        if (item == null || value == PendingAction.later) continue;
        groups.putIfAbsent((value, item.source), () => []).add(item);
      }
      for (final MapEntry(key: (action, name), value: items)
          in groups.entries) {
        final local = _sourceDir(name);
        final disk = p.join(dir, name);
        if (local == null) {
          errors.add('A pasta $name não está mais na lista do backup.');
          continue;
        }
        final rels = [for (final i in items) i.rel];
        switch (action) {
          case PendingAction.later:
            break;
          case PendingAction.keepOnDisk:
            kept.addAll(items.map((i) => i.key));
            done.addAll(items.map((i) => i.key));
          case PendingAction.deleteFromDisk:
            final deleter = SafeDeleter(
              allowedRoots: [dir],
              protectedPaths: [
                dir,
                for (final s in config.sources) p.join(dir, p.basename(s)),
              ],
            );
            for (final i in items) {
              final outcome = await deleter.delete(p.join(disk, i.rel));
              if (outcome == DeleteOutcome.deleted ||
                  outcome == DeleteOutcome.missing) {
                done.add(i.key);
              } else {
                errors.add('Não foi possível apagar ${i.key} do disco.');
              }
            }
          case PendingAction.sendLocal ||
              PendingAction.bringFromDisk ||
              PendingAction.keepBoth:
            final toDisk = action == PendingAction.sendLocal;
            final r = await _b.restore.execute(
              analysis: RestoreAnalysis(
                source: toDisk ? local : disk,
                target: toDisk ? disk : local,
                created: const [],
                conflicts: const [],
              ),
              decision: RestoreDecision(
                copy: const [],
                replace: action == PendingAction.keepBoth ? const [] : rels,
                duplicate: action == PendingAction.keepBoth ? rels : const [],
                keep: const [],
              ),
              replacedDir: toDisk
                  ? p.join(dir, '.substituidos', _stamp(now), name)
                  : p.join(services.dataDir, 'substituidos', _stamp(now), name),
              duplicateLabel: 'do disco ${_stamp(now).substring(0, 10)}',
              tmp: tmp,
            );
            if (r.outcome == RsyncOutcome.failed) {
              errors.add(r.error ?? 'A cópia falhou.');
            } else {
              done.addAll(items.map((i) => i.key));
              errors.addAll(r.warnings);
            }
        }
      }
      keepOnDisk = kept;
      pending = [
        for (final i in pending)
          if (!done.contains(i.key)) i,
      ];
      await _pendingStore.save(
        id,
        PendingState(items: pending, keepOnDisk: keepOnDisk),
      );
    } on FileSystemException catch (e) {
      errors.add('${e.message}: ${e.path}');
    } finally {
      await _deleteTmp(tmp);
      _b.lock.release(this);
      resolving = false;
      notifyListeners();
    }
    return errors.isEmpty ? null : errors.take(3).join('\n');
  }

  Future<BackupStep> _browser(
    BackupStep step,
    Directory tmp,
    CancelToken cancel,
  ) async {
    final install = browsers
        .where((b) => b.spec.id == step.browserId)
        .firstOrNull;
    if (install == null) {
      return step.copyWith(
        status: BackupStepStatus.skipped,
        message: 'Perfil não encontrado.',
      );
    }
    if (_b.browsers.isOpen(install)) {
      return step.copyWith(
        status: BackupStepStatus.skipped,
        message: 'Feche o ${install.spec.label} e tente de novo.',
        retryable: true,
      );
    }
    final filter = File(p.join(tmp.path, 'navegadores'));
    await writeBrowserFilter(filter);
    final r = await _b.browsers.copy(
      install,
      backupDir: _runBackupDir!,
      filterFile: filter.path,
      mirror: config.mirror,
      onProgress: _onProgress,
      cancel: cancel,
    );
    final result = _fromRsync(step, r);
    return result.status == BackupStepStatus.failed
        ? result.copyWith(retryable: true)
        : result;
  }

  Future<BackupStep> _guide(BackupStep step) async {
    final dest = _runDestination!;
    final dir = _runBackupDir!;
    await Directory(dir).create(recursive: true);
    await _moveLegacyFiles(dest, dir);
    final secretsFile =
        _secretsResult?.path ??
        switch (listSecretsFiles(dir)) {
          [final latest, ...] => p.join(dir, latest),
          _ => null,
        };
    final gitconfig = File(p.join(home, '.gitconfig'));
    final info = RestoreInfo(
      date: _runDate!,
      destination: dest,
      home: home,
      folderName: p.basename(_runBackupDir!),
      sources: config.sources,
      ignoredBuilds: ignoredBuilds,
      backupBytes: estimate?.totalBytes,
      secrets: secretsFile == null
          ? null
          : RestoredSecrets(
              fileName: p.basename(secretsFile),
              items: _runSecretItems,
            ),
      browsers: [
        for (final spec in kBrowserCatalog)
          if (Directory(p.join(_runBackupDir!, kBrowserFolder, spec.id))
              .existsSync())
            RestoredBrowser(
              id: spec.id,
              label: spec.label,
              profilePath:
                  browsers
                      .where((b) => b.spec.id == spec.id)
                      .firstOrNull
                      ?.path ??
                  p.join(home, spec.paths.first),
            ),
      ],
      gitTools: gitconfig.existsSync()
          ? GitTools.fromGitconfig(await gitconfig.readAsString())
          : const GitTools(),
      device: disks
          .where((d) => d.mountPoint == destinationMount?.target)
          .firstOrNull
          ?.device,
    );
    final readme = File(p.join(dir, kRestoreReadmeName));
    await readme.writeAsString(restoreReadme(info));
    await BackupManifest.write(
      _runBackupDir!,
      BackupManifest(
        date: _runDate,
        hostname: Platform.localHostname,
        home: home,
        folderName: p.basename(_runBackupDir!),
        sources: [
          for (final s in config.sources)
            ManifestSource(path: s, name: p.basename(s)),
        ],
        browsers: [
          for (final b in info.browsers)
            ManifestBrowser(
              id: b.id,
              label: b.label,
              profilePath: b.profilePath,
            ),
        ],
      ),
    );
    await _b.disks.flush(dest);
    return step.copyWith(
      status: BackupStepStatus.done,
      message: kRestoreReadmeName,
    );
  }

  Future<void> _moveLegacyFiles(String dest, String dir) async {
    if (p.equals(dest, dir)) return;
    for (final name in listSecretsFiles(dest)) {
      final target = File(p.join(dir, name));
      if (!target.existsSync()) {
        await File(p.join(dest, name)).rename(target.path);
      }
    }
    final readme = File(p.join(dest, kRestoreReadmeName));
    if (readme.existsSync() &&
        (await readme.readAsString()).startsWith(kRestoreReadmeTitle)) {
      await SafeDeleter(
        allowedRoots: [dest],
        protectedPaths: [dest, dir],
      ).delete(readme.path);
    }
  }

  BackupStepStatus get outcome {
    final s = steps.map((s) => s.status).toSet();
    if (s.contains(BackupStepStatus.failed) ||
        s.contains(BackupStepStatus.running) ||
        s.contains(BackupStepStatus.pending)) {
      return BackupStepStatus.failed;
    }
    if (s.contains(BackupStepStatus.cancelled)) {
      return BackupStepStatus.cancelled;
    }
    if (s.contains(BackupStepStatus.warnings) ||
        s.contains(BackupStepStatus.skipped)) {
      return BackupStepStatus.warnings;
    }
    return BackupStepStatus.done;
  }

  Future<void> dismiss() async {
    phase = BackupPhase.idle;
    steps = const [];
    await refresh();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }
}
