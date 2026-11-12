import 'dart:io';

import 'package:disk_cleanup/backup/backup_controller.dart';
import 'package:disk_cleanup/backup/pending_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'backup_fakes.dart';

void main() {
  test('store guarda pendentes e itens mantidos por disco', () async {
    final tmp = Directory.systemTemp.createTempSync('pendentes-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = PendingStore(p.join(tmp.path, 'sub', 'pendentes.json'));
    final item = PendingItem(
      kind: PendingKind.diskNewer,
      source: 'projetos',
      rel: 'a b/[x].txt',
      localSize: 1,
      localModified: DateTime(2026, 1, 1),
      diskSize: 2,
      diskModified: DateTime(2026, 2, 1),
    );
    await store.save(
      'disco-1',
      PendingState(items: [item], keepOnDisk: {'projetos/velho'}),
    );
    await store.save('disco-2', const PendingState());

    final read = await store.load('disco-1');
    expect(read.items.single.toJson(), item.toJson());
    expect(read.keepOnDisk, {'projetos/velho'});
    expect((await store.load('disco-2')).items, isEmpty);
    expect((await store.load('outro')).items, isEmpty);
    expect(item.rule, r'- /projetos/a b/\[x].txt');
  });

  test('saves simultâneos no mesmo arquivo não se perdem', () async {
    final tmp = Directory.systemTemp.createTempSync('pendentes-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final path = p.join(tmp.path, 'pendentes.json');
    await Future.wait([
      for (var i = 0; i < 10; i++)
        PendingStore(path)
            .save('disco-$i', PendingState(keepOnDisk: {'pasta/$i'})),
    ]);
    for (var i = 0; i < 10; i++) {
      expect((await PendingStore(path).load('disco-$i')).keepOnDisk, {
        'pasta/$i',
      });
    }
  });

  group('no backup', () {
    late BackupFixture f;
    late BackupController c;
    var now = DateTime(2026, 11, 10, 9);
    String backup() => p.join(f.hd, 'backup');

    String disk(String rel) =>
        File(p.join(backup(), 'projetos', rel)).readAsStringSync();
    String local(String rel) =>
        File(p.join(f.home, 'projetos', rel)).readAsStringSync();

    setUp(() async {
      now = DateTime(2026, 11, 10, 9);
      f = BackupFixture();
      f.file('projetos/app/notas.txt', 'v1');
      f.file('projetos/app/rascunho.txt', 'r');
      c = BackupController(f.services, f.settings, now: () => now);
      await c.refresh();
      await c.chooseDestination(f.hd);
      await c.addSource(p.join(f.home, 'projetos'));
      await c.setMirror(true);
      await c.start();
      await c.dismiss();
      expect(c.pending, isEmpty);

      File(p.join(f.home, 'projetos/app/notas.txt'))
          .setLastModifiedSync(DateTime(2025));
      File(p.join(backup(), 'projetos/app/notas.txt'))
        ..writeAsStringSync('editado no disco')
        ..setLastModifiedSync(DateTime(2026, 6));
      File(p.join(f.home, 'projetos/app/rascunho.txt')).deleteSync();
      f.file('projetos/app/novo.txt', 'novo');
      now = now.add(const Duration(days: 1));
      await c.start();
    });

    tearDown(() {
      c.dispose();
      f.dispose();
    });

    test('segura conflitos e copia o resto', () async {
      final folders = c.steps.firstWhere(
        (s) => s.kind == BackupStepKind.folders,
      );
      expect(folders.status, BackupStepStatus.warnings);
      expect(folders.message, '2 itens esperam sua decisão em Pendentes');
      expect(
        {for (final i in c.pending) (i.kind, i.key)},
        {
          (PendingKind.diskNewer, 'projetos/app/notas.txt'),
          (PendingKind.wouldDelete, 'projetos/app/rascunho.txt'),
        },
      );
      expect(disk('app/notas.txt'), 'editado no disco');
      expect(disk('app/rascunho.txt'), 'r');
      expect(disk('app/novo.txt'), 'novo');

      final again = BackupController(f.services, f.settings, now: () => now);
      addTearDown(again.dispose);
      await again.refresh();
      expect(again.pending.length, 2);
    });

    test('trazer do disco guarda a versão local à parte', () async {
      await c.dismiss();
      final error = await c.resolvePending({
        'projetos/app/notas.txt': PendingAction.bringFromDisk,
      });
      expect(error, isNull);
      expect(local('app/notas.txt'), 'editado no disco');
      final replaced = Directory(p.join(f.services.dataDir, 'substituidos'))
          .listSync(recursive: true)
          .whereType<File>()
          .single;
      expect(replaced.readAsStringSync(), 'v1');
      expect([for (final i in c.pending) i.key], ['projetos/app/rascunho.txt']);
    });

    test(
      'enviar o do computador guarda a versão do disco no próprio disco',
      () async {
        await c.dismiss();
        await c.resolvePending({
          'projetos/app/notas.txt': PendingAction.sendLocal,
        });
        expect(disk('app/notas.txt'), 'v1');
        final kept = Directory(p.join(backup(), '.substituidos'))
            .listSync(recursive: true)
            .whereType<File>()
            .single;
        expect(kept.readAsStringSync(), 'editado no disco');
      },
    );

    test('manter os dois traz a cópia do disco com sufixo', () async {
      await c.dismiss();
      await c.resolvePending({
        'projetos/app/notas.txt': PendingAction.keepBoth,
      });
      expect(local('app/notas.txt'), 'v1');
      expect(local('app/notas (do disco 2026-11-11).txt'), 'editado no disco');
    });

    test('apagar do disco e manter no disco', () async {
      await c.dismiss();
      await c.resolvePending({
        'projetos/app/rascunho.txt': PendingAction.deleteFromDisk,
        'projetos/app/notas.txt': PendingAction.later,
      });
      expect(
        File(p.join(backup(), 'projetos/app/rascunho.txt')).existsSync(),
        isFalse,
      );
      expect([for (final i in c.pending) i.key], ['projetos/app/notas.txt']);
    });

    test('manter no disco não volta a pedir decisão', () async {
      await c.dismiss();
      await c.resolvePending({
        'projetos/app/rascunho.txt': PendingAction.keepOnDisk,
      });
      expect(c.keepOnDisk, {'projetos/app/rascunho.txt'});
      await c.start();
      expect([for (final i in c.pending) i.key], ['projetos/app/notas.txt']);
      expect(disk('app/rascunho.txt'), 'r');
    });

    test('manter no disco não impede enviar o arquivo que voltou', () async {
      await c.dismiss();
      await c.resolvePending({
        'projetos/app/rascunho.txt': PendingAction.keepOnDisk,
      });
      f.file('projetos/app/rascunho.txt', 'de volta');
      await c.start();
      expect(disk('app/rascunho.txt'), 'de volta');
    });

    test(
      'nome com codificação inválida não é apagado nem sobrescrito',
      () async {
        String sh(String script, List<String> args) {
          final r = Process.runSync('sh', [
            '-c',
            script,
            'sh',
            ...args,
          ], workingDirectory: p.join(backup(), 'projetos', 'app'));
          expect(r.exitCode, 0, reason: '${r.stderr}');
          return r.stdout as String;
        }

        const soNoDisco = r'so-no-disco-\351.txt';
        const velho = r'velho-\351.txt';
        sh(r'printf disco > "$(printf "$1")"', [soNoDisco]);
        sh(
          r'printf disco > "$(printf "$1")"; touch -d 2026-06-01 "$(printf "$1")"',
          [velho],
        );
        final r = Process.runSync('sh', [
          '-c',
          r'printf local > "$(printf "$1")"; touch -d 2025-01-01 "$(printf "$1")"',
          'sh',
          velho,
        ], workingDirectory: p.join(f.home, 'projetos', 'app'));
        expect(r.exitCode, 0, reason: '${r.stderr}');

        await c.dismiss();
        await c.start();

        expect(sh(r'cat "$(printf "$1")"', [soNoDisco]), 'disco');
        expect(sh(r'cat "$(printf "$1")"', [velho]), 'disco');
        expect(disk('app/rascunho.txt'), 'r');
        final folders = c.steps.firstWhere(
          (s) => s.kind == BackupStepKind.folders,
        );
        expect(folders.status, BackupStepStatus.warnings);
        expect(
          folders.warnings.first,
          contains('codificação inválida em projetos'),
        );
        expect(c.pending.any((i) => i.key.contains('\u{FFFD}')), isFalse);
      },
    );

    test('pendente não resolve com backup em andamento', () async {
      expect(
        await c.resolvePending({
          'projetos/app/notas.txt': PendingAction.sendLocal,
        }),
        contains('Espere'),
      );
    });
  });
}
