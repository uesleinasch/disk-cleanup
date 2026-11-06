import 'package:disk_cleanup/core/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

void main() {
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
