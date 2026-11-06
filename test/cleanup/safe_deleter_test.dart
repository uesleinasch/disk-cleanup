import 'dart:io';

import 'package:disk_cleanup/cleanup/safe_deleter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late SafeDeleter deleter;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('safe_deleter_test');
    deleter = SafeDeleter(
      allowedRoots: [tmp.path],
      protectedPaths: ['${tmp.path}/home'],
    );
  });

  tearDown(() => tmp.delete(recursive: true));

  test('apaga diretório dentro da raiz permitida', () async {
    final dir = Directory('${tmp.path}/home/proj/node_modules')
      ..createSync(recursive: true);
    File('${dir.path}/a.js').writeAsStringSync('x');
    expect(await deleter.delete(dir.path), DeleteOutcome.deleted);
    expect(dir.existsSync(), isFalse);
    expect(Directory('${tmp.path}/home/proj').existsSync(), isTrue);
  });

  test('apaga arquivo', () async {
    final f = File('${tmp.path}/home/a.txt')..createSync(recursive: true);
    expect(await deleter.delete(f.path), DeleteOutcome.deleted);
    expect(f.existsSync(), isFalse);
  });

  test('recusa caminho protegido, ancestral, raiz e /', () async {
    Directory('${tmp.path}/home').createSync();
    expect(await deleter.delete('${tmp.path}/home'), DeleteOutcome.refused);
    expect(await deleter.delete(tmp.path), DeleteOutcome.refused);
    expect(await deleter.delete('/'), DeleteOutcome.refused);
    expect(Directory('${tmp.path}/home').existsSync(), isTrue);
  });

  test('recusa fora das raízes permitidas', () async {
    expect(await deleter.delete('/etc'), DeleteOutcome.refused);
  });

  test('recusa caminho relativo', () async {
    expect(await deleter.delete('home/proj'), DeleteOutcome.refused);
  });

  test('recusa ".." que normaliza para fora', () async {
    final outside = Directory('${tmp.path}/home/x')
      ..createSync(recursive: true);
    final sneaky = '${outside.path}/../../../etc';
    expect(await deleter.delete(sneaky), DeleteOutcome.refused);
  });

  test('".." que continua dentro da raiz é normalizado', () async {
    final d = Directory('${tmp.path}/home/a/b')..createSync(recursive: true);
    expect(
      await deleter.delete('${d.path}/../../../home'),
      DeleteOutcome.refused,
    );
    expect(await deleter.delete('${d.path}/../b'), DeleteOutcome.deleted);
  });

  test('caminho inexistente é missing', () async {
    expect(
      await deleter.delete('${tmp.path}/home/nada'),
      DeleteOutcome.missing,
    );
  });

  test('symlink é removido sem tocar no alvo', () async {
    final fora = Directory('${tmp.path}/fora')..createSync();
    File('${fora.path}/arquivo').writeAsStringSync('x');
    Directory('${tmp.path}/home').createSync();
    final link = Link('${tmp.path}/home/link')..createSync(fora.path);
    expect(await deleter.delete(link.path), DeleteOutcome.deleted);
    expect(
      FileSystemEntity.typeSync(link.path, followLinks: false),
      FileSystemEntityType.notFound,
    );
    expect(File('${fora.path}/arquivo').existsSync(), isTrue);
  });
}
