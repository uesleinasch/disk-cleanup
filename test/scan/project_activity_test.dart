import 'dart:io';

import 'package:disk_cleanup/scan/project_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void setOld(String path, DateTime when) {
  final r = Process.runSync('touch', [
    '-h',
    '-d',
    '@${when.millisecondsSinceEpoch ~/ 1000}',
    path,
  ]);
  if (r.exitCode != 0) throw StateError('touch falhou: ${r.stderr}');
}

void main() {
  late Directory tmp;
  late String proj;
  final old = DateTime(2020, 1, 1);
  final recent = DateTime(2026, 11, 1);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dc_activity_');
    proj = p.join(tmp.path, 'proj');
    for (final f in [
      'package.json',
      'src/deep/a/main.ts',
      'node_modules/lib/index.js',
      'dist/out.js',
    ]) {
      File(p.join(proj, f)).createSync(recursive: true);
    }
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void ageAll() {
    final all = [
      for (final e in Directory(proj).listSync(recursive: true)) e.path,
      proj,
    ]..sort((a, b) => b.length.compareTo(a.length));
    for (final path in all) {
      setOld(path, old);
    }
  }

  test('edição aninhada conta como atividade', () {
    ageAll();
    setOld(p.join(proj, 'src', 'deep', 'a', 'main.ts'), recent);
    expect(newestProjectModification(proj, mountPoints: const {}), recent);
  });

  test('pastas de build e dependências não contam', () {
    ageAll();
    setOld(p.join(proj, 'node_modules', 'lib', 'index.js'), recent);
    setOld(p.join(proj, 'node_modules'), recent);
    setOld(p.join(proj, 'dist', 'out.js'), recent);
    expect(newestProjectModification(proj, mountPoints: const {}), old);
  });

  test('.git/index recente conta como atividade', () {
    File(p.join(proj, '.git', 'index')).createSync(recursive: true);
    ageAll();
    setOld(p.join(proj, '.git', 'index'), recent);
    expect(newestProjectModification(proj, mountPoints: const {}), recent);
  });

  test('não desce em ponto de montagem', () {
    ageAll();
    setOld(p.join(proj, 'src', 'deep', 'a', 'main.ts'), recent);
    expect(
      newestProjectModification(
        proj,
        mountPoints: {p.join(proj, 'src', 'deep')},
      ),
      old,
    );
  });

  test('diretório inexistente devolve null', () {
    expect(newestProjectModification(p.join(tmp.path, 'nada')), isNull);
  });
}
