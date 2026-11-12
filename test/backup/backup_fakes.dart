import 'dart:async';
import 'dart:io';

import 'package:disk_cleanup/backup/backup_planner.dart';
import 'package:disk_cleanup/backup/backup_services.dart';
import 'package:disk_cleanup/backup/browser_profiles.dart';
import 'package:disk_cleanup/backup/disk_targets.dart';
import 'package:disk_cleanup/backup/rsync_runner.dart';
import 'package:disk_cleanup/backup/secrets_archiver.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/services.dart';
import 'package:disk_cleanup/settings/backup_settings.dart';
import 'package:disk_cleanup/settings/settings_controller.dart';
import 'package:disk_cleanup/settings/settings_store.dart';
import 'package:disk_cleanup/scan/snapshot_store.dart';
import 'package:path/path.dart' as p;

import '../support/fake_process_runner.dart';

class FakeDisks extends DiskTargets {
  FakeDisks(this.mountPoint, {this.fsType = 'ext4'})
    : super(FakeProcessRunner());

  final String mountPoint;
  String fsType;
  int available = 1000000000000;
  bool connected = true;

  MountInfo get _mount => MountInfo(
    target: mountPoint,
    source: '/dev/sdz1',
    fsType: fsType,
    uuid: 'disco-1',
    label: 'Disco externo',
    available: available,
  );

  @override
  Future<List<DiskTarget>> list() async => [
    if (connected)
      DiskTarget(
        device: '/dev/sdz1',
        mountPoint: mountPoint,
        label: 'Disco externo',
        uuid: 'disco-1',
        fsType: fsType,
        hotplug: true,
        size: 2000000000000,
        available: available,
      ),
  ];

  @override
  Future<MountInfo?> mountOf(String path) async =>
      connected && (path == mountPoint || p.isWithin(mountPoint, path))
      ? _mount
      : MountInfo(
          target: '/',
          source: '/dev/raiz',
          fsType: 'ext4',
          uuid: 'raiz',
        );

  @override
  Future<BackupTarget?> targetFor(String dir) async {
    if (dir != mountPoint && !p.isWithin(mountPoint, dir)) {
      return BackupTarget(
        id: 'raiz',
        label: 'raiz',
        relPath: p.relative(dir, from: '/'),
      );
    }
    final rel = p.relative(dir, from: mountPoint);
    return BackupTarget(
      id: 'disco-1',
      label: 'Disco externo',
      relPath: rel == '.' ? '' : rel,
    );
  }

  @override
  Future<String?> resolve(BackupTarget target) async {
    if (target.id == 'raiz') return p.join('/', target.relPath);
    if (!connected) return null;
    return target.relPath.isEmpty
        ? mountPoint
        : p.join(mountPoint, target.relPath);
  }

  @override
  Future<void> flush(String dir) async {}
}

class FakeSecrets extends SecretsArchiver {
  FakeSecrets({required super.home}) : super(runner: FakeProcessRunner());

  List<String> detected = ['.ssh'];
  SecretsOutcome outcome = SecretsOutcome.ok;
  bool waitForCancel = false;
  final archived = <List<String>>[];

  @override
  Future<List<String>> detect() async => detected;

  @override
  Future<SecretsResult> archive({
    required List<String> items,
    required String destination,
    required DateTime date,
    CancelToken? cancel,
  }) async {
    archived.add(items);
    if (waitForCancel) {
      if (cancel!.isCancelled) throw const ScanCancelled();
      final done = Completer<void>();
      cancel.onCancel(done.complete);
      await done.future;
      throw const ScanCancelled();
    }
    if (outcome != SecretsOutcome.ok) {
      return SecretsResult(outcome, message: 'janela de senha foi fechada');
    }
    final out = File(p.join(destination, secretsFileName(date)))
      ..writeAsStringSync('cifrado');
    return SecretsResult(SecretsOutcome.ok, path: out.path, bytes: 7);
  }

  final extracted = <String>[];
  Map<String, String> packed = {'.ssh/id_ed25519': 'chave do backup'};

  @override
  Future<SecretsResult> extract({
    required String file,
    required String staging,
    CancelToken? cancel,
  }) async {
    extracted.add(file);
    if (outcome != SecretsOutcome.ok) {
      return SecretsResult(outcome, message: 'janela de senha foi fechada');
    }
    for (final MapEntry(:key, :value) in packed.entries) {
      File(p.join(staging, key))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    return SecretsResult(SecretsOutcome.ok, path: staging);
  }
}

class BackupFixture {
  BackupFixture() {
    tmp = Directory.systemTemp.createTempSync('backup_ctrl_');
    home = p.join(tmp.path, 'home');
    hd = p.join(tmp.path, 'hd');
    Directory(hd).createSync(recursive: true);
    file('projetos/app/main.dart', 'void main() {}');
    file('projetos/app/node_modules/dep/index.js');
    file('.ssh/id_ed25519', 'chave');
    file('.config/google-chrome/Local State', '{}');
    file('.config/google-chrome/Default/History', 'h');
    file('.config/google-chrome/Default/Cache/x');
    disks = FakeDisks(hd);
    secrets = FakeSecrets(home: home);
    final runner = SystemProcessRunner();
    final rsync = RsyncRunner(runner);
    services = Services(
      home: home,
      runner: FakeProcessRunner(),
      settingsStore: SettingsStore(p.join(tmp.path, 'settings.json')),
      snapshots: SnapshotStore(p.join(tmp.path, 'snap')),
      trashDir: p.join(home, '.local/share/Trash'),
      backup: BackupServices(
        disks: disks,
        planner: BackupPlanner(runner),
        rsync: rsync,
        browsers: BrowserProfiles(
          home: home,
          rsync: rsync,
          hostname: 'maquina',
          pidAlive: alive.contains,
        ),
        secrets: secrets,
      ),
    );
    settings = SettingsController(services.settingsStore, home);
  }

  late final Directory tmp;
  late final String home;
  late final String hd;
  late final FakeDisks disks;
  late final FakeSecrets secrets;
  late final Services services;
  late final SettingsController settings;
  final alive = <int>{};

  void file(String rel, [String content = 'x']) {
    File(p.join(home, rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  void openChrome() {
    Link(p.join(home, '.config/google-chrome/SingletonLock'))
        .createSync('maquina-4242');
    alive.add(4242);
  }

  void dispose() => tmp.deleteSync(recursive: true);
}
