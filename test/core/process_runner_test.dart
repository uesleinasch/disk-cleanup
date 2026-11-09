import 'dart:convert';
import 'dart:io';

import 'package:disk_cleanup/core/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

void main() {
  group('runStreaming', () {
    Future<(RunResult, List<String>)> stream(
      String script, {
      Map<String, String>? environment,
    }) async {
      final lines = <String>[];
      final r = await SystemProcessRunner().runStreaming(
        '/bin/sh',
        ['-c', script],
        onLine: lines.add,
        environment: environment,
      );
      return (r, lines);
    }

    test(
      'separa linhas por \\r, \\n e \\r\\n, em ordem e sem vazias',
      () async {
        final (r, lines) = await stream(r"printf 'a\rb\nc\r\nd\r\re'");
        expect(r.exitCode, 0);
        expect(lines, ['a', 'b', 'c', 'd', 'e']);
      },
    );

    test('preserva código de saída e stderr', () async {
      final (r, lines) = await stream('echo saida; echo erro >&2; exit 3');
      expect(r.exitCode, 3);
      expect(r.stderr, 'erro\n');
      expect(lines, ['saida']);
    });

    test('repassa variáveis de ambiente', () async {
      final (_, lines) = await stream(
        r'echo "$LC_ALL"',
        environment: {'LC_ALL': 'C'},
      );
      expect(lines, ['C']);
    });

    test('binário ausente vira exitCode 127', () async {
      final r = await SystemProcessRunner().runStreaming(
        'binario-que-nao-existe',
        [],
        onLine: (_) {},
      );
      expect(r.exitCode, 127);
    });

    test('entrega a linha antes do processo terminar', () async {
      final token = CancelToken();
      final lines = <String>[];
      final sw = Stopwatch()..start();
      await expectLater(
        SystemProcessRunner().runStreaming(
          '/bin/sh',
          ['-c', 'echo um; sleep 5; echo dois'],
          onLine: (l) {
            lines.add(l);
            token.cancel();
          },
          cancel: token,
        ),
        throwsA(isA<ScanCancelled>()),
      );
      expect(lines, ['um']);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('cancelar manda SIGTERM e espera o processo encerrar', () async {
      final dir = await Directory.systemTemp.createTemp('runner_test');
      addTearDown(() => dir.delete(recursive: true));
      final marker = File('${dir.path}/encerrou');
      final token = CancelToken();
      Future.delayed(const Duration(milliseconds: 200), token.cancel);
      await expectLater(
        SystemProcessRunner().runStreaming(
          '/bin/sh',
          [
            '-c',
            r'trap "kill $!; echo ok > \"$1\"; exit 0" TERM; sleep 30 & wait',
            'sh',
            marker.path,
          ],
          onLine: (_) {},
          cancel: token,
        ),
        throwsA(isA<ScanCancelled>()),
      );
      expect(marker.readAsStringSync(), 'ok\n');
    });

    test('processo que ignora SIGTERM leva SIGKILL após o prazo', () async {
      final token = CancelToken();
      Future.delayed(const Duration(milliseconds: 100), token.cancel);
      final sw = Stopwatch()..start();
      await expectLater(
        SystemProcessRunner(termGrace: const Duration(milliseconds: 200))
            .runStreaming(
              '/bin/sh',
              ['-c', 'trap "" TERM; sleep 3 & wait'],
              onLine: (_) {},
              cancel: token,
            ),
        throwsA(isA<ScanCancelled>()),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('token já cancelado não inicia o processo', () async {
      final token = CancelToken()..cancel();
      await expectLater(
        SystemProcessRunner().runStreaming(
          'sleep',
          ['5'],
          onLine: (_) {},
          cancel: token,
        ),
        throwsA(isA<ScanCancelled>()),
      );
    });
  });

  group('runPiped', () {
    test('liga a saída do primeiro à entrada do segundo', () async {
      final (a, b) = await SystemProcessRunner().runPiped(
        const Command('/bin/sh', [
          '-c',
          r'printf "um\ndois\n"; echo aviso >&2',
        ]),
        const Command('/bin/sh', [
          '-c',
          r'tr a-z A-Z; echo "$FOO" >&2; exit 3',
        ]),
        environment: {'FOO': 'bar'},
      );
      expect(a.exitCode, 0);
      expect(a.stderr, 'aviso\n');
      expect(b.exitCode, 3);
      expect(utf8.decode(b.stdout), 'UM\nDOIS\n');
      expect(b.stderr, 'bar\n');
    });

    test('consumidor que sai cedo encerra o produtor', () async {
      final sw = Stopwatch()..start();
      final (a, b) = await SystemProcessRunner().runPiped(
        const Command('/bin/sh', ['-c', 'while :; do echo x; done']),
        const Command('/bin/sh', ['-c', 'exit 2']),
      );
      expect(b.exitCode, 2);
      expect(a.exitCode, isNot(0));
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('binário ausente vira 127 no lado certo', () async {
      final (a, b) = await SystemProcessRunner().runPiped(
        const Command('binario-que-nao-existe', []),
        const Command('cat', []),
      );
      expect(a.exitCode, 127);
      expect(b, same(notStarted));
      final (c, d) = await SystemProcessRunner().runPiped(
        const Command('echo', ['x']),
        const Command('binario-que-nao-existe', []),
      );
      expect(c, same(notStarted));
      expect(d.exitCode, 127);
    });

    test('cancelar encerra os dois e lança ScanCancelled', () async {
      final token = CancelToken();
      Future.delayed(const Duration(milliseconds: 100), token.cancel);
      final sw = Stopwatch()..start();
      await expectLater(
        SystemProcessRunner().runPiped(
          const Command('sleep', ['30']),
          const Command('cat', []),
          cancel: token,
        ),
        throwsA(isA<ScanCancelled>()),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  test('FakeProcessRunner roteiriza linhas, ambiente e cancelamento', () async {
    final fake = FakeProcessRunner()
      ..whenStreaming(
        'rsync',
        ['-a', '/a', '/b'],
        lines: ['10%', '50%', '100%'],
        result: const RunResult(24, [], 'sumiu'),
      );
    final lines = <String>[];
    final r = await fake.runStreaming(
      'rsync',
      ['-a', '/a', '/b'],
      onLine: lines.add,
      environment: {'LC_ALL': 'C'},
    );
    expect(lines, ['10%', '50%', '100%']);
    expect(r.exitCode, 24);
    expect(fake.calls, [
      ['rsync', '-a', '/a', '/b'],
    ]);
    expect(fake.environments, [
      {'LC_ALL': 'C'},
    ]);

    final token = CancelToken();
    final seen = <String>[];
    await expectLater(
      fake.runStreaming(
        'rsync',
        ['-a', '/a', '/b'],
        onLine: (l) {
          seen.add(l);
          token.cancel();
        },
        cancel: token,
      ),
      throwsA(isA<ScanCancelled>()),
    );
    expect(seen, ['10%']);
    await expectLater(
      fake.runStreaming('rsync', ['/x'], onLine: (_) {}),
      throwsA(isA<StateError>()),
    );
  });

  test('SystemProcessRunner captura saída e código', () async {
    final r = await SystemProcessRunner().run('echo', ['oi']);
    expect(r.exitCode, 0);
    expect(r.stdoutText.trim(), 'oi');
  });

  test('cancelar mata o processo e lança ScanCancelled', () async {
    final token = CancelToken();
    Future.delayed(const Duration(milliseconds: 100), token.cancel);
    final sw = Stopwatch()..start();
    await expectLater(
      SystemProcessRunner().run('sleep', ['5'], cancel: token),
      throwsA(isA<ScanCancelled>()),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('token já cancelado durante o start ainda aborta rápido', () async {
    final token = CancelToken();
    final sw = Stopwatch()..start();
    final future = SystemProcessRunner().run('sleep', ['5'], cancel: token);
    token.cancel();
    await expectLater(future, throwsA(isA<ScanCancelled>()));
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('neto segurando o pipe não trava o cancelamento', () async {
    final token = CancelToken();
    Future.delayed(const Duration(milliseconds: 100), token.cancel);
    final sw = Stopwatch()..start();
    await expectLater(
      SystemProcessRunner().run('/bin/sh', [
        '-c',
        'sleep 30 & sleep 30',
      ], cancel: token),
      throwsA(isA<ScanCancelled>()),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('binário ausente vira exitCode 127', () async {
    final r = await SystemProcessRunner().run('binario-que-nao-existe', []);
    expect(r.exitCode, 127);
  });

  test(
    'FakeProcessRunner responde por comparação exata e registra chamadas',
    () async {
      final fake = FakeProcessRunner()
        ..when('du', ['-x', '/a'], RunResult(0, 'ok'.codeUnits, ''));
      final r = await fake.run('du', ['-x', '/a']);
      expect(r.stdoutText, 'ok');
      expect(fake.calls, [
        ['du', '-x', '/a'],
      ]);
      await expectLater(
        fake.run('du', ['/a']),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('du /a'),
          ),
        ),
      );
    },
  );
}
