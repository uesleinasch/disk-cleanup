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

  CleanupItem dockerRoot(String id, DockerOp op, List<String> ids) =>
      CleanupItem(
        id: id,
        category: CleanupCategory.docker,
        title: id,
        note: '',
        bytes: 10,
        risk: RiskLevel.attention,
        requiresRoot: true,
        preselected: false,
        action: DockerAction(op, ids),
      );

  final dockerItems = [
    dockerRoot('docker:buildcache', DockerOp.pruneBuildCache, []),
    dockerRoot('docker:containers', DockerOp.removeContainers, [
      'abcdef123456',
    ]),
    dockerRoot('docker:volumes', DockerOp.removeVolumes, ['vol-old']),
  ];
  final dockerCommands = [
    DockerCli(DockerOp.pruneBuildCache, []),
    DockerCli(DockerOp.removeContainers, ['abcdef123456']),
    DockerCli(DockerOp.removeVolumes, ['vol-old']),
  ];

  test('journal e três itens docker root usam um único pkexec', () async {
    fake.when(
      'pkexec',
      [
        '/bin/sh',
        '-c',
        buildRootScript([JournalVacuum(), AptClean(), ...dockerCommands]),
      ],
      RunResult(
        0,
        utf8.encode(
          [for (var i = 0; i < 5; i++) '__dc_status $i ${i == 4 ? 1 : 0}']
              .join('\n'),
        ),
        '',
      ),
    );
    final result = await controller.execute([rootItem, ...dockerItems]);
    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.first, 'pkexec');
    expect(result.succeeded, 3);
    expect(result.failed, 1);
    expect(result.doneIds, isNot(contains('docker:volumes')));
  });

  test('senha cancelada com docker root conta como cancelado', () async {
    fake.when('pkexec', [
      '/bin/sh',
      '-c',
      buildRootScript(dockerCommands),
    ], const RunResult(126, [], ''));
    final result = await controller.execute(dockerItems);
    expect(result.cancelled, isTrue);
    expect(result.failed, 0);
  });

  test('falha ao esvaziar a lixeira não interrompe o lote', () async {
    final trash = p.join(home, '.local', 'share', 'Trash');
    final locked = Directory(p.join(trash, 'files', 'travada'))
      ..createSync(recursive: true);
    File(p.join(locked.path, 'x')).writeAsStringSync('x');
    Directory(p.join(trash, 'info')).createSync(recursive: true);
    Process.runSync('chmod', ['555', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));

    final result = await controller.execute([
      item('trash:all', const EmptyTrashAction()),
      item('cache:uv', DeletePathsAction([p.join(home, '.cache', 'uv')])),
    ]);
    final isRoot =
        Process.runSync('id', ['-u']).stdout.toString().trim() == '0';
    if (!isRoot) expect(result.failed, 1);
    expect(result.doneIds, contains('cache:uv'));
  });

  test('mover para a lixeira fora das raízes permitidas é recusado', () async {
    final outside = File(p.join(tmp.path, 'fora', 'a.txt'))
      ..createSync(recursive: true);
    final inside = File(p.join(home, 'docs', 'b.txt'))
      ..createSync(recursive: true);
    final result = await controller.execute([
      item('large:fora', TrashPathsAction([outside.path])),
      item('large:dentro', TrashPathsAction([inside.path])),
    ]);
    expect(result.failed, 1);
    expect(result.doneIds, ['large:dentro']);
    expect(outside.existsSync(), isTrue);
    expect(inside.existsSync(), isFalse);
  });

  test('undo restaura o que pode e conta o que não voltou', () async {
    final a = File(p.join(home, 'docs', 'a.txt'))..createSync(recursive: true);
    final b = File(p.join(home, 'docs', 'b.txt'))..createSync(recursive: true);
    final result = await controller.execute([
      item('large:a', TrashPathsAction([a.path])),
      item('large:b', TrashPathsAction([b.path])),
    ]);
    expect(result.undo, hasLength(2));
    a.createSync();
    final undo = await controller.undo(result.undo);
    expect(undo.restored, 1);
    expect(undo.failed, 1);
    expect(b.existsSync(), isTrue);
  });

  test('edição aninhada mantém o projeto ativo', () async {
    final proj = p.join(home, 'proj');
    File(p.join(proj, 'package.json')).createSync(recursive: true);
    File(p.join(proj, 'src', 'deep', 'main.ts')).createSync(recursive: true);
    File(p.join(proj, 'node_modules', 'x.js')).createSync(recursive: true);
    final old = DateTime(2020).millisecondsSinceEpoch ~/ 1000;
    final paths = [
      for (final e in Directory(proj).listSync(recursive: true)) e.path,
    ]..sort((a, b) => b.length.compareTo(a.length));
    for (final path in paths) {
      Process.runSync('touch', ['-d', '@$old', path]);
    }
    final nm = item(
      'build:nm',
      DeletePathsAction([p.join(proj, 'node_modules')]),
      category: CleanupCategory.build,
    );
    Process.runSync('touch', [p.join(proj, 'src', 'deep', 'main.ts')]);
    final result = await controller.execute([nm]);
    expect(result.skipped, 1);
    expect(Directory(p.join(proj, 'node_modules')).existsSync(), isTrue);
  });

  test('projeto parado tem o build removido', () async {
    final proj = p.join(home, 'proj');
    File(p.join(proj, 'package.json')).createSync(recursive: true);
    File(p.join(proj, 'src', 'deep', 'main.ts')).createSync(recursive: true);
    File(p.join(proj, 'node_modules', 'x.js')).createSync(recursive: true);
    final old = DateTime(2020).millisecondsSinceEpoch ~/ 1000;
    final paths = [
      for (final e in Directory(proj).listSync(recursive: true)) e.path,
    ]..sort((a, b) => b.length.compareTo(a.length));
    for (final path in paths) {
      Process.runSync('touch', ['-d', '@$old', path]);
    }
    Process.runSync('touch', [p.join(proj, 'node_modules', 'x.js')]);
    final result = await controller.execute([
      item(
        'build:nm',
        DeletePathsAction([p.join(proj, 'node_modules')]),
        category: CleanupCategory.build,
      ),
    ]);
    expect(result.succeeded, 1);
    expect(Directory(p.join(proj, 'node_modules')).existsSync(), isFalse);
  });
}
