import 'dart:convert';
import 'dart:io';

import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/scan/large_files.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

void main() {
  test('interpreta registros do find', () async {
    final fake = FakeProcessRunner();
    const path = '/h/Downloads/Dispatch [BASE][01008BA02525A000][v0].nsz';
    fake.when(
      'find',
      [
        '/h',
        '-xdev',
        '(',
        '-path',
        '/h/skip',
        ')',
        '-prune',
        '-o',
        '-type',
        'f',
        '-size',
        '+999999999c',
        '-printf',
        r'%s\t%A@\t%T@\t%p\0',
      ],
      RunResult(
        0,
        utf8.encode(
          '6700000000\t1730000000.5\t1730000000.0\t$path\x00'
          'lixo\x00'
          '5\tx\t1.0\t/h/a\x00',
        ),
        '',
      ),
    );
    final result = await LargeFileFinder(fake)
        .find(['/h'], excludeRoots: ['/h/skip']);
    expect(result, hasLength(1));
    expect(result.single.path, path);
    expect(result.single.bytes, 6700000000);
    expect(
      result.single.lastAccess,
      DateTime.fromMillisecondsSinceEpoch(1730000000500),
    );
    expect(
      result.single.modified,
      DateTime.fromMillisecondsSinceEpoch(1730000000000),
    );
  });

  test('sem excludes omite o grupo de prune e tolera exit 1', () async {
    final fake = FakeProcessRunner();
    fake.when('find', [
      '/h',
      '-xdev',
      '-type',
      'f',
      '-size',
      '+999c',
      '-printf',
      r'%s\t%A@\t%T@\t%p\0',
    ], RunResult(1, utf8.encode('10\t1.0\t2.0\t/h/a\tb\nc\x00'), ''));
    final result = await LargeFileFinder(fake).find(['/h'], minBytes: 1000);
    expect(result.single.path, '/h/a\tb\nc');
  });

  group('integração', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('large_files_'));
    tearDown(() => root.deleteSync(recursive: true));

    test(
      'filtra por tamanho, exclusão e symlink; ordena e deduplica',
      () async {
        File('${root.path}/vídeo com espaço.mp4')
            .writeAsBytesSync(List.filled(2000, 1));
        File('${root.path}/pequeno.txt').writeAsBytesSync(List.filled(10, 1));
        File('${root.path}/maior.bin').writeAsBytesSync(List.filled(3000, 1));
        Directory('${root.path}/skip').createSync();
        File('${root.path}/skip/grande.bin')
            .writeAsBytesSync(List.filled(5000, 1));
        Link('${root.path}/link.bin').createSync('${root.path}/maior.bin');

        final result = await LargeFileFinder(SystemProcessRunner()).find(
          [root.path, root.path],
          minBytes: 1000,
          excludeRoots: ['${root.path}/skip'],
        );
        expect(result.map((f) => f.path), [
          '${root.path}/maior.bin',
          '${root.path}/vídeo com espaço.mp4',
        ]);
        expect(result.first.bytes, 3000);
      },
    );
  });
}
