import 'dart:convert';
import 'dart:io';

import 'package:disk_cleanup/cleanup/trash_service.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/scan/du_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

void main() {
  late Directory tmp;
  late String trashDir;
  late FakeProcessRunner runner;

  TrashService service({Future<void> Function(String, String)? renameFn}) =>
      TrashService(
        trashDir: trashDir,
        runner: runner,
        du: DuScanner(runner),
        renameFn: renameFn,
      );

  File mk(String rel, [String content = 'x']) {
    final f = File('${tmp.path}/$rel')..createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('trash_service_test');
    trashDir = '${tmp.path}/Trash';
    runner = FakeProcessRunner();
  });

  tearDown(() => tmp.delete(recursive: true));

  test('moveToTrash cria files, info e .trashinfo válido', () async {
    final f = mk('src/relatório final.pdf');
    final e = await service().moveToTrash(f.path);

    expect(e, isNotNull);
    expect(e!.trashedName, 'relatório final.pdf');
    expect(e.originalPath, f.path);
    expect(f.existsSync(), isFalse);
    expect(File('$trashDir/files/relatório final.pdf').existsSync(), isTrue);
    final info = File('$trashDir/info/relatório final.pdf.trashinfo')
        .readAsStringSync();
    final lines = info.split('\n');
    expect(lines[0], '[Trash Info]');
    expect(lines[1], 'Path=${tmp.path}/src/relat%C3%B3rio%20final.pdf');
    expect(lines[2], matches(r'^DeletionDate=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$'));
    expect(info.endsWith('\n'), isTrue);
  });

  test('nomes repetidos recebem sufixo único', () async {
    final a = mk('a/nome.ext');
    final b = mk('b/nome.ext');
    final c = mk('c/nome.ext');
    final s = service();
    expect((await s.moveToTrash(a.path))!.trashedName, 'nome.ext');
    expect((await s.moveToTrash(b.path))!.trashedName, 'nome.2.ext');
    expect((await s.moveToTrash(c.path))!.trashedName, 'nome.3.ext');
  });

  test('nomes sem extensão recebem .2', () async {
    final a = mk('a/Makefile');
    final b = mk('b/Makefile');
    final s = service();
    await s.moveToTrash(a.path);
    expect((await s.moveToTrash(b.path))!.trashedName, 'Makefile.2');
  });

  test('restore devolve ao caminho original e remove o .trashinfo', () async {
    final f = mk('src/deep/arq.txt', 'conteudo');
    final s = service();
    final e = (await s.moveToTrash(f.path))!;
    Directory('${tmp.path}/src').deleteSync(recursive: true);

    await s.restore(e);

    expect(File(f.path).readAsStringSync(), 'conteudo');
    expect(File('$trashDir/info/arq.txt.trashinfo').existsSync(), isFalse);
    expect(File('$trashDir/files/arq.txt').existsSync(), isFalse);
  });

  test('restore nunca sobrescreve', () async {
    final f = mk('src/arq.txt', 'velho');
    final s = service();
    final e = (await s.moveToTrash(f.path))!;
    mk('src/arq.txt', 'novo');

    await expectLater(s.restore(e), throwsA(isA<FileSystemException>()));
    expect(File(f.path).readAsStringSync(), 'novo');
    expect(File('$trashDir/files/arq.txt').existsSync(), isTrue);
  });

  test('empty deixa files e info vazios porém existentes', () async {
    final s = service();
    await s.moveToTrash(mk('a/x.txt').path);
    final dir = Directory('${tmp.path}/d')..createSync();
    File('${dir.path}/y').writeAsStringSync('y');
    await s.moveToTrash(dir.path);

    await s.empty();

    expect(Directory('$trashDir/files').listSync(), isEmpty);
    expect(Directory('$trashDir/info').listSync(), isEmpty);
  });

  test('empty não segue symlinks', () async {
    final fora = mk('fora/keep.txt');
    final s = service();
    final link = Link('${tmp.path}/lnk')..createSync('${tmp.path}/fora');
    await s.moveToTrash(link.path);

    await s.empty();

    expect(fora.existsSync(), isTrue);
    expect(Directory('$trashDir/files').listSync(), isEmpty);
  });

  test('EXDEV recorre a gio trash e retorna null', () async {
    final f = mk('src/x.txt');
    runner.when('gio', ['trash', f.path], const RunResult(0, [], ''));
    final s = service(
      renameFn: (from, to) async => throw FileSystemException(
        'x',
        from,
        const OSError('Invalid cross-device link', 18),
      ),
    );

    expect(await s.moveToTrash(f.path), isNull);
    expect(runner.calls, [
      ['gio', 'trash', f.path],
    ]);
    expect(Directory('$trashDir/info').listSync(), isEmpty);
  });

  test('falha de rename remove o .trashinfo e relança', () async {
    final f = mk('src/x.txt');
    final s = service(
      renameFn: (from, to) async => throw FileSystemException(
        'x',
        from,
        const OSError('Permission denied', 13),
      ),
    );

    await expectLater(
      s.moveToTrash(f.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory('$trashDir/info').listSync(), isEmpty);
  });

  test('list retorna itens com bytes via um único du', () async {
    final s = service();
    final e1 = (await s.moveToTrash(mk('a/um.txt').path))!;
    final e2 = (await s.moveToTrash(mk('b/dois.txt').path))!;
    File('$trashDir/info/quebrado.trashinfo').writeAsStringSync('lixo');
    File('$trashDir/info/orfao.trashinfo').writeAsStringSync(
      '[Trash Info]\nPath=/x/orfao\nDeletionDate=2026-01-01T00:00:00\n',
    );

    final p1 = '$trashDir/files/${e1.trashedName}';
    final p2 = '$trashDir/files/${e2.trashedName}';
    String rec(String p, int n) => '$n\t$p\x00';
    runner.when('du', [
      '-sx',
      '-B1',
      '-0',
      p1,
      p2,
    ], RunResult(0, utf8.encode(rec(p1, 4096) + rec(p2, 8192)), ''));
    runner.when('du', [
      '-sx',
      '-B1',
      '-0',
      p2,
      p1,
    ], RunResult(0, utf8.encode(rec(p1, 4096) + rec(p2, 8192)), ''));

    final items = await s.list();
    items.sort((a, b) => a.name.compareTo(b.name));

    expect(items.map((i) => i.name), ['dois.txt', 'um.txt']);
    expect(items[0].bytes, 8192);
    expect(items[1].bytes, 4096);
    expect(items[1].originalPath, '${tmp.path}/a/um.txt');
    expect(items[1].deletedAt.year, DateTime.now().year);
    expect(runner.calls.where((c) => c.first == 'du'), hasLength(1));
  });

  test(
    'deleteFromTrash remove arquivo e info; rejeita nomes inválidos',
    () async {
      final s = service();
      final e = (await s.moveToTrash(mk('a/z.txt').path))!;

      for (final bad in ['../x', 'a/b', '..', '.']) {
        await expectLater(
          s.deleteFromTrash([bad]),
          throwsA(isA<ArgumentError>()),
        );
      }
      await s.deleteFromTrash([e.trashedName]);

      expect(Directory('$trashDir/files').listSync(), isEmpty);
      expect(Directory('$trashDir/info').listSync(), isEmpty);
    },
  );

  test('list ignora entradas malformadas e mantém as válidas', () async {
    final s = service();
    final e = (await s.moveToTrash(mk('a/ok.txt').path))!;
    mk('Trash/files/bad1.bin');
    mk('Trash/files/bad2.bin');
    File('$trashDir/info/bad1.bin.trashinfo').writeAsStringSync(
      '[Trash Info]\nPath=/tmp/x/%FF.bin\nDeletionDate=2026-01-01T00:00:00\n',
    );
    File('$trashDir/info/bad2.bin.trashinfo').writeAsBytesSync([
      ...utf8.encode('[Trash Info]\nPath=/x/'),
      0xff,
      0xfe,
      ...utf8.encode('\nDeletionDate=2026-01-01T00:00:00\n'),
    ]);
    final p1 = '$trashDir/files/${e.trashedName}';
    runner.when('du', [
      '-sx',
      '-B1',
      '-0',
      p1,
    ], RunResult(0, utf8.encode('4096\t$p1\x00'), ''));

    final items = await s.list();

    expect(items.map((i) => i.name), ['ok.txt']);
  });
}
