import 'package:disk_cleanup/backup/auto_sync.dart';
import 'package:disk_cleanup/backup/backup_controller.dart';
import 'package:disk_cleanup/backup/mount_watcher.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/settings/backup_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_process_runner.dart';
import 'backup_fakes.dart';

void main() {
  group('autoSyncDue', () {
    final now = DateTime(2026, 11, 10, 12);

    test('desligado nunca vence', () {
      expect(autoSyncDue(const BackupSettings(), now), isFalse);
    });

    test('vence quando passou o intervalo desde o último backup', () {
      final s = const BackupSettings().copyWith(
        autoSyncHours: 6,
        lastBackupAt: now.subtract(const Duration(hours: 5)),
      );
      expect(autoSyncDue(s, now), isFalse);
      expect(autoSyncDue(s, now.add(const Duration(hours: 1))), isTrue);
    });

    test('sem backup ainda vence logo', () {
      final s = const BackupSettings().copyWith(autoSyncHours: 24);
      expect(autoSyncDue(s, now), isTrue);
    });

    test('tentativa recente que falhou espera o próximo intervalo', () {
      final s = const BackupSettings().copyWith(autoSyncHours: 1);
      expect(
        autoSyncDue(
          s,
          now,
          lastAttempt: now.subtract(const Duration(minutes: 10)),
        ),
        isFalse,
      );
    });
  });

  group('agendador', () {
    late BackupFixture f;
    late BackupController b;
    late AutoSyncScheduler sync;
    var now = DateTime(2026, 11, 10, 12);

    setUp(() async {
      now = DateTime(2026, 11, 10, 12);
      f = BackupFixture();
      b = BackupController(f.services, f.settings, now: () => now);
      sync = AutoSyncScheduler(
        backup: b,
        now: () => now,
        pollInterval: const Duration(hours: 1),
      );
      await b.refresh();
      await b.chooseDestination(f.hd);
      await b.addSource(p.join(f.home, 'projetos'));
    });

    tearDown(() {
      sync.dispose();
      b.dispose();
      f.dispose();
    });

    test('nada acontece com o sync desligado', () async {
      f.disks.connected = false;
      await sync.check();
      f.disks.connected = true;
      await sync.check();
      expect(sync.last, isNull);
      expect(f.settings.value.backup.lastBackupAt, isNull);
    });

    test('ao conectar o disco faz o backup sem pedir a senha', () async {
      await b.setAutoSyncOnConnect(true);
      await sync.check();
      expect(sync.last, isNull, reason: 'já estava conectado ao abrir');

      f.disks.connected = false;
      await sync.check();
      f.disks.connected = true;
      await sync.check();

      expect(sync.last!.trigger, AutoSyncTrigger.connect);
      expect(sync.last!.outcome, BackupStepStatus.done);
      expect(f.secrets.archived, isEmpty);
      expect(f.settings.value.backup.lastBackupAt, now);
      expect(b.phase, BackupPhase.idle);
    });

    test('por intervalo, só quando vence', () async {
      await b.setAutoSyncHours(6);
      await sync.check();
      expect(sync.last!.trigger, AutoSyncTrigger.interval);
      expect(f.settings.value.backup.lastBackupAt, now);

      final first = sync.last;
      now = now.add(const Duration(hours: 5));
      await sync.check();
      expect(sync.last, same(first));

      now = now.add(const Duration(hours: 1));
      await sync.check();
      expect(sync.last, isNot(same(first)));
      expect(f.settings.value.backup.lastBackupAt, now);
    });

    test('não começa com o backup ocupado ou com problemas', () async {
      await b.setAutoSyncHours(1);
      final other = Object();
      f.services.backup.lock.acquire(other);
      await sync.check();
      expect(sync.last, isNull);
      f.services.backup.lock.release(other);

      f.disks.connected = false;
      await sync.check();
      expect(sync.last, isNull);
    });

    test('backup que falha fica visível para a pessoa', () async {
      await b.setAutoSyncHours(1);
      f.disks.available = 0;
      await sync.check();
      expect(sync.last!.outcome, BackupStepStatus.failed);
      expect(b.phase, BackupPhase.finished);
    });

    test('falha automática some na próxima vez que vence', () async {
      await b.setAutoSyncHours(1);
      f.disks.available = 0;
      await sync.check();
      expect(sync.last!.outcome, BackupStepStatus.failed);

      f.disks.available = 1000000000000;
      now = now.add(const Duration(hours: 1));
      await sync.check();
      expect(sync.last!.outcome, BackupStepStatus.done);
      expect(b.phase, BackupPhase.idle);
      expect(f.settings.value.backup.lastBackupAt, now);
    });

    test(
      'sem poder rodar espera o intervalo antes de tentar de novo',
      () async {
        await b.setAutoSyncHours(1);
        await b.removeSource(p.join(f.home, 'projetos'));
        var notified = 0;
        b.addListener(() => notified++);
        await sync.check();
        expect(notified, greaterThan(0));
        expect(sync.last, isNull);

        notified = 0;
        now = now.add(const Duration(minutes: 5));
        await sync.check();
        expect(notified, 0);
      },
    );

    test('evento de montagem verifica depois da espera', () async {
      final runner = FakeProcessRunner()
        ..whenStreaming(
          'findmnt',
          const ['--poll', '-n', '-r', '-o', 'ACTION,TARGET'],
          lines: ['mount ${f.hd}'],
          result: const RunResult(127, [], ''),
        );
      await b.setAutoSyncOnConnect(true);
      f.disks.connected = false;
      final watched = AutoSyncScheduler(
        backup: b,
        watcher: MountWatcher(runner),
        now: () => now,
        pollInterval: const Duration(hours: 1),
        connectDelay: const Duration(milliseconds: 20),
      );
      addTearDown(watched.dispose);
      watched.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      f.disks.connected = true;
      for (var i = 0; i < 100 && watched.last?.outcome == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(watched.last?.trigger, AutoSyncTrigger.connect);
      expect(watched.last?.outcome, BackupStepStatus.done);
    });
  });
}
