import 'dart:convert';
import 'dart:io';

import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/scan/du_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

RunResult _out(int code, String stdout, [String stderr = '']) =>
    RunResult(code, utf8.encode(stdout), stderr);

void main() {
  const childArgs = ['-x', '-a', '-d1', '-B1', '-0', '/h'];

  test('childrenSizes separa filhos e total do próprio diretório', () async {
    final fake = FakeProcessRunner()
      ..when(
        'du',
        childArgs,
        _out(
          0,
          '1000\t/h/a b\x00'
          '2000\t/h/Dispatch [BASE].nsz\x00'
          '3000\t/h\x00',
        ),
      );
    final r = await DuScanner(fake).childrenSizes('/h');
    expect(r.entries.map((e) => e.path), ['/h/a b', '/h/Dispatch [BASE].nsz']);
    expect(r.entries.map((e) => e.bytes), [1000, 2000]);
    expect(r.total, 3000);
    expect(r.errors, 0);
    expect(r.permissionDenied, isFalse);
  });

  test(
    'saída parcial com erro conta errors e não é permissionDenied',
    () async {
      final fake = FakeProcessRunner()
        ..when(
          'du',
          childArgs,
          _out(
            1,
            '1000\t/h/a\x003000\t/h\x00',
            "du: cannot read directory '/h/x': Permission denied\n",
          ),
        );
      final r = await DuScanner(fake).childrenSizes('/h');
      expect(r.entries, hasLength(1));
      expect(r.errors, 1);
      expect(r.permissionDenied, isFalse);
    },
  );

  test(
    'sem registro do próprio dir e Permission denied marca negado',
    () async {
      final fake = FakeProcessRunner()
        ..when(
          'du',
          childArgs,
          _out(1, '', "du: cannot read directory '/h': Permission denied\n"),
        );
      final r = await DuScanner(fake).childrenSizes('/h');
      expect(r.permissionDenied, isTrue);
      expect(r.total, 0);
      expect(r.entries, isEmpty);
    },
  );

  test('token já cancelado lança ScanCancelled sem chamar du', () async {
    final fake = FakeProcessRunner();
    final token = CancelToken()..cancel();
    await expectLater(
      DuScanner(fake).childrenSizes('/h', cancel: token),
      throwsA(isA<ScanCancelled>()),
    );
    expect(fake.calls, isEmpty);
  });

  test('sizesOf mede caminhos e omite ausentes', () async {
    final fake = FakeProcessRunner()
      ..when('du', [
        '-sx',
        '-B1',
        '-0',
        '/h/a/',
        '/h/b',
      ], _out(1, '10\t/h/a\x00', "du: cannot access '/h/b': No such file\n"));
    final r = await DuScanner(fake).sizesOf(['/h/a/', '/h/b']);
    expect(r, {'/h/a': 10});
  });

  test('sizesOf vazio não chama du', () async {
    final fake = FakeProcessRunner();
    expect(await DuScanner(fake).sizesOf([]), isEmpty);
    expect(fake.calls, isEmpty);
  });

  group('integração com du real', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('du_scanner_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('preserva nomes com quebra de linha e acentos', () async {
      File('${tmp.path}/x\ny.bin').writeAsBytesSync(List.filled(10, 1));
      File('${tmp.path}/acentuação.txt').writeAsStringSync('olá');
      final r = await DuScanner(SystemProcessRunner()).childrenSizes(tmp.path);
      final names = r.entries.map((e) => e.path).toSet();
      expect(names, {'${tmp.path}/x\ny.bin', '${tmp.path}/acentuação.txt'});
      expect(r.total, greaterThan(0));
    });
  });
}
