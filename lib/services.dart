import 'dart:io';

import 'package:path/path.dart' as p;

import 'backup/backup_services.dart';
import 'cleanup/docker_service.dart';
import 'cleanup/privileged_runner.dart';
import 'cleanup/safe_deleter.dart';
import 'cleanup/trash_service.dart';
import 'core/process_runner.dart';
import 'core/system_paths.dart';
import 'disk/disk_info.dart';
import 'scan/build_finder.dart';
import 'scan/cache_catalog.dart';
import 'scan/du_scanner.dart';
import 'scan/large_files.dart';
import 'scan/snapshot_store.dart';
import 'settings/settings.dart';
import 'settings/settings_store.dart';

class Services {
  Services({
    required this.home,
    required this.runner,
    required this.settingsStore,
    required this.snapshots,
    required this.trashDir,
    String? dataDir,
    String? runtimeDir,
    DateTime Function()? now,
    BackupServices? backup,
  }) : dataDir = dataDir ?? p.join(home, '.local', 'share', 'disk-cleanup'),
       runtimeDir = runtimeDir ?? Directory.systemTemp.path,
       now = now ?? DateTime.now,
       backup = backup ?? BackupServices.system(home, runner),
       du = DuScanner(runner),
       disk = DiskInfoService(runner),
       root = PrivilegedRunner(runner) {
    builds = BuildFinder(runner, du);
    largeFiles = LargeFileFinder(runner);
    caches = CacheInventory(runner, du);
    system = SystemInventory(runner, du);
    trash = TrashService(trashDir: trashDir, runner: runner, du: du);
    docker = DockerService(runner, root);
  }

  factory Services.system() {
    final env = Platform.environment;
    final home = env['HOME'] ?? '/';
    final dataHome = (env['XDG_DATA_HOME'] ?? '').isNotEmpty
        ? env['XDG_DATA_HOME']!
        : p.join(home, '.local', 'share');
    return Services(
      home: home,
      runner: SystemProcessRunner(),
      settingsStore: SettingsStore(SettingsStore.defaultPath(env, home)),
      snapshots: SnapshotStore(p.join(dataHome, 'disk-cleanup', 'snapshots')),
      trashDir: p.join(dataHome, 'Trash'),
      dataDir: p.join(dataHome, 'disk-cleanup'),
      runtimeDir: (env['XDG_RUNTIME_DIR'] ?? '').isNotEmpty
          ? env['XDG_RUNTIME_DIR']
          : null,
    );
  }

  final String home;
  final ProcessRunner runner;
  final SettingsStore settingsStore;
  final SnapshotStore snapshots;
  final String trashDir;
  final String dataDir;
  final String runtimeDir;
  final DateTime Function() now;
  final DuScanner du;
  final DiskInfoService disk;
  final PrivilegedRunner root;
  late final BuildFinder builds;
  late final LargeFileFinder largeFiles;
  late final CacheInventory caches;
  late final SystemInventory system;
  late final TrashService trash;
  late final DockerService docker;
  final BackupServices backup;

  List<String> safeMappedDirs(Settings s) =>
      allowedMappedDirs(s.mappedDirs, home: home);

  SafeDeleter deleter(Settings s) => SafeDeleter(
    home: home,
    allowedRoots: [home, ...safeMappedDirs(s)],
    protectedPaths: [
      home,
      ...s.mappedDirs,
      p.join(home, '.cache'),
      p.join(home, '.config'),
      p.join(home, '.local'),
      p.join(home, '.local', 'share'),
      trashDir,
      p.join(trashDir, 'files'),
      p.join(trashDir, 'info'),
    ],
  );
}
