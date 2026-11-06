import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../cleanup/docker_service.dart';
import '../cleanup/privileged_runner.dart';
import '../core/models.dart';
import '../core/process_runner.dart';
import '../services.dart';
import '../settings/settings.dart';
import 'du_scanner.dart';
import 'preselect.dart';
import 'scan_state.dart';
import 'snapshot_store.dart';

const kSystemDirs = ['/var/lib/flatpak', '/var/lib/snapd', '/var/log'];

int? parseRootDuBytes(String stdout) {
  final record = stdout.split('\u0000').first;
  final tab = record.indexOf('\t');
  if (tab <= 0) return null;
  return int.tryParse(record.substring(0, tab).trim());
}

class ScanController extends ChangeNotifier {
  ScanController(this.services);

  final Services services;
  ScanState _state = const ScanState();
  Set<String> _selected = {};
  CancelToken? _cancel;

  ScanState get state => _state;
  bool get running => _state.progress.running;

  bool isSelected(String id) => _selected.contains(id);

  List<CleanupItem> selectedIn(Set<CleanupCategory> categories) => [
    for (final i in _state.items)
      if (categories.contains(i.category) && _selected.contains(i.id)) i,
  ];

  List<CleanupItem> get preselected => [
    for (final i in _state.items)
      if (i.preselected) i,
  ];

  void toggle(String itemId) {
    _selected.contains(itemId)
        ? _selected.remove(itemId)
        : _selected.add(itemId);
    notifyListeners();
  }

  void setSelection(CleanupCategory c, bool selected) {
    for (final i in _state.items.where((i) => i.category == c)) {
      selected ? _selected.add(i.id) : _selected.remove(i.id);
    }
    notifyListeners();
  }

  void removeItems(Iterable<String> ids) {
    final gone = ids.toSet();
    _selected.removeAll(gone);
    _state = _state.copyWith(
      items: [
        for (final i in _state.items)
          if (!gone.contains(i.id)) i,
      ],
    );
    notifyListeners();
  }

  void replaceDocker(DockerInventory inventory) {
    _state = _state.copyWith(
      docker: inventory,
      items: [
        for (final i in _state.items)
          if (i.category != CleanupCategory.docker) i,
        ...inventory.toItems(),
      ],
    );
    _selected.addAll(
      inventory.toItems().where((i) => i.preselected).map((i) => i.id),
    );
    notifyListeners();
  }

  Future<void> readDockerAsRoot() async {
    replaceDocker(await services.docker.inventoryAsRoot());
  }

  final Set<String> measuring = {};

  Future<void> measureDir(String dir) async {
    if (measuring.contains(dir)) return;
    measuring.add(dir);
    notifyListeners();
    try {
      final r = await services.du.childrenSizes(dir);
      final locked = {..._state.lockedDirs};
      r.permissionDenied ? locked.add(dir) : locked.remove(dir);
      _state = _state.copyWith(
        mappedDirs: {..._state.mappedDirs, dir: r},
        lockedDirs: locked,
      );
    } on Object catch (e) {
      debugPrint('Falha ao medir $dir: $e');
    } finally {
      measuring.remove(dir);
      notifyListeners();
    }
  }

  Future<bool> measureLocked(String dir) async {
    final result = await services.root.run([DuMeasure(dir)]);
    if (result.cancelled || result.exitCodes[0] != 0) return false;
    final bytes = parseRootDuBytes(result.stdout);
    if (bytes == null) return false;
    _state = _state.copyWith(
      mappedDirs: {
        ..._state.mappedDirs,
        dir: DuResult(
          entries: const [],
          total: bytes,
          errors: 0,
          permissionDenied: false,
        ),
      },
      lockedDirs: {..._state.lockedDirs}..remove(dir),
    );
    notifyListeners();
    return true;
  }

  Future<void> loadLast() async {
    final last = await services.snapshots.latest();
    if (last == null) return;
    try {
      _state = ScanState.fromJson(last.state);
      _selected = {
        for (final i in _state.items)
          if (i.preselected) i.id,
      };
      notifyListeners();
    } on Object {
      return;
    }
  }

  void cancel() => _cancel?.cancel();

  Future<void> scan() async {
    if (running) return;
    final cancel = CancelToken();
    _cancel = cancel;
    final previous = _state;
    final settings = await services.settingsStore.load(services.home);
    final mapped = settings.mappedDirs;
    final steps = mapped.length + 7;
    var done = 0;
    void step(String label) {
      _state = _state.copyWith(
        progress: ScanProgressInfo(
          currentDir: label,
          doneDirs: done++,
          totalDirs: steps,
          running: true,
        ),
      );
      notifyListeners();
    }

    try {
      step('Disco');
      final volumes = await services.disk.volumes();

      final mappedResults = <String, DuResult>{};
      final locked = <String>{};
      for (final dir in mapped) {
        step(dir);
        final r = await services.du.childrenSizes(dir, cancel: cancel);
        mappedResults[dir] = r;
        if (r.permissionDenied) locked.add(dir);
      }

      step('Sistema');
      final systemSizes = await services.du.sizesOf(
        kSystemDirs,
        cancel: cancel,
      );
      final systemItems = await services.system.scan();

      step('Caches');
      final cacheItems = await services.caches.scan(services.home);

      step('Builds');
      final excludes = [services.trashDir, p.join(services.home, '.cache')];
      final artifacts = await services.builds.find(
        mapped,
        settings.buildRules,
        excludeRoots: excludes,
        cancel: cancel,
      );

      step('Arquivos grandes');
      final largeFiles = await services.largeFiles.find(
        mapped,
        excludeRoots: [services.trashDir],
        cancel: cancel,
      );

      step('Docker');
      final docker = await services.docker.inventory();

      step('Lixeira');
      final trashItems = await _trashItems();

      final now = services.now();
      final items = _applyPreselection(
        [
          ...cacheItems,
          ...systemItems,
          for (final a in artifacts) buildItem(a, now),
          ...docker.toItems(),
          ...trashItems,
        ],
        settings,
        now,
      );

      final weekAgo = await services.snapshots.closestTo(
        now.subtract(const Duration(days: 7)),
      );
      final deltas = <String, int?>{
        for (final e in mappedResults.entries)
          e.key: weeklyDelta(e.value.total, _totalIn(weekAgo, e.key)),
      };

      _state = ScanState(
        updatedAt: now,
        volumes: volumes,
        alert: worstAlert(volumes, mapped, settings),
        consumers: composeConsumers(
          home: services.home,
          mapped: mappedResults,
          dockerBytes: docker.available
              ? docker.imagesBytes +
                    docker.containersBytes +
                    docker.volumesBytes +
                    docker.buildCacheBytes
              : null,
          systemDirs: systemSizes,
        ),
        mappedDirs: mappedResults,
        weeklyDeltas: deltas,
        lockedDirs: locked,
        items: items,
        docker: docker,
        largeFiles: largeFiles,
      );
      _selected = {
        for (final i in items)
          if (i.preselected) i.id,
      };
      notifyListeners();
      await services.snapshots.save(
        Snapshot(takenAt: now, state: _state.toJson()),
      );
      await services.snapshots.prune(now: now);
    } on ScanCancelled {
      _state = previous;
      notifyListeners();
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      if (_state.progress.running) {
        _state = _state.copyWith(progress: const ScanProgressInfo());
        notifyListeners();
      }
    }
  }

  List<CleanupItem> _applyPreselection(
    List<CleanupItem> items,
    Settings s,
    DateTime now,
  ) => [
    for (final i in items)
      withPreselected(
        i,
        i.category == CleanupCategory.build
            ? shouldPreselect(i, s, now)
            : i.preselected && shouldPreselect(i, s, now),
      ),
  ];

  Future<List<CleanupItem>> _trashItems() async {
    final listing = await services.trash.list();
    if (listing.isEmpty) return [];
    final total = listing.fold(0, (a, e) => a + e.bytes);
    return [
      CleanupItem(
        id: 'trash:all',
        category: CleanupCategory.trash,
        title: 'Esvaziar a lixeira',
        note: '${listing.length} itens',
        bytes: total,
        risk: RiskLevel.danger,
        requiresRoot: false,
        preselected: false,
        action: const EmptyTrashAction(),
      ),
      for (final e in listing)
        CleanupItem(
          id: 'trash:${e.name}',
          category: CleanupCategory.trash,
          title: e.name,
          path: e.originalPath,
          note: 'Sairá da lixeira para sempre',
          bytes: e.bytes,
          risk: RiskLevel.danger,
          requiresRoot: false,
          preselected: false,
          lastModified: e.deletedAt,
          action: DeletePathsAction([
            p.join(services.trashDir, 'files', e.name),
            p.join(services.trashDir, 'info', '${e.name}.trashinfo'),
          ]),
        ),
    ];
  }

  static int? _totalIn(Snapshot? s, String dir) {
    final dirs = s?.state['mappedDirs'];
    if (dirs is! Map) return null;
    final entry = dirs[dir];
    if (entry is! Map) return null;
    return entry['total'] as int?;
  }
}
