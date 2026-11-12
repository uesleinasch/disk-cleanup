import 'dart:async';
import 'dart:io';

import 'package:disk_cleanup/cleanup/cleanup_controller.dart';
import 'package:disk_cleanup/cleanup/trash_service.dart';
import 'package:disk_cleanup/core/models.dart';
import 'package:disk_cleanup/scan/du_scanner.dart';
import 'package:disk_cleanup/scan/large_files.dart';
import 'package:disk_cleanup/scan/scan_controller.dart';
import 'package:disk_cleanup/scan/scan_state.dart';
import 'package:disk_cleanup/scan/snapshot_store.dart';
import 'package:disk_cleanup/services.dart';
import 'package:disk_cleanup/settings/settings_controller.dart';
import 'package:disk_cleanup/settings/settings_store.dart';
import 'package:disk_cleanup/ui/cleanup_flow.dart';
import 'package:disk_cleanup/ui/pages/cleanup_page.dart';
import 'package:disk_cleanup/ui/pages/directories_page.dart';
import 'package:disk_cleanup/ui/pages/large_files_page.dart';
import 'package:disk_cleanup/ui/pages/overview_page.dart';
import 'package:disk_cleanup/ui/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_process_runner.dart';
import '../support/test_app.dart';

class FakeCleanup extends CleanupController {
  FakeCleanup(super.services);

  Future<CleanupResult> Function(List<CleanupItem>)? onExecute;
  final failUndo = <String>{};
  final executed = <List<CleanupItem>>[];

  @override
  Future<CleanupResult> execute(List<CleanupItem> items) {
    executed.add(items);
    final handler = onExecute;
    if (handler != null) return handler(items);
    return Future.value(
      CleanupResult(
        succeeded: items.length,
        doneIds: [for (final i in items) i.id],
      ),
    );
  }

  @override
  Future<UndoResult> undo(List<TrashedEntry> entries) async {
    final failed = entries.where((e) => failUndo.contains(e.originalPath));
    return UndoResult(
      restored: entries.length - failed.length,
      failed: failed.length,
    );
  }
}

CleanupItem item(
  String id,
  CleanupCategory c,
  int gb, {
  bool unknown = false,
  bool pre = true,
}) => CleanupItem(
  id: id,
  category: c,
  title: id,
  path: '/h/$id',
  note: '',
  bytes: unknown ? 0 : gb * 1000000000,
  risk: RiskLevel.safe,
  requiresRoot: false,
  preselected: pre,
  sizeUnknown: unknown,
  action: const DeletePathsAction(['/nao/existe']),
);

void main() {
  late Directory tmp;
  late Services services;
  late ScanController scan;
  late FakeCleanup cleanup;
  late CleanupFlow flow;
  late SettingsController settings;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dc_ui_');
    final home = p.join(tmp.path, 'home');
    Directory(home).createSync();
    services = Services(
      home: home,
      runner: FakeProcessRunner(),
      settingsStore: SettingsStore(p.join(tmp.path, 'settings.json')),
      snapshots: SnapshotStore(p.join(tmp.path, 'snap')),
      trashDir: p.join(home, '.local', 'share', 'Trash'),
    );
    scan = ScanController(services);
    cleanup = FakeCleanup(services);
    flow = CleanupFlow(scan: scan, cleanup: cleanup);
    settings = SettingsController(services.settingsStore, home);
  });

  tearDown(() {
    flow.dispose();
    scan.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> load(WidgetTester t, ScanState state) => t.runAsync(() async {
    await services.snapshots.save(
      Snapshot(takenAt: DateTime.now(), state: state.toJson()),
    );
    await scan.loadLast();
  });

  ScanState scanned({
    List<CleanupItem> items = const [],
    List<LargeFile> largeFiles = const [],
    Map<String, DuResult> mappedDirs = const {},
  }) => ScanState(
    updatedAt: DateTime.now(),
    items: items,
    largeFiles: largeFiles,
    mappedDirs: mappedDirs,
  );

  Future<void> wide(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  ButtonStyleButton filled(WidgetTester t, String text) =>
      t.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.textContaining(text),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );

  test('mensagem do desfazer usa singular e plural', () {
    expect(CleanupFlow.undoMessage(1, 1), '1 restaurado, 1 não pôde voltar.');
    expect(
      CleanupFlow.undoMessage(3, 2),
      '3 restaurados, 2 não puderam voltar.',
    );
  });

  testWidgets('erro na limpeza vira SnackBar e libera o botão', (t) async {
    await wide(t);
    await load(t, scanned(items: [item('cache:uv', CleanupCategory.cache, 2)]));
    cleanup.onExecute = (_) => Future.error(StateError('falhou'));
    await t.pumpWidget(testApp(CleanupPage(scan: scan, flow: flow)));
    await t.tap(find.text('Limpar 2,0 GB'));
    await t.pumpAndSettle();
    await t.tap(find.text('Limpar 2,0 GB').last);
    await t.pumpAndSettle();
    expect(
      find.text('A limpeza falhou. Nada mais foi apagado.'),
      findsOneWidget,
    );
    expect(flow.busy, isFalse);
  });

  testWidgets('Limpar fica desabilitado enquanto a limpeza roda', (t) async {
    await wide(t);
    await load(t, scanned(items: [item('cache:uv', CleanupCategory.cache, 2)]));
    final pending = Completer<CleanupResult>();
    cleanup.onExecute = (_) => pending.future;
    await t.pumpWidget(testApp(CleanupPage(scan: scan, flow: flow)));
    await t.tap(find.text('Limpar 2,0 GB'));
    await t.pumpAndSettle();
    await t.tap(find.text('Limpar 2,0 GB').last);
    await t.pumpAndSettle();
    expect(flow.busy, isTrue);
    expect(filled(t, 'Limpar 2,0 GB').onPressed, isNull);
    pending.complete(const CleanupResult());
    await t.pumpAndSettle();
    expect(flow.busy, isFalse);
  });

  testWidgets('desfazer parcial avisa o que não voltou', (t) async {
    await wide(t);
    await load(t, scanned(items: [item('cache:uv', CleanupCategory.cache, 2)]));
    cleanup
      ..failUndo.add('/b')
      ..onExecute = (items) async => CleanupResult(
        succeeded: 2,
        undo: const [
          TrashedEntry(originalPath: '/a', trashedName: 'a'),
          TrashedEntry(originalPath: '/b', trashedName: 'b'),
        ],
        doneIds: [for (final i in items) i.id],
      );
    await t.pumpWidget(testApp(CleanupPage(scan: scan, flow: flow)));
    await t.tap(find.text('Limpar 2,0 GB'));
    await t.pumpAndSettle();
    await t.tap(find.text('Limpar 2,0 GB').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Desfazer'));
    await t.pumpAndSettle();
    expect(find.text('1 restaurado, 1 não pôde voltar.'), findsOneWidget);
  });

  testWidgets('antes da primeira varredura não mostra 0 B', (t) async {
    await wide(t);
    await t.pumpWidget(testApp(CleanupPage(scan: scan, flow: flow)));
    expect(find.text('Ainda não varrido'), findsWidgets);
    expect(find.text('Nada para limpar aqui'), findsNothing);
    expect(find.textContaining('0 B'), findsNothing);
    expect(find.text('Caches'), findsOneWidget);
  });

  testWidgets('visão geral antes da varredura não diz que não há nada', (
    t,
  ) async {
    await wide(t);
    await t.pumpWidget(
      testApp(
        OverviewPage(
          scan: scan,
          flow: flow,
          settings: settings,
          onNavigate: (_) {},
        ),
      ),
    );
    expect(find.text('Nada seguro para limpar agora'), findsNothing);
    expect(find.text('Ainda não varrido'), findsWidgets);
  });

  testWidgets('tamanho desconhecido aparece e o total vira pelo menos', (
    t,
  ) async {
    await wide(t);
    await load(
      t,
      scanned(
        items: [
          item('cache:uv', CleanupCategory.cache, 2),
          item('cache:pip', CleanupCategory.cache, 0, unknown: true),
        ],
      ),
    );
    await t.pumpWidget(testApp(CleanupPage(scan: scan, flow: flow)));
    expect(find.text('Desconhecido'), findsOneWidget);
    expect(find.text('Limpar pelo menos 2,0 GB'), findsOneWidget);
    expect(find.text('Caches (pelo menos 2,0 GB)'), findsOneWidget);
    await t.tap(find.text('Limpar pelo menos 2,0 GB'));
    await t.pumpAndSettle();
    expect(find.text('Limpar pelo menos 2,0 GB?'), findsOneWidget);
  });

  testWidgets('Liberar da visão geral respeita o que foi desmarcado', (
    t,
  ) async {
    await wide(t);
    await load(
      t,
      scanned(
        items: [
          item('cache:uv', CleanupCategory.cache, 2),
          item('cache:pip', CleanupCategory.cache, 3),
        ],
      ),
    );
    scan.toggle('cache:pip');
    await t.pumpWidget(
      testApp(
        OverviewPage(
          scan: scan,
          flow: flow,
          settings: settings,
          onNavigate: (_) {},
        ),
      ),
    );
    await t.tap(find.text('Liberar 2,0 GB com segurança'));
    await t.pumpAndSettle();
    await t.tap(find.text('Limpar 2,0 GB'));
    await t.pumpAndSettle();
    expect(cleanup.executed.single.map((i) => i.id), ['cache:uv']);
  });

  testWidgets('arquivo grande removido continua oculto e volta no desfazer', (
    t,
  ) async {
    await wide(t);
    final file = p.join(services.home, 'grande.iso');
    await load(
      t,
      scanned(
        largeFiles: [
          LargeFile(
            path: file,
            bytes: 5000000000,
            lastAccess: DateTime(2026),
            modified: DateTime(2026),
          ),
        ],
      ),
    );
    cleanup.onExecute = (items) async => CleanupResult(
      succeeded: 1,
      undo: [TrashedEntry(originalPath: file, trashedName: 'grande.iso')],
      doneIds: [for (final i in items) i.id],
    );
    final current = ValueNotifier(AppDestination.largeFiles);
    await t.pumpWidget(
      testApp(
        ValueListenableBuilder(
          valueListenable: current,
          builder: (_, d, _) => d == AppDestination.largeFiles
              ? LargeFilesPage(scan: scan, flow: flow)
              : const SizedBox(),
        ),
      ),
    );
    await t.tap(find.text('grande.iso'));
    await t.pump();
    await t.tap(find.text('Mover para a lixeira'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mover para a lixeira').last);
    await t.pumpAndSettle();
    expect(find.text('grande.iso'), findsNothing);

    current.value = AppDestination.overview;
    await t.pump();
    current.value = AppDestination.largeFiles;
    await t.pump();
    expect(find.text('grande.iso'), findsNothing);

    current.value = AppDestination.overview;
    await t.pump();
    await t.tap(find.text('Desfazer'));
    await t.pumpAndSettle();
    current.value = AppDestination.largeFiles;
    await t.pumpAndSettle();
    expect(find.text('grande.iso'), findsOneWidget);
  });

  testWidgets('diretório do sistema é recusado no mapeamento', (t) async {
    await wide(t);
    await t.pumpWidget(
      testApp(DirectoriesPage(scan: scan, settings: settings)),
    );
    await t.tap(find.text('Adicionar diretório').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '/etc');
    await t.tap(find.text('Adicionar e medir'));
    await t.pump();
    expect(
      find.text('Escolha uma pasta dentro do seu home ou de um disco externo.'),
      findsOneWidget,
    );
  });

  testWidgets('total desconhecido do diretório não vira 0 B', (t) async {
    await wide(t);
    final dir = services.home;
    await t.runAsync(
      () => settings.update((s) => s.copyWith(mappedDirs: [dir])),
    );
    await load(
      t,
      scanned(
        mappedDirs: {
          dir: const DuResult(
            entries: [],
            total: 0,
            errors: 1,
            permissionDenied: false,
            totalUnknown: true,
          ),
        },
      ),
    );
    await t.pumpWidget(
      testApp(DirectoriesPage(scan: scan, settings: settings)),
    );
    await t.pumpAndSettle();
    expect(find.text('Tamanho desconhecido'), findsOneWidget);
    expect(find.text('0 B'), findsNothing);
  });
}
