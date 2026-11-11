import 'dart:io';

import 'package:disk_cleanup/backup/restore_planner.dart';
import 'package:disk_cleanup/backup/rsync_runner.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parseItemize', () {
    test('lê a saída real do rsync -8 --itemize-changes', () {
      const lines = [
        '>f+++++++++ com espaço.txt',
        r'>f+++++++++ linha\#012quebrada.txt',
        r'>f+++++++++ x\#134#012y.txt',
        r'>f+++++++++ bar\ra.txt',
        'cL+++++++++ link',
        '>f..t...... mesmo-tamanho.txt',
        '.d..t...... sub/',
        '>f.st...... sub/alterado.txt',
        'cd+++++++++ vazia/',
        '.f...p..... só-permissão.txt',
        '*deleting   velho.txt',
        '*deleting   pasta-velha/',
        'sent 1,234 bytes  received 56 bytes',
      ];
      expect(parseItemize(lines), [
        const ItemizeEntry(ItemizeKind.created, 'com espaço.txt'),
        const ItemizeEntry(ItemizeKind.created, 'linha\nquebrada.txt'),
        const ItemizeEntry(ItemizeKind.created, r'x\#012y.txt'),
        const ItemizeEntry(ItemizeKind.created, r'bar\ra.txt'),
        const ItemizeEntry(ItemizeKind.created, 'link', isLink: true),
        const ItemizeEntry(ItemizeKind.changed, 'mesmo-tamanho.txt'),
        const ItemizeEntry(ItemizeKind.changed, 'sub/alterado.txt'),
        const ItemizeEntry(ItemizeKind.deleting, 'velho.txt'),
        const ItemizeEntry(ItemizeKind.deleting, 'pasta-velha', isDir: true),
      ]);
    });
  });

  group('resolveConflicts', () {
    final old = DateTime(2026, 1, 1);
    final recent = DateTime(2026, 11, 1);
    final analysis = RestoreAnalysis(
      source: '/b',
      target: '/l',
      created: const ['novo.txt'],
      conflicts: [
        RestoreConflict(
          path: 'a.txt',
          localModified: old,
          backupModified: recent,
        ),
        RestoreConflict(
          path: 'b.txt',
          localModified: recent,
          backupModified: old,
        ),
      ],
    );

    test('mais recente vence decide por arquivo', () {
      final d = resolveConflicts(analysis, ConflictAction.newerWins);
      expect(d.copy, ['novo.txt']);
      expect(d.replace, ['a.txt']);
      expect(d.keep, ['b.txt']);
      expect(d.duplicate, isEmpty);
    });

    test('a decisão por arquivo vale sobre a regra em lote', () {
      final d = resolveConflicts(
        analysis,
        ConflictAction.keepLocal,
        overrides: const {'b.txt': ConflictAction.keepBoth},
      );
      expect(d.replace, isEmpty);
      expect(d.keep, ['a.txt']);
      expect(d.duplicate, ['b.txt']);
    });

    test('usar backup substitui todos', () {
      final d = resolveConflicts(analysis, ConflictAction.useBackup);
      expect(d.replace, ['a.txt', 'b.txt']);
    });
  });

  test('duplicateName põe o rótulo antes da extensão', () {
    expect(duplicateName('a/b.tar.gz', 'backup'), 'a/b.tar (backup).gz');
    expect(duplicateName('Makefile', 'backup'), 'Makefile (backup)');
    expect(duplicateName('.bashrc', 'backup'), '.bashrc (backup)');
  });

  group('com rsync de verdade', () {
    late Directory tmp;
    late String backup;
    late String local;
    late String replaced;
    late RestoreEngine engine;

    void write(String path, String content, {DateTime? at}) {
      final f = File(path)..createSync(recursive: true);
      f.writeAsStringSync(content);
      if (at != null) f.setLastModifiedSync(at);
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('restaurar-');
      backup = p.join(tmp.path, 'hd', 'projetos');
      local = p.join(tmp.path, 'home', 'projetos');
      replaced = p.join(tmp.path, 'substituidos');
      final runner = SystemProcessRunner();
      engine = RestoreEngine(runner, RsyncRunner(runner));
      final old = DateTime(2025, 1, 1);
      final recent = DateTime(2026, 11, 1);
      write(p.join(backup, 'novo.txt'), 'novo');
      write(p.join(backup, 'sub', 'novo2.txt'), 'novo2');
      write(p.join(backup, 'igual.txt'), 'igual', at: old);
      write(p.join(local, 'igual.txt'), 'igual', at: recent);
      write(p.join(backup, 'troca.txt'), 'do backup', at: recent);
      write(p.join(local, 'troca.txt'), 'local', at: old);
      write(p.join(backup, 'fica.txt'), 'do backup', at: old);
      write(p.join(local, 'fica.txt'), 'local mais novo', at: recent);
      write(p.join(local, 'so-local.txt'), 'só aqui');
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    Future<RestoreAnalysis> analyze({List<String>? subpaths}) => engine.analyze(
      source: backup,
      target: local,
      tmp: tmp,
      subpaths: subpaths,
    );

    test('análise separa novos de conflitos e ignora conteúdo igual', () async {
      final a = await analyze();
      expect(a.created..sort(), ['novo.txt', 'sub/novo2.txt']);
      expect([for (final c in a.conflicts) c.path]..sort(), [
        'fica.txt',
        'troca.txt',
      ]);
      final troca = a.conflicts.firstWhere((c) => c.path == 'troca.txt');
      expect(troca.backupIsNewer, isTrue);
      expect(troca.localSize, 5);
      expect(troca.backupSize, 9);
      expect(a.createdBytes, 9);
    });

    test('só os itens escolhidos entram na análise', () async {
      final a = await analyze(subpaths: ['sub', 'troca.txt']);
      expect(a.created, ['sub/novo2.txt']);
      expect([for (final c in a.conflicts) c.path], ['troca.txt']);
    });

    test(
      'execução copia, substitui guardando o antigo e mantém os dois',
      () async {
        final a = await analyze();
        final d = resolveConflicts(
          a,
          ConflictAction.newerWins,
          overrides: const {'fica.txt': ConflictAction.keepBoth},
        );
        final r = await engine.execute(
          analysis: a,
          decision: d,
          replacedDir: replaced,
          duplicateLabel: 'backup 2026-11-09',
          tmp: tmp,
        );
        expect(r.outcome, RsyncOutcome.ok);
        expect((r.copied, r.replaced, r.duplicated), (2, 1, 1));

        String read(String rel) => File(p.join(local, rel)).readAsStringSync();
        expect(read('novo.txt'), 'novo');
        expect(read('sub/novo2.txt'), 'novo2');
        expect(read('troca.txt'), 'do backup');
        expect(File(p.join(replaced, 'troca.txt')).readAsStringSync(), 'local');
        expect(read('fica.txt'), 'local mais novo');
        expect(read('fica (backup 2026-11-09).txt'), 'do backup');
        expect(read('so-local.txt'), 'só aqui');
        expect(read('igual.txt'), 'igual');

        final again = await engine.execute(
          analysis: a,
          decision: d,
          replacedDir: replaced,
          duplicateLabel: 'backup 2026-11-09',
          tmp: tmp,
        );
        expect(again.duplicated, 1);
        expect(read('fica (backup 2026-11-09 2).txt'), 'do backup');
      },
    );

    test('manter local não toca no arquivo', () async {
      final a = await analyze();
      final d = resolveConflicts(a, ConflictAction.keepLocal);
      await engine.execute(
        analysis: a,
        decision: d,
        replacedDir: replaced,
        duplicateLabel: 'backup',
        tmp: tmp,
      );
      expect(File(p.join(local, 'troca.txt')).readAsStringSync(), 'local');
      expect(Directory(replaced).existsSync(), isFalse);
    });

    test(
      'destino só dentro das raízes permitidas, sem fugir por symlink',
      () async {
        final home = p.join(tmp.path, 'home');
        Link(p.join(home, 'fuga')).createSync(tmp.path);
        expect(
          await isRestorableTarget(p.join(home, 'projetos'), [home]),
          isTrue,
        );
        expect(
          await isRestorableTarget(p.join(home, 'nova', 'pasta'), [home]),
          isTrue,
        );
        expect(await isRestorableTarget(home, [home]), isTrue);
        expect(
          await isRestorableTarget(p.join(home, 'fuga', 'x'), [home]),
          isFalse,
        );
        expect(await isRestorableTarget(tmp.path, [home]), isFalse);
        expect(await isRestorableTarget('relativo', [home]), isFalse);
      },
    );
  });
}
