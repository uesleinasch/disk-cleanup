import 'dart:io';

import 'package:disk_cleanup/app.dart';
import 'package:disk_cleanup/cleanup/docker_service.dart';
import 'package:disk_cleanup/cleanup/privileged_runner.dart';
import 'package:disk_cleanup/core/models.dart';
import 'package:disk_cleanup/disk/alert.dart';
import 'package:disk_cleanup/disk/disk_info.dart';
import 'package:disk_cleanup/scan/du_scanner.dart';
import 'package:disk_cleanup/scan/large_files.dart';
import 'package:disk_cleanup/scan/preselect.dart';
import 'package:disk_cleanup/scan/scan_state.dart';
import 'package:disk_cleanup/scan/snapshot_store.dart';
import 'package:disk_cleanup/services.dart';
import 'package:disk_cleanup/settings/settings_controller.dart';
import 'package:disk_cleanup/settings/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/fake_process_runner.dart';

CleanupItem it(
  String id,
  CleanupCategory c,
  int gb, {
  RiskLevel risk = RiskLevel.safe,
  bool root = false,
  bool pre = true,
  CleanupAction action = const DeletePathsAction(['/nao/existe']),
}) => CleanupItem(
  id: id,
  category: c,
  title: id,
  path: '/h/$id',
  note: 'nota',
  bytes: gb * 1000000000,
  risk: risk,
  requiresRoot: root,
  preselected: pre,
  action: action,
);

ScanState sample(String home) => ScanState(
  updatedAt: DateTime.now().subtract(const Duration(minutes: 3)),
  volumes: const [
    VolumeUsage(
      device: '/dev/nvme0n1p2',
      fsType: 'ext4',
      mountPoint: '/',
      size: 502500000000,
      used: 433800000000,
      available: 44000000000,
    ),
    VolumeUsage(
      device: '/dev/sdb1',
      fsType: 'ext4',
      mountPoint: '/media/u/Dados com espaço',
      size: 1000000000000,
      used: 400000000000,
      available: 600000000000,
    ),
  ],
  alert: AlertLevel.warning,
  consumers: [
    for (var i = 0; i < 9; i++)
      Consumer(
        label: 'pasta-$i',
        path: '$home/pasta-$i',
        bytes: (9 - i) * 5000000000,
        kind: ConsumerKind.directory,
      ),
  ],
  mappedDirs: {
    home: DuResult(
      entries: [DirEntrySize('$home/pasta-0', 45000000000)],
      total: 300000000000,
      errors: 0,
      permissionDenied: false,
    ),
  },
  weeklyDeltas: {home: 2100000000},
  lockedDirs: const {'/var/lib/docker'},
  items: [
    it('cache:uv', CleanupCategory.cache, 14),
    it(
      'system:journal',
      CleanupCategory.system,
      4,
      root: true,
      pre: false,
      action: RootAction([JournalVacuum()]),
    ),
    it('build:node_modules', CleanupCategory.build, 4),
    it(
      'trash:a.7z',
      CleanupCategory.trash,
      3,
      risk: RiskLevel.danger,
      pre: false,
    ),
    it(
      'docker:buildcache',
      CleanupCategory.docker,
      23,
      action: const DockerAction(DockerOp.pruneBuildCache, []),
    ),
  ],
  docker: const DockerInventory(
    available: true,
    needsRoot: false,
    imagesBytes: 26400000000,
    containersBytes: 3800000000,
    volumesBytes: 5100000000,
    buildCacheBytes: 43100000000,
    buildCacheReclaimable: 23300000000,
    stopped: [],
    unusedImages: [],
    unusedVolumes: [],
  ),
  largeFiles: [
    LargeFile(
      path: '$home/Downloads/Dispatch [BASE][01008BA02525A000][v0].nsz',
      bytes: 6700000000,
      lastAccess: DateTime(2026, 7, 1),
      modified: DateTime(2026, 7, 1),
    ),
  ],
);

bool settingsLoaded(WidgetTester t) =>
    find.text('Pode liberar com segurança').evaluate().isEmpty;

void main() {
  late Directory tmp;
  late Services services;
  late SettingsController settings;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('dc_app_');
    final home = p.join(tmp.path, 'home')..toString();
    Directory(home).createSync();
    services = Services(
      home: home,
      runner: FakeProcessRunner(),
      settingsStore: SettingsStore(p.join(tmp.path, 'settings.json')),
      snapshots: SnapshotStore(p.join(tmp.path, 'snap')),
      trashDir: p.join(home, '.local', 'share', 'Trash'),
    );
    settings = SettingsController(services.settingsStore, home);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> boot(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(
      () => services.snapshots.save(
        Snapshot(
          takenAt: DateTime.now(),
          state: sample(services.home).toJson(),
        ),
      ),
    );
    await t.pumpWidget(
      DiskCleanupApp(
        services: services,
        settings: settings,
        scanOnStart: false,
      ),
    );
    for (var i = 0; i < 20 && settingsLoaded(t); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  for (final size in const [Size(720, 560), Size(1920, 1080)]) {
    testWidgets('navega pelas 6 telas sem overflow em $size', (t) async {
      await boot(t, size);
      expect(find.text('Pode liberar com segurança'), findsOneWidget);
      expect(find.textContaining('Espaço em disco baixo'), findsOneWidget);
      final keys = [
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit1,
      ];
      for (final k in keys) {
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.sendKeyEvent(k);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    });
  }

  testWidgets('Liberar com segurança abre o diálogo leve', (t) async {
    await boot(t, const Size(1280, 900));
    await t.tap(find.textContaining('com segurança').last);
    await t.pumpAndSettle();
    expect(find.text('Limpar 41,0 GB?'), findsOneWidget);
    expect(
      find.text(
        'Estes itens são recriados automaticamente quando necessário. '
        'Nenhum arquivo pessoal será apagado.',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(find.text('Limpar 41,0 GB?'), findsNothing);
  });

  testWidgets('diálogo avisa da senha quando há item root', (t) async {
    await boot(t, const Size(1280, 900));
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.digit4);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(find.text('requer admin'), findsOneWidget);
    await t.tap(find.text('system:journal'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Limpar 18,0 GB'));
    await t.pumpAndSettle();
    expect(
      find.text(
        'O sistema vai pedir sua senha de administrador para concluir.',
      ),
      findsOneWidget,
    );
  });
}
