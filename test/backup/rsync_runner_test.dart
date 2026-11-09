import 'dart:io';

import 'package:disk_cleanup/backup/backup_planner.dart';
import 'package:disk_cleanup/backup/rsync_runner.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_process_runner.dart';

const _stats = [
  'Number of files: 3 (reg: 2, dir: 1)',
  'Number of regular files transferred: 2',
  'Total file size: 300,000,002 bytes',
  'Total transferred file size: 300,000,002 bytes',
];

void main() {
  group('parseRsyncProgress', () {
    test('linhas reais do progress2 em locale C', () {
      final start = parseRsyncProgress(
        '         32,768   0%    0.00kB/s    0:00:00  ',
      )!;
      expect(start.bytes, 32768);
      expect(start.percent, 0);
      expect(start.bytesPerSecond, 0);

      final mid = parseRsyncProgress(
        '    106,856,448  35%  100.07MB/s    0:00:01  ',
      )!;
      expect(mid.bytes, 106856448);
      expect(mid.percent, 35);
      expect(mid.bytesPerSecond, (100.07 * 1024 * 1024).round());
      expect(mid.remaining, const Duration(seconds: 1));

      final end = parseRsyncProgress(
        '  1,300,000,002 100%    1.50GB/s    1:02:03 (xfr#2, to-chk=0/3)',
      )!;
      expect(end.percent, 100);
      expect(end.bytesPerSecond, (1.5 * 1024 * 1024 * 1024).round());
      expect(end.remaining, const Duration(hours: 1, minutes: 2, seconds: 3));
    });

    test('ignora o que não é progresso', () {
      for (final line in [
        'Number of files: 3 (reg: 2, dir: 1)',
        'sending incremental file list',
        'total size is 300,000,002  speedup is 1.00',
        '',
      ]) {
        expect(parseRsyncProgress(line), isNull, reason: line);
      }
    });
  });

  group('interpretRsync', () {
    test('0 é sucesso com estatísticas', () {
      final r = interpretRsync(const RunResult(0, [], ''), _stats);
      expect(r.outcome, RsyncOutcome.ok);
      expect(r.stats!.totalBytes, 300000002);
    });

    test('23 e 24 são avisos com as linhas do stderr', () {
      const stderr =
          'rsync: [sender] send_files failed to open "/src/a": Permission denied (13)\n'
          'file has vanished: "/src/b"\n'
          'rsync error: some files/attrs were not transferred (see previous errors) (code 23)\n';
      for (final code in [23, 24]) {
        final r = interpretRsync(RunResult(code, const [], stderr), _stats);
        expect(r.outcome, RsyncOutcome.warnings);
        expect(r.stats, isNotNull);
        expect(r.warnings, [
          'rsync: [sender] send_files failed to open "/src/a": Permission denied (13)',
          'file has vanished: "/src/b"',
        ]);
      }
    });

    test('127 diz para instalar o rsync', () {
      final r = interpretRsync(const RunResult(127, [], ''), const []);
      expect(r.outcome, RsyncOutcome.failed);
      expect(r.error, contains('Instale o pacote rsync'));
    });

    test('outros códigos são erro com o fim do stderr', () {
      final r = interpretRsync(
        const RunResult(
          11,
          [],
          'a\nb\nrsync: write failed: No space left on device (28)\nrsync error: error in file IO (code 11)\n',
        ),
        const [],
      );
      expect(r.outcome, RsyncOutcome.failed);
      expect(r.error, startsWith('b\n'));
      expect(r.error, contains('No space left'));
      expect(
        interpretRsync(const RunResult(12, [], ''), const []).error,
        'O rsync terminou com o código 12.',
      );
    });
  });

  test('RsyncRunner separa progresso de estatísticas e usa LC_ALL=C', () async {
    final args = backupRsyncArgs(
      filterFile: '/tmp/regras',
      sources: ['/home/user/projetos'],
      destination: '/media/user/Disco externo/backup',
      mirror: true,
    );
    final fake = FakeProcessRunner()
      ..whenStreaming(
        'rsync',
        args,
        lines: [
          '    106,856,448  35%  100.07MB/s    0:00:01  ',
          '    300,000,002 100%  101.84MB/s    0:00:02 (xfr#2, to-chk=0/3)',
          ..._stats,
        ],
      );
    final progress = <int>[];
    final r = await RsyncRunner(fake).copy(
      filterFile: '/tmp/regras',
      sources: ['/home/user/projetos'],
      destination: '/media/user/Disco externo/backup',
      mirror: true,
      onProgress: (pr) => progress.add(pr.percent),
    );
    expect(progress, [35, 100]);
    expect(r.outcome, RsyncOutcome.ok);
    expect(r.stats!.files, 2);
    expect(fake.calls.single, contains('--delete'));
    expect(fake.environments.single, {'LC_ALL': 'C'});
  });

  group('cópia real', () {
    late Directory tmp;

    String path(String rel) => p.join(tmp.path, rel);

    void file(String rel, [String content = 'x']) {
      File(path(rel))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    Future<RsyncResult> copy({bool mirror = false}) async {
      final rules = File(path('regras'));
      await BackupFilter(sources: [path('src')]).writeTo(rules);
      return RsyncRunner(SystemProcessRunner()).copy(
        filterFile: rules.path,
        sources: [path('src')],
        destination: path('dest/backup'),
        mirror: mirror,
      );
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('rsync_runner_');
      Directory(path('dest')).createSync();
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('copia, acumula por padrão e apaga só com espelhar', () async {
      file('src/a.txt', 'aaa');
      file('src/b.txt', 'bb');
      file('src/node_modules/x.js');

      final first = await copy();
      expect(first.outcome, RsyncOutcome.ok);
      expect(first.stats!.transferredBytes, 5);
      expect(File(path('dest/backup/src/a.txt')).readAsStringSync(), 'aaa');
      expect(
        Directory(path('dest/backup/src/node_modules')).existsSync(),
        isFalse,
      );

      File(path('src/b.txt')).deleteSync();
      final second = await copy();
      expect(second.stats!.transferredBytes, 0);
      expect(File(path('dest/backup/src/b.txt')).existsSync(), isTrue);

      await copy(mirror: true);
      expect(File(path('dest/backup/src/b.txt')).existsSync(), isFalse);
      expect(File(path('dest/backup/src/a.txt')).existsSync(), isTrue);
    });

    test('arquivo sem permissão vira aviso, o resto é copiado', () async {
      file('src/ok.txt');
      file('src/fechado.txt');
      Process.runSync('chmod', ['000', path('src/fechado.txt')]);
      addTearDown(
        () => Process.runSync('chmod', ['644', path('src/fechado.txt')]),
      );

      final r = await copy();

      expect(r.outcome, RsyncOutcome.warnings);
      expect(r.warnings.single, contains('fechado.txt'));
      expect(File(path('dest/backup/src/ok.txt')).existsSync(), isTrue);
    });
  });
}
