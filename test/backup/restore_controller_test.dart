import 'dart:io';

import 'package:disk_cleanup/backup/backup_controller.dart';
import 'package:disk_cleanup/backup/restore_controller.dart';
import 'package:disk_cleanup/backup/restore_planner.dart';
import 'package:disk_cleanup/backup/secrets_archiver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'backup_fakes.dart';

void main() {
  late BackupFixture f;
  late BackupController b;
  late RestoreController r;
  final now = DateTime(2026, 11, 10, 9);

  String read(String rel) => File(p.join(f.home, rel)).readAsStringSync();

  setUp(() async {
    f = BackupFixture();
    f.file('projetos/app/notas.txt', 'do backup');
    File(p.join(f.home, 'projetos/app/notas.txt'))
        .setLastModifiedSync(DateTime(2026, 1, 1));
    b = BackupController(f.services, f.settings, now: () => now);
    r = RestoreController(f.services, f.settings, b, now: () => now);
    await b.refresh();
    await b.chooseDestination(f.hd);
    await b.addSource(p.join(f.home, 'projetos'));
    await b.start();
    expect(b.outcome, BackupStepStatus.done);
    await b.dismiss();

    File(p.join(f.home, 'projetos/app/main.dart')).deleteSync();
    f.file('projetos/app/notas.txt', 'editado aqui');
    f.file('projetos/app/so-local.txt', 'só local');
    await r.load();
  });

  tearDown(() {
    r.dispose();
    b.dispose();
    f.dispose();
  });

  test('lista segredos, pastas e navegadores do backup', () {
    expect(r.loadError, isNull);
    expect(r.backupDir, p.join(f.hd, 'backup'));
    expect(
      [for (final c in r.choices) c.id],
      ['segredos', 'pasta:projetos', 'navegador:chrome'],
    );
    expect(
      r.choice('pasta:projetos')!.originalPath,
      p.join(f.home, 'projetos'),
    );
    expect(r.secretsFiles, ['secrets-2026-11-10.tar.gz.gpg']);
    expect(r.problems, ['Escolha o que restaurar.']);
  });

  test('restaura pasta: copia o que falta e resolve o conflito', () async {
    r.toggle('pasta:projetos');
    await r.analyze();
    expect(r.phase, RestorePhase.reviewing);
    final item = r.items.single;
    expect(item.analysis!.created, ['app/main.dart']);
    expect(
      [for (final c in item.analysis!.conflicts) c.path],
      ['app/notas.txt'],
    );

    expect(r.totals.keep, 1);
    r.setOverride(item, 'app/notas.txt', ConflictAction.useBackup);
    expect((r.totals.created, r.totals.replace), (1, 1));

    await r.start();
    expect(r.phase, RestorePhase.finished);
    expect(r.outcome, BackupStepStatus.done);
    expect(read('projetos/app/main.dart'), 'void main() {}');
    expect(read('projetos/app/notas.txt'), 'do backup');
    expect(read('projetos/app/so-local.txt'), 'só local');
    expect(r.replacedSomething, isTrue);
    expect(
      File(p.join(r.replacedDir!, 'pasta-projetos', 'app/notas.txt'))
          .readAsStringSync(),
      'editado aqui',
    );
    expect(
      Directory(p.join(f.home, 'projetos/app/node_modules')).existsSync(),
      isTrue,
    );
  });

  test('só os arquivos escolhidos', () async {
    r.setSubpaths('pasta:projetos', ['app/notas.txt']);
    r.setRule(ConflictAction.keepBoth);
    await r.analyze();
    expect(r.items.single.analysis!.created, isEmpty);
    await r.start();
    expect(
      File(p.join(f.home, 'projetos/app/main.dart')).existsSync(),
      isFalse,
    );
    expect(read('projetos/app/notas.txt'), 'editado aqui');
    expect(read('projetos/app/notas (backup 2026-11-10).txt'), 'do backup');
  });

  test('pasta separada não toca nos arquivos atuais', () async {
    r.toggle('pasta:projetos');
    r.setDestination(RestoreDestination.separate);
    await r.analyze();
    expect(
      r.items.single.target,
      p.join(f.home, 'Restaurado-2026-11-10', 'projetos'),
    );
    expect(r.totals.conflicts, 0);
    await r.start();
    expect(read('Restaurado-2026-11-10/projetos/app/notas.txt'), 'do backup');
    expect(read('projetos/app/notas.txt'), 'editado aqui');
  });

  test(
    'segredos: descriptografa, revisa o conflito e fecha permissões',
    () async {
      r.toggle('segredos');
      await r.analyze();
      final item = r.items.single;
      expect(f.secrets.extracted, [
        p.join(f.hd, 'secrets-2026-11-10.tar.gz.gpg'),
      ]);
      expect(
        [for (final c in item.analysis!.conflicts) c.path],
        ['.ssh/id_ed25519'],
      );
      final staging = item.source!;
      expect(Directory(staging).existsSync(), isTrue);

      r.setRule(ConflictAction.useBackup);
      await r.start();
      expect(read('.ssh/id_ed25519'), 'chave do backup');
      expect(Directory(staging).existsSync(), isFalse);
      final mode = File(p.join(f.home, '.ssh/id_ed25519')).statSync().mode;
      expect(mode & 0x3f, 0);
    },
  );

  test(
    'janela de senha fechada pula os segredos e segue com o resto',
    () async {
      f.secrets.outcome = SecretsOutcome.cancelled;
      r.selectAll();
      await r.analyze();
      expect(r.items.first.status, BackupStepStatus.skipped);
      expect(r.items.first.analysis, isNull);
      expect(r.canRun, isTrue);
    },
  );

  test('navegador aberto bloqueia só o perfil', () async {
    f.openChrome();
    r.toggle('navegador:chrome');
    r.toggle('pasta:projetos');
    await r.analyze();
    final chrome = r.items.firstWhere((i) => i.choice.id == 'navegador:chrome');
    expect(chrome.status, BackupStepStatus.failed);
    expect(chrome.message, contains('Feche o Google Chrome'));
  });

  test('backup e restauração não rodam juntos', () async {
    f.services.backup.lock.acquire(b);
    r.toggle('pasta:projetos');
    expect(r.problems, contains('Espere o backup terminar para restaurar.'));
    await r.analyze();
    expect(r.phase, RestorePhase.idle);
    f.services.backup.lock.release(b);

    await r.analyze();
    expect(b.problems, isNot(contains(startsWith('Espere a restauração'))));
    f.services.backup.lock.acquire(r);
    expect(b.canRun, isFalse);
    expect(
      b.problems,
      contains('Espere a restauração terminar para fazer o backup.'),
    );
  });

  test('pasta sem backup avisa', () async {
    await r.load(dir: p.join(f.tmp.path, 'vazio'));
    expect(r.loadError, contains('Não há backup'));
    expect(r.choices, isEmpty);
  });
}
