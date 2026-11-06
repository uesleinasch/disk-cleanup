import 'dart:convert';
import 'dart:io';

import 'package:disk_cleanup/cleanup/cleanup_controller.dart';
import 'package:disk_cleanup/cleanup/privileged_runner.dart';
import 'package:disk_cleanup/core/models.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/scan/snapshot_store.dart';
import 'package:disk_cleanup/services.dart';
import 'package:disk_cleanup/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_process_runner.dart';

CleanupItem item(
  String id,
  CleanupAction action, {
  int bytes = 100,
  bool root = false,
  CleanupCategory category = CleanupCategory.cache,
}) => CleanupItem(
  id: id,
  category: category,
  title: id,
  note: '',
  bytes: bytes,
  risk: RiskLevel.safe,
  requiresRoot: root,
  preselected: true,
  action: action,
);

void main() {
  late Directory tmp;
  late String home;
  late FakeProcessRunner fake;
  late CleanupController controller;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dc_cleanup_');
    home = p.join(tmp.path, 'home');
    Directory(p.join(home, '.cache', 'uv')).createSync(recursive: true);
    File(p.join(home, '.cache', 'uv', 'a.whl')).writeAsStringSync('x');
    fake = FakeProcessRunner();
    controller = CleanupController(
      Services(
        home: home,
        runner: fake,
        settingsStore: SettingsStore(p.join(tmp.path, 'settings.json')),
        snapshots: SnapshotStore(p.join(tmp.path, 'snap')),
        trashDir: p.join(home, '.local', 'share', 'Trash'),
      ),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  final rootItem = item(
    'system:journal',
    RootAction([JournalVacuum(), AptClean()]),
    root: true,
  );

  test('um pkexec por lote, caminho ausente é ignorado', () async {
    fake.when('pkexec', [
      '/bin/sh',
      '-c',
      buildRootScript([JournalVacuum(), AptClean()]),
    ], RunResult(0, utf8.encode('__dc_status 0 0\n__dc_status 1 0\n'), ''));
    final result = await controller.execute([
      item('cache:uv', DeletePathsAction([p.join(home, '.cache', 'uv')])),
      item('cache:pip', DeletePathsAction([p.join(home, '.cache', 'pip')])),
      rootItem,
    ]);
    expect(fake.calls.where((c) => c.first == 'pkexec'), hasLength(1));
    expect(result.skipped, 1);
    expect(result.succeeded, 2);
    expect(result.freedBytes, 200);
    expect(Directory(p.join(home, '.cache', 'uv')).existsSync(), isFalse);
  });

  test('senha cancelada aborta o lote inteiro', () async {
    fake.when('pkexec', [
      '/bin/sh',
      '-c',
      buildRootScript([JournalVacuum(), AptClean()]),
    ], const RunResult(126, [], ''));
    final result = await controller.execute([
      item('cache:uv', DeletePathsAction([p.join(home, '.cache', 'uv')])),
      rootItem,
    ]);
    expect(result.cancelled, isTrue);
    expect(result.freedBytes, 0);
    expect(Directory(p.join(home, '.cache', 'uv')).existsSync(), isTrue);
  });

  test('build de projeto que voltou a ser ativo é pulado', () async {
    final proj = Directory(p.join(home, 'proj'))..createSync();
    File(p.join(proj.path, 'package.json')).writeAsStringSync('{}');
    Directory(p.join(proj.path, 'node_modules')).createSync();
    final result = await controller.execute([
      item(
        'build:nm',
        DeletePathsAction([p.join(proj.path, 'node_modules')]),
        category: CleanupCategory.build,
      ),
    ]);
    expect(result.skipped, 1);
    expect(Directory(p.join(proj.path, 'node_modules')).existsSync(), isTrue);
  });

  test('highestRisk e batchNeedsRoot', () {
    final attention = CleanupItem(
      id: 'd',
      category: CleanupCategory.docker,
      title: 'd',
      note: '',
      bytes: 1,
      risk: RiskLevel.attention,
      requiresRoot: false,
      preselected: false,
      action: const DockerAction(DockerOp.removeVolumes, ['v']),
    );
    expect(highestRisk([rootItem, attention]), RiskLevel.attention);
    expect(batchNeedsRoot([attention]), isFalse);
    expect(batchNeedsRoot([attention, rootItem]), isTrue);
  });
}
