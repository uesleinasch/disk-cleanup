import 'dart:io';

import 'package:disk_cleanup/backup/backup_controller.dart';
import 'package:disk_cleanup/backup/backup_manifest.dart';
import 'package:disk_cleanup/backup/secrets_archiver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'backup_fakes.dart';

void main() {
  late BackupFixture f;
  late BackupController c;
  final now = DateTime(2026, 11, 9, 20, 30);

  setUp(() async {
    f = BackupFixture();
    c = BackupController(f.services, f.settings, now: () => now);
    await c.refresh();
  });

  tearDown(() {
    c.dispose();
    f.dispose();
  });

  Future<void> configure() async {
    expect(await c.chooseDestination(f.hd), isNull);
    expect(await c.addSource(p.join(f.home, 'projetos')), isNull);
  }

  List<BackupStepStatus> statuses() => [for (final s in c.steps) s.status];

  group('configuração', () {
    test('sem destino e sem pastas não deixa começar', () {
      expect(c.problems, [
        'Escolha onde salvar o backup.',
        'Adicione ao menos uma pasta.',
      ]);
      expect(c.canRun, isFalse);
    });

    test('destino e pasta válidos liberam o backup', () async {
      await configure();
      expect(c.problems, isEmpty);
      expect(c.canRun, isTrue);
      expect(c.backupDir, p.join(f.hd, 'backup'));
      expect(c.settings.value.backup.target!.id, 'disco-1');
    });

    test('addSource recusa os casos inválidos', () async {
      await configure();
      Directory(p.join(f.tmp.path, 'outro', 'projetos'))
          .createSync(recursive: true);
      Directory(p.join(f.home, 'navegadores')).createSync();
      expect(
        await c.addSource(p.join(f.home, 'nao-existe')),
        contains('não existe'),
      );
      expect(
        await c.addSource(p.join(f.home, 'projetos')),
        contains('já está na lista'),
      );
      expect(
        await c.addSource(p.join(f.tmp.path, 'outro', 'projetos')),
        contains('Já existe uma pasta chamada "projetos"'),
      );
      expect(
        await c.addSource(p.join(f.home, 'projetos', 'app')),
        contains('dentro de outra'),
      );
      expect(await c.addSource(f.home), contains('dentro de outra'));
      expect(
        await c.addSource(p.join(f.home, 'navegadores')),
        contains('reservado'),
      );
      expect(
        await c.addSource(p.join(f.home, '.ssh')),
        contains('chaves ou perfis'),
      );
      expect(c.config.sources, [p.join(f.home, 'projetos')]);
    });

    test('sistema de arquivos sem permissões bloqueia', () async {
      f.disks.fsType = 'exfat';
      await configure();
      expect(c.problems.single, contains('exFAT'));
    });

    test('disco desconectado pede para conectar', () async {
      await configure();
      f.disks.connected = false;
      await c.refresh();
      expect(c.problems, [
        'Conecte o disco Disco externo para fazer o backup.',
      ]);
    });

    test('destino dentro da origem bloqueia e avisa do mesmo disco', () async {
      final projetos = p.join(f.home, 'projetos');
      expect(await c.addSource(projetos), isNull);
      final dentro = p.join(projetos, 'copia');
      Directory(dentro).createSync();

      expect(await c.chooseDestination(dentro), isNull);

      expect(c.destination, dentro);
      expect(c.problems, ['O destino fica dentro de $projetos.']);
      expect(c.notices.first, contains('mesmo disco de projetos'));
    });

    test('avisos: navegador aberto e perfis sem keyring', () async {
      f.openChrome();
      await c.refresh();
      expect(c.notices, [
        contains('Feche o Google Chrome'),
        'Sem o keyring, os perfis voltam sem as senhas salvas.',
      ]);
      await c.toggleBrowser('chrome');
      expect(c.notices, isEmpty);
    });

    test('itens de segredo avulsos só de dentro do home', () async {
      f.file('chave.pem');
      expect(await c.addSecret('/etc/hosts'), contains('pasta pessoal'));
      expect(
        await c.addSecret(p.join(f.home, 'nada.pem')),
        contains('não existe'),
      );
      expect(
        await c.addSecret(p.join(f.home, '.ssh', 'id_ed25519')),
        contains('.ssh'),
      );
      expect(await c.addSecret(p.join(f.home, 'chave.pem')), isNull);
      expect(c.selectedSecrets, ['.ssh', 'chave.pem']);
      await c.toggleSecret('.ssh');
      expect(c.selectedSecrets, ['chave.pem']);
    });
  });

  test('calcular mostra o tamanho sem copiar nada', () async {
    await configure();
    await c.calculate();
    expect(c.estimateError, isNull);
    expect(c.estimate!.totalBytes, 'void main() {}'.length);
    expect(Directory(p.join(f.hd, 'backup')).existsSync(), isFalse);
    await c.setMirror(true);
    expect(c.estimate, isNull);
  });

  test('backup completo: segredos, pastas, navegador e guia', () async {
    await configure();

    await c.start();

    expect(c.phase, BackupPhase.finished);
    expect(
      [for (final s in c.steps) s.kind],
      [
        BackupStepKind.prepare,
        BackupStepKind.secrets,
        BackupStepKind.folders,
        BackupStepKind.browser,
        BackupStepKind.guide,
      ],
    );
    expect(statuses(), everyElement(BackupStepStatus.done));
    expect(c.outcome, BackupStepStatus.done);
    expect(f.secrets.archived.single, ['.ssh']);

    final backup = p.join(f.hd, 'backup');
    expect(File(p.join(backup, 'projetos/app/main.dart')).existsSync(), isTrue);
    expect(
      Directory(p.join(backup, 'projetos/app/node_modules')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(backup, 'navegadores/chrome/Default/History')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(backup, 'navegadores/chrome/Default/Cache'))
          .existsSync(),
      isFalse,
    );
    expect(
      File(p.join(backup, 'secrets-2026-11-09.tar.gz.gpg')).existsSync(),
      isTrue,
    );

    final readme = File(p.join(backup, 'LEIA-ME-RESTAURAR.md'))
        .readAsStringSync();
    expect(readme, contains('secrets-2026-11-09.tar.gz.gpg'));
    expect(readme, contains('navegadores/chrome/'));
    expect(readme, contains('udisksctl unmount -b /dev/sdz1'));
    expect(c.readmePath, p.join(backup, 'LEIA-ME-RESTAURAR.md'));
    expect(
      [for (final e in Directory(f.hd).listSync()) p.basename(e.path)],
      ['backup'],
    );
    expect(f.settings.value.backup.lastBackupAt, now);

    final manifest = (await BackupManifest.load(backup))!;
    expect(manifest.fromManifest, isTrue);
    expect(manifest.date, now);
    expect(manifest.home, f.home);
    expect(
      [for (final s in manifest.sources) s.path],
      [p.join(f.home, 'projetos')],
    );
    expect([for (final b in manifest.browsers) b.id], ['chrome']);

    await c.dismiss();
    expect(c.phase, BackupPhase.idle);
  });

  test('arquivos antigos da raiz do disco vão para a pasta do backup', () async {
    await configure();
    File(p.join(f.hd, 'secrets-2026-11-01.tar.gz.gpg')).writeAsStringSync('x');
    File(p.join(f.hd, 'LEIA-ME-RESTAURAR.md'))
        .writeAsStringSync('# Restauração do backup\n\nantigo\n');
    File(p.join(f.hd, 'notas.txt')).writeAsStringSync('da pessoa');

    await c.start();

    expect(c.outcome, BackupStepStatus.done);
    expect(
      [for (final e in Directory(f.hd).listSync()) p.basename(e.path)]..sort(),
      ['backup', 'notas.txt'],
    );
    final backup = p.join(f.hd, 'backup');
    expect(
      File(p.join(backup, 'secrets-2026-11-01.tar.gz.gpg')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(backup, 'LEIA-ME-RESTAURAR.md')).readAsStringSync(),
      isNot(contains('antigo')),
    );
  });

  test('navegador aberto é pulado e pode tentar de novo', () async {
    await configure();
    f.openChrome();
    await c.refresh();

    await c.start();

    final i = c.steps.indexWhere((s) => s.kind == BackupStepKind.browser);
    expect(c.steps[i].status, BackupStepStatus.skipped);
    expect(c.steps[i].retryable, isTrue);
    expect(c.outcome, BackupStepStatus.warnings);
    expect(
      File(p.join(f.hd, 'backup', 'LEIA-ME-RESTAURAR.md')).readAsStringSync(),
      isNot(contains('navegadores/chrome/')),
    );

    f.alive.clear();
    await c.retry(i);

    expect(c.steps[i].status, BackupStepStatus.done);
    expect(c.outcome, BackupStepStatus.done);
    expect(
      File(p.join(f.hd, 'backup', 'LEIA-ME-RESTAURAR.md')).readAsStringSync(),
      contains('navegadores/chrome/'),
    );
  });

  test('janela de senha fechada não impede o resto', () async {
    await configure();
    f.secrets.outcome = SecretsOutcome.cancelled;

    await c.start();

    expect(statuses(), [
      BackupStepStatus.done,
      BackupStepStatus.skipped,
      BackupStepStatus.done,
      BackupStepStatus.done,
      BackupStepStatus.done,
    ]);
    expect(c.steps[1].retryable, isTrue);
    expect(
      File(p.join(f.hd, 'backup', 'LEIA-ME-RESTAURAR.md')).readAsStringSync(),
      isNot(contains('gpg -d')),
    );
    expect(f.settings.value.backup.lastBackupAt, now);
  });

  test('sem espaço para na preparação', () async {
    await configure();
    f.disks.available = 3;

    await c.start();

    expect(c.steps.first.status, BackupStepStatus.failed);
    expect(c.steps.first.message, contains('Falta espaço'));
    expect(statuses().skip(1), everyElement(BackupStepStatus.skipped));
    expect(c.outcome, BackupStepStatus.failed);
    expect(f.settings.value.backup.lastBackupAt, isNull);
    expect(f.secrets.archived, isEmpty);
  });

  test('cancelar interrompe a etapa atual e as seguintes', () async {
    await configure();
    f.secrets.waitForCancel = true;

    final run = c.start();
    while (c.currentStep != 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    c.cancel();
    await run;

    expect(statuses(), [
      BackupStepStatus.done,
      BackupStepStatus.cancelled,
      BackupStepStatus.cancelled,
      BackupStepStatus.cancelled,
      BackupStepStatus.cancelled,
    ]);
    expect(c.outcome, BackupStepStatus.cancelled);
    expect(f.settings.value.backup.lastBackupAt, isNull);
    expect(File(p.join(f.hd, 'backup', 'LEIA-ME-RESTAURAR.md')).existsSync(), isFalse);
  });
}
