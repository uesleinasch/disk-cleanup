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

  test('recusa ancestral de caminho protegido', () async {
    Directory('${tmp.path}/home/proj').createSync(recursive: true);
    final d = SafeDeleter(
      allowedRoots: [tmp.path],
      protectedPaths: ['${tmp.path}/home/proj'],
    );
    expect(await d.delete('${tmp.path}/home'), DeleteOutcome.refused);
    expect(Directory('${tmp.path}/home/proj').existsSync(), isTrue);
  });

  test('recusa irmão com prefixo comum da raiz', () async {
    Directory('${tmp.path}/a').createSync();
    final x = File('${tmp.path}/ab/x')..createSync(recursive: true);
    final d = SafeDeleter(allowedRoots: ['${tmp.path}/a'], protectedPaths: []);
    expect(await d.delete(x.path), DeleteOutcome.refused);
    expect(x.existsSync(), isTrue);
  });

  test('recusa alvo alcançado por symlink de diretório que escapa', () async {
    final victim = File('${tmp.path}/outside/victim')
      ..createSync(recursive: true);
    Directory('${tmp.path}/root').createSync();
    Link('${tmp.path}/root/link').createSync('../outside');
    final d = SafeDeleter(
      allowedRoots: ['${tmp.path}/root'],
      protectedPaths: [],
    );
    expect(
      await d.delete('${tmp.path}/root/link/victim'),
      DeleteOutcome.refused,
    );
    expect(victim.existsSync(), isTrue);
  });

  test('symlink de diretório pai que permanece dentro da raiz apaga', () async {
    final real = Directory('${tmp.path}/root/real')
      ..createSync(recursive: true);
    final f = File('${real.path}/f')..createSync();
    Link('${tmp.path}/root/alias').createSync(real.path);
    final d = SafeDeleter(
      allowedRoots: ['${tmp.path}/root'],
      protectedPaths: [],
    );
    expect(await d.delete('${tmp.path}/root/alias/f'), DeleteOutcome.deleted);
    expect(f.existsSync(), isFalse);
  });

  test('canRemove segue as mesmas regras do delete', () async {
    final f = File('${tmp.path}/home/b.txt')..createSync(recursive: true);
    expect(await deleter.canRemove(f.path), isTrue);
    expect(await deleter.canRemove('${tmp.path}/home'), isFalse);
    expect(await deleter.canRemove('/etc/passwd'), isFalse);
    expect(await deleter.canRemove('relativo.txt'), isFalse);
    expect(f.existsSync(), isTrue);
  });

  test('raiz de sistema mapeada é ignorada quando home é informado', () async {
    final d = SafeDeleter(
      home: '${tmp.path}/home',
      allowedRoots: ['${tmp.path}/home', '/usr', '/'],
      protectedPaths: [],
    );
    expect(await d.canRemove('/usr/share/doc'), isFalse);
    expect(await d.canRemove('/opt/x'), isFalse);
  });
}
