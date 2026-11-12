import 'dart:io';

import 'package:disk_cleanup/cleanup/privileged_runner.dart';
import 'package:disk_cleanup/core/models.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/scan/du_scanner.dart';
import 'package:disk_cleanup/scan/preselect.dart';
import 'package:disk_cleanup/scan/scan_controller.dart';
import 'package:disk_cleanup/scan/snapshot_store.dart';
import 'package:disk_cleanup/services.dart';
import 'package:disk_cleanup/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_process_runner.dart';

void main() {
  late Directory tmp;
  late FakeProcessRunner fake;
  late ScanController controller;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dc_scan_');
    final home = p.join(tmp.path, 'home');
    Directory(home).createSync();
    fake = FakeProcessRunner();
    controller = ScanController(
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

  test('docker lido como root não pré-seleciona nem seleciona nada', () async {
    final json = File('test/fixtures/docker_system_df_v.json')
        .readAsStringSync()
        .replaceAll('\n', '');
    fake.when('pkexec', [
      '/bin/sh',
      '-c',
      buildRootScript([DockerCli(DockerOp.inventory, [])]),
    ], RunResult(0, '$json\n__dc_status 0 0\n'.codeUnits, ''));
    await controller.readDockerAsRoot();
    final docker = controller.state.items.where(
      (i) => i.category == CleanupCategory.docker,
    );
    expect(docker, isNotEmpty);
    expect(docker.every((i) => i.requiresRoot), isTrue);
    expect(docker.where((i) => i.preselected), isEmpty);
    expect(docker.where((i) => controller.isSelected(i.id)), isEmpty);
  });

  test('segunda varredura simultânea é ignorada', () async {
    final first = controller.scan();
    expect(controller.running, isTrue);
    await controller.scan();
    await expectLater(first, throwsA(isA<StateError>()));
    expect(fake.calls.where((c) => c.first == 'df'), hasLength(1));
    expect(controller.running, isFalse);
  });

  test('delta semanal e consumidores ignoram tamanho desconhecido', () {
    const unknown = DuResult(
      entries: [],
      total: 0,
      errors: 1,
      permissionDenied: false,
      totalUnknown: true,
    );
    const known = DuResult(
      entries: [],
      total: 500,
      errors: 0,
      permissionDenied: false,
    );
    final weekAgo = Snapshot(
      takenAt: DateTime(2026),
      state: {
        'mappedDirs': {
          '/dados': {'total': 900},
          '/fotos': {'total': 100},
          '/velho': {'total': 0, 'totalUnknown': true},
        },
      },
    );
    final deltas = mappedWeeklyDeltas({
      '/dados': unknown,
      '/fotos': known,
      '/velho': known,
    }, weekAgo);
    expect(deltas, {'/dados': null, '/fotos': 400, '/velho': null});
    final consumers = composeConsumers(
      home: '/home/u',
      mapped: {'/dados': unknown, '/fotos': known},
    );
    expect(consumers.map((c) => c.path), ['/fotos']);
  });
}
