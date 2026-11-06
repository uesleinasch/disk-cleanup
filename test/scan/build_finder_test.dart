import 'dart:io';

import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/scan/build_finder.dart';
import 'package:disk_cleanup/scan/du_scanner.dart';
import 'package:disk_cleanup/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late BuildFinder finder;

  void file(String rel, [String content = 'x']) {
    final f = File('${root.path}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  void touch(String rel, DateTime time) {
    final stamp = time.toIso8601String();
    final r = Process.runSync('touch', ['-d', stamp, '${root.path}/$rel']);
    expect(r.exitCode, 0);
  }

  Future<List<BuildArtifact>> find({List<String> exclude = const []}) =>
      finder.find([root.path], kDefaultBuildRules, excludeRoots: exclude);

  setUp(() {
    root = Directory.systemTemp.createTempSync('build_finder_');
    final runner = SystemProcessRunner();
    finder = BuildFinder(runner, DuScanner(runner));
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('detecta node_modules com package.json ao lado', () async {
    file('proj/package.json');
    file('proj/node_modules/a.js');
    final result = await find();
    expect(result, hasLength(1));
    expect(result.single.path, '${root.path}/proj/node_modules');
    expect(result.single.projectDir, '${root.path}/proj');
    expect(result.single.rule, const BuildRule('node_modules', 'package.json'));
    expect(result.single.bytes, greaterThan(0));
  });

  test('ignora node_modules sem marcador', () async {
    file('solto/node_modules/a.js');
    expect(await find(), isEmpty);
  });

  test('não lista node_modules aninhado separadamente', () async {
    file('proj/package.json');
    file('proj/node_modules/dep/package.json');
    file('proj/node_modules/dep/node_modules/b.js');
    final result = await find();
    expect(result.map((a) => a.path), ['${root.path}/proj/node_modules']);
  });

  test('build com pubspec.yaml é detectado e sem marcador não', () async {
    file('app/pubspec.yaml');
    file('app/build/o.bin');
    file('foo/build/o.bin');
    final result = await find();
    expect(result.map((a) => a.path), ['${root.path}/app/build']);
  });

  test('bin com glob *.csproj é detectado', () async {
    file('api/Api.csproj');
    file('api/bin/Api.dll');
    final result = await find();
    expect(result.map((a) => a.path), ['${root.path}/api/bin']);
    expect(result.single.rule, const BuildRule('bin', '*.csproj'));
  });

  test('symlink chamado node_modules não é detectado', () async {
    file('proj/package.json');
    final target = Directory('${root.path}/alvo')..createSync();
    File('${target.path}/a.js').writeAsStringSync('x');
    Link('${root.path}/proj/node_modules').createSync(target.path);
    expect(await find(), isEmpty);
  });

  test('ignora caminhos dentro de excludeRoots', () async {
    file('trash/proj/package.json');
    file('trash/proj/node_modules/a.js');
    file('ok/package.json');
    file('ok/node_modules/a.js');
    final result = await find(exclude: ['${root.path}/trash']);
    expect(result.map((a) => a.path), ['${root.path}/ok/node_modules']);
  });

  test(
    'projectModified é o maior mtime dos filhos sem pastas de build',
    () async {
      file('proj/package.json');
      file('proj/src/main.js');
      file('proj/node_modules/a.js');
      final old = DateTime(2024, 1, 1);
      final mid = DateTime(2024, 6, 1);
      final recent = DateTime(2025, 3, 1);
      touch('proj/package.json', old);
      touch('proj/src/main.js', old);
      touch('proj/src', mid);
      touch('proj/node_modules', recent);
      final result = await find();
      expect(result.single.projectModified, mid);
    },
  );

  test('exclude com barra final ainda é podado', () async {
    file('trash/proj/package.json');
    file('trash/proj/node_modules/a.js');
    final result = await find(exclude: ['${root.path}/trash/']);
    expect(result, isEmpty);
  });

  test('exclude com espaço e colchetes é literal', () async {
    file('Dispatch [BASE]/proj/package.json');
    file('Dispatch [BASE]/proj/node_modules/a.js');
    file('Dispatch B/proj/package.json');
    file('Dispatch B/proj/node_modules/a.js');
    final result = await find(exclude: ['${root.path}/Dispatch [BASE]']);
    expect(result.map((a) => a.path), [
      '${root.path}/Dispatch B/proj/node_modules',
    ]);
  });

  test('raízes sobrepostas não duplicam artefatos', () async {
    file('projects/proj/package.json');
    file('projects/proj/node_modules/a.js');
    final result = await finder.find([
      root.path,
      '${root.path}/projects',
    ], kDefaultBuildRules);
    expect(result, hasLength(1));
  });
}
