import 'dart:convert';

import 'package:disk_cleanup/cleanup/privileged_runner.dart';
import 'package:disk_cleanup/core/models.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/scan/cache_catalog.dart';
import 'package:disk_cleanup/scan/du_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

RunResult _out(int code, String stdout, [String stderr = '']) =>
    RunResult(code, utf8.encode(stdout), stderr);

String _du(Map<String, int> sizes) =>
    sizes.entries.map((e) => '${e.value}\t${e.key}\x00').join();

int? _noFile(String path) => null;

void main() {
  const home = '/h';

  group('CacheInventory', () {
    late FakeProcessRunner runner;
    late CacheInventory inventory;

    setUp(() {
      runner = FakeProcessRunner();
      inventory = CacheInventory(runner, DuScanner(runner));
    });

    void scriptDu(Map<String, int> sizes) {
      runner.when('du', [
        '-sx',
        '-B1',
        '-0',
        for (final d in kCacheCatalog) '$home/${d.relPath}',
      ], _out(0, _du(sizes)));
    }

    test('mede tudo com um único du e marca navegador aberto', () async {
      scriptDu({'/h/.cache/uv': 5000, '/h/.cache/BraveSoftware': 3000});
      runner.when('pgrep', ['-x', 'brave'], _out(0, '123\n'));

      final items = await inventory.scan(home);

      expect(items.map((i) => i.id), ['cache:uv', 'cache:brave']);
      final uv = items[0];
      expect(uv.title, 'Cache do uv');
      expect(uv.note, 'Pacotes Python baixados');
      expect(uv.path, '/h/.cache/uv');
      expect(uv.bytes, 5000);
      expect(uv.category, CleanupCategory.cache);
      expect(uv.risk, RiskLevel.safe);
      expect(uv.requiresRoot, isFalse);
      expect(uv.preselected, isTrue);
      expect((uv.action as DeletePathsAction).paths, ['/h/.cache/uv']);
      final brave = items[1];
      expect(brave.preselected, isFalse);
      expect(brave.note, 'Brave está aberto: feche para limpar');
      expect(runner.calls.where((c) => c.first == 'du'), hasLength(1));
    });

    test('navegador fechado fica pré-selecionado', () async {
      scriptDu({'/h/.cache/google-chrome': 10});
      runner.when('pgrep', ['-x', 'chrome'], _out(1, ''));

      final items = await inventory.scan(home);

      expect(items.single.preselected, isTrue);
      expect(items.single.note, 'Páginas e imagens; logins e histórico ficam');
    });

    test('cache ausente ou vazio não gera item', () async {
      scriptDu({'/h/.cache/uv': 0});

      expect(await inventory.scan(home), isEmpty);
    });
  });

  group('SystemInventory', () {
    late FakeProcessRunner runner;

    SystemInventory build({int? Function(String path) fileSize = _noFile}) =>
        SystemInventory(runner, DuScanner(runner), fileSize: fileSize);

    void scriptDu(Map<String, int> sizes) {
      runner.when('du', [
        '-sx',
        '-B1',
        '-0',
        '/var/log/journal',
        '/var/cache/apt/archives',
      ], _out(0, _du(sizes)));
    }

    setUp(() => runner = FakeProcessRunner());

    test('journal e apt a partir de um único du', () async {
      scriptDu({
        '/var/log/journal': 4000000000,
        '/var/cache/apt/archives': 2000000,
      });
      runner.when('snap', ['list', '--all'], _out(127, '', 'not found'));

      final items = await build().scan();

      expect(items.map((i) => i.id), ['system:journal', 'system:apt']);
      final journal = items[0];
      expect(journal.title, 'Logs do sistema (journal)');
      expect(journal.note, 'Mantém os últimos 500 MB');
      expect(journal.path, '/var/log/journal');
      expect(journal.bytes, 4000000000);
      expect(journal.category, CleanupCategory.system);
      expect(journal.risk, RiskLevel.safe);
      expect(journal.requiresRoot, isTrue);
      expect(journal.preselected, isFalse);
      expect(
        (journal.action as RootAction).commands.single,
        isA<JournalVacuum>(),
      );
      expect((items[1].action as RootAction).commands.single, isA<AptClean>());
      expect(items[1].title, 'Cache do apt');
    });

    test('ignora itens ausentes ou menores que 1 MB', () async {
      scriptDu({'/var/cache/apt/archives': 999999});
      runner.when('snap', ['list', '--all'], _out(127, '', ''));

      expect(await build().scan(), isEmpty);
    });

    test('uma revisão desativada do snap vira um item', () async {
      scriptDu({});
      runner.when(
        'snap',
        ['list', '--all'],
        _out(
          0,
          'Name    Version   Rev   Tracking       Publisher   Notes\n'
          'core20  20240111  2182  latest/stable  canonical**  base,disabled\n'
          'core20  20240301  2200  latest/stable  canonical**  base\n'
          'bad;name  1  5  latest/stable  x  disabled\n'
          'gone  1  7  latest/stable  x  disabled\n',
        ),
      );

      final items = await build(
        fileSize: (path) =>
            path == '/var/lib/snapd/snaps/core20_2182.snap' ? 1234 : null,
      ).scan();

      final item = items.single;
      expect(item.id, 'system:snap:core20:2182');
      expect(item.title, 'Snap core20 (revisão 2182 desativada)');
      expect(item.bytes, 1234);
      expect(item.requiresRoot, isTrue);
      expect(item.preselected, isFalse);
      final cmd =
          (item.action as RootAction).commands.single as SnapRemoveRevision;
      expect(cmd.name, 'core20');
      expect(cmd.revision, '2182');
    });

    test('snap inexistente não gera item nem erro', () async {
      scriptDu({});
      runner.when('snap', ['list', '--all'], _out(127, '', 'not found'));

      expect(await build().scan(), isEmpty);
    });
  });
}
