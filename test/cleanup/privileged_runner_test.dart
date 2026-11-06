import 'package:disk_cleanup/cleanup/privileged_runner.dart';
import 'package:disk_cleanup/core/models.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

RunResult ok(String out, {int code = 0}) => RunResult(code, out.codeUnits, '');

void main() {
  group('validação', () {
    test('SnapRemoveRevision rejeita injeção e formatos inválidos', () {
      expect(
        () => SnapRemoveRevision("core20'; rm -rf / #", '1'),
        throwsArgumentError,
      );
      expect(() => SnapRemoveRevision('Core', '1'), throwsArgumentError);
      expect(() => SnapRemoveRevision('-x', '1'), throwsArgumentError);
      expect(() => SnapRemoveRevision('core20', '1a'), throwsArgumentError);
      expect(() => SnapRemoveRevision('core20', '1\n'), throwsArgumentError);
      expect(() => SnapRemoveRevision('core20\n', '1'), throwsArgumentError);
    });

    test('DuMeasure rejeita relativo, .., aspas, NUL e newline', () {
      expect(() => DuMeasure('relativo'), throwsArgumentError);
      expect(() => DuMeasure('/a/../b'), throwsArgumentError);
      expect(() => DuMeasure('/a/..'), throwsArgumentError);
      expect(() => DuMeasure("/a/b'c"), throwsArgumentError);
      expect(() => DuMeasure('/a\nb'), throwsArgumentError);
      expect(() => DuMeasure('/a\u0000b'), throwsArgumentError);
      expect(() => DuMeasure("/a'; rm -rf /; echo '"), throwsArgumentError);
      expect(DuMeasure('/a/..b/c').toShell(), contains("'/a/..b/c'"));
    });

    test('DockerCli valida ids por operação', () {
      expect(
        () => DockerCli(DockerOp.inventory, ['abcdef123456']),
        throwsArgumentError,
      );
      expect(
        () => DockerCli(DockerOp.pruneBuildCache, ['abcdef123456']),
        throwsArgumentError,
      );
      expect(
        () => DockerCli(DockerOp.removeContainers, []),
        throwsArgumentError,
      );
      expect(
        () => DockerCli(DockerOp.removeContainers, ['abc']),
        throwsArgumentError,
      );
      expect(
        () => DockerCli(DockerOp.removeImages, ["abcdef123456'; id #"]),
        throwsArgumentError,
      );
      expect(
        () => DockerCli(DockerOp.removeContainers, ['ABCDEF123456']),
        throwsArgumentError,
      );
      expect(
        () => DockerCli(DockerOp.removeVolumes, ['-v']),
        throwsArgumentError,
      );
      expect(
        () => DockerCli(DockerOp.removeVolumes, ['a b']),
        throwsArgumentError,
      );
      expect(() => DockerCli(DockerOp.removeVolumes, []), throwsArgumentError);
    });
  });

  group('toShell', () {
    test('comandos gerados', () {
      expect(
        JournalVacuum().toShell(),
        '/usr/bin/journalctl --vacuum-size=500M',
      );
      expect(AptClean().toShell(), '/usr/bin/apt-get clean');
      expect(
        SnapRemoveRevision('core20', '1234').toShell(),
        "/usr/bin/snap remove 'core20' --revision='1234'",
      );
      expect(
        DuMeasure('/var/log').toShell(),
        "/usr/bin/du -sx -B1 -0 '/var/log'",
      );
      expect(
        DockerCli(DockerOp.inventory, const []).toShell(),
        "/usr/bin/docker system df -v --format '{{json .}}'",
      );
      expect(
        DockerCli(DockerOp.pruneBuildCache, const []).toShell(),
        '/usr/bin/docker builder prune -f',
      );
      expect(
        DockerCli(DockerOp.removeContainers, [
          'abcdef123456',
          'a' * 64,
        ]).toShell(),
        "/usr/bin/docker rm 'abcdef123456' '${'a' * 64}'",
      );
      expect(
        DockerCli(DockerOp.removeImages, ['abcdef123456']).toShell(),
        "/usr/bin/docker rmi 'abcdef123456'",
      );
      expect(
        DockerCli(DockerOp.removeVolumes, ['my_vol-1.x']).toShell(),
        "/usr/bin/docker volume rm 'my_vol-1.x'",
      );
    });

    test('buildRootScript gera uma linha por comando', () {
      final script = buildRootScript([JournalVacuum(), AptClean()]);
      final lines = script.split('\n');
      expect(lines, hasLength(2));
      expect(
        lines[0],
        '/usr/bin/journalctl --vacuum-size=500M; echo "__dc_status 0 \$?"',
      );
      expect(lines[1], '/usr/bin/apt-get clean; echo "__dc_status 1 \$?"');
      expect(script, isNot(contains('set -e')));
    });
  });

  group('PrivilegedRunner', () {
    final cmds = <RootCommand>[JournalVacuum(), AptClean(), DuMeasure('/var')];

    test('chama pkexec uma vez com o script', () async {
      final fake = FakeProcessRunner();
      fake.when('pkexec', [
        '/bin/sh',
        '-c',
        buildRootScript(cmds),
      ], ok('__dc_status 0 0\n__dc_status 1 0\n__dc_status 2 0\n'));
      final r = await PrivilegedRunner(fake).run(cmds);
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.first, 'pkexec');
      expect(r.cancelled, isFalse);
    });

    test('parseia exit codes', () async {
      final fake = FakeProcessRunner();
      final two = cmds.sublist(0, 2);
      fake.when('pkexec', [
        '/bin/sh',
        '-c',
        buildRootScript(two),
      ], ok('x\n__dc_status 0 0\n__dc_status 1 1\n'));
      final r = await PrivilegedRunner(fake).run(two);
      expect(r.exitCodes, {0: 0, 1: 1});
      expect(r.cancelled, isFalse);
    });

    test('exit 126 sem status é cancelamento', () async {
      final fake = FakeProcessRunner();
      fake.when('pkexec', [
        '/bin/sh',
        '-c',
        buildRootScript(cmds),
      ], ok('', code: 126));
      final r = await PrivilegedRunner(fake).run(cmds);
      expect(r.cancelled, isTrue);
      expect(r.exitCodes, isEmpty);
    });

    test('exit 127 sem status é cancelamento; com status não é', () async {
      final fake = FakeProcessRunner();
      final one = [JournalVacuum()];
      fake.when('pkexec', [
        '/bin/sh',
        '-c',
        buildRootScript(one),
      ], ok('__dc_status 0 127\n', code: 127));
      final r = await PrivilegedRunner(fake).run(one);
      expect(r.cancelled, isFalse);
      expect(r.exitCodes, {0: 127});
    });

    test('lista vazia não chama pkexec', () async {
      final fake = FakeProcessRunner();
      final r = await PrivilegedRunner(fake).run(const []);
      expect(fake.calls, isEmpty);
      expect(r.cancelled, isFalse);
      expect(r.exitCodes, isEmpty);
    });
  });

  group('serialização', () {
    test('RootCommand faz round-trip e revalida', () {
      final cmds = <RootCommand>[
        JournalVacuum(),
        AptClean(),
        SnapRemoveRevision('core20', '7'),
        DuMeasure('/var/lib'),
        DockerCli(DockerOp.removeImages, ['abcdef123456']),
      ];
      for (final c in cmds) {
        expect(RootCommand.fromJson(c.toJson()).toShell(), c.toShell());
      }
      expect(
        () => RootCommand.fromJson({
          'type': 'snapRemove',
          'name': "x'",
          'revision': '1',
        }),
        throwsArgumentError,
      );
      expect(
        () => RootCommand.fromJson({'type': 'nope'}),
        throwsFormatException,
      );
    });
  });
}
