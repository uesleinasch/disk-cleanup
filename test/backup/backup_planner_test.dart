import 'dart:io';

import 'package:disk_cleanup/backup/backup_planner.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/settings/backup_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_process_runner.dart';

void main() {
  late Directory tmp;
  late BackupPlanner planner;

  String path(String rel) => p.join(tmp.path, rel);

  void file(String rel, [String content = 'x']) {
    File(path(rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  void git(String repoRel, List<String> args) {
    final r = Process.runSync('git', ['-C', path(repoRel), ...args]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  Future<Set<String>> copy(BackupFilter filter, {bool dryRun = false}) async {
    final rules = File(path('rules.bin'));
    await filter.writeTo(rules);
    final dest = path('dest');
    Directory(dest).createSync(recursive: true);
    final r = Process.runSync('rsync', [
      ...backupRsyncArgs(
        filterFile: rules.path,
        sources: filter.sources,
        destination: dest,
        dryRun: dryRun,
      ),
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return {
      for (final e in Directory(dest).listSync(recursive: true))
        if (e is File) p.relative(e.path, from: dest),
    };
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_planner_');
    planner = BackupPlanner(SystemProcessRunner());
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('findIgnoredBuilds', () {
    test('exclui só builds ignorados e sem arquivo versionado', () async {
      file('src/app/.gitignore', 'dist/\nbin/\n');
      file('src/app/dist/bundle.js');
      file('src/app/build/keep.txt');
      file('src/app/vendor/bin/tool');
      file('src/app/wwwroot/lib/bin/sub/jquery.js');
      file('src/app/wwwroot/lib/bin/solto.js');
      file('src/app/packages/lib/bin/cli.dart');
      file('src/solto/dist/a.js');
      git('src/app', ['init', '-q']);
      git('src/app', [
        'add',
        '-f',
        'vendor/bin/tool',
        'wwwroot/lib/bin/sub/jquery.js',
      ]);

      final ignored = await planner.findIgnoredBuilds([path('src')]);

      expect(ignored, [path('src/app/dist'), path('src/app/packages/lib/bin')]);
    });

    test('não desce em pastas sempre excluídas nem em .git', () async {
      file('src/app/.gitignore', 'dist/\n');
      file('src/app/node_modules/pkg/dist/a.js');
      git('src/app', ['init', '-q']);
      Directory(path('src/app/.git/dist')).createSync();

      expect(await planner.findIgnoredBuilds([path('src')]), isEmpty);
    });

    test('usa o repositório mais próximo (submódulo, repo aninhado)', () async {
      file('src/mono/.gitignore', 'out/\n');
      file('src/mono/sub/.gitignore', '');
      file('src/mono/sub/out/a.txt');
      file('src/mono/out/b.txt');
      git('src/mono', ['init', '-q']);
      git('src/mono/sub', ['init', '-q']);

      expect(await planner.findIgnoredBuilds([path('src')]), [
        path('src/mono/out'),
      ]);
    });

    test('git ausente ou com erro mantém as pastas no backup', () async {
      final fake = FakeProcessRunner()
        ..when('find', [
          '/src',
          '-type',
          'd',
          '(',
          for (final (i, n) in [...kBackupAlwaysExcluded, '.git'].indexed) ...[
            if (i > 0) '-o',
            '-name',
            n,
          ],
          ')',
          '-prune',
          '-o',
          '-type',
          'd',
          '(',
          for (final (i, n) in kBackupBuildDirs.indexed) ...[
            if (i > 0) '-o',
            '-name',
            n,
          ],
          ')',
          '-prune',
          '-print0',
        ], RunResult(0, '${path('repo/dist')}\x00'.codeUnits, ''))
        ..when('git', [
          '-c',
          'core.quotePath=false',
          '-C',
          path('repo'),
          'check-ignore',
          '--',
          'dist/',
        ], const RunResult(127, [], 'git: not found'));
      Directory(path('repo/.git')).createSync(recursive: true);

      expect(await BackupPlanner(fake).findIgnoredBuilds(['/src']), isEmpty);
    });
  });

  group('BackupFilter + rsync', () {
    test('lista fixa vale em qualquer profundidade', () async {
      file('src/a/node_modules/x.js');
      file('src/a/deep/er/.venv/bin/python');
      file('src/a/coverage/lcov.info');
      file('src/a/main.dart');
      file('src/a/.env');

      final copied = await copy(BackupFilter(sources: [path('src')]));

      expect(copied, {'src/a/main.dart', 'src/a/.env'});
    });

    test('builds ignorados saem, versionados ficam', () async {
      file('src/app/.gitignore', 'dist/\nbin/\n');
      file('src/app/dist/bundle.js');
      file('src/app/vendor/bin/tool');
      file('src/app/index.js');
      git('src/app', ['init', '-q']);
      git('src/app', ['add', '-f', 'vendor/bin/tool']);

      final filter = await planner.plan([path('src')]);
      final copied = await copy(filter);

      expect(copied.where((f) => !f.startsWith('src/app/.git/')).toSet(), {
        'src/app/.gitignore',
        'src/app/vendor/bin/tool',
        'src/app/index.js',
      });
      expect(copied, contains('src/app/.git/HEAD'));
    });

    test('âncoras funcionam com origens de pais diferentes', () async {
      file('casa/projetos/app/dist/a.js');
      file('casa/projetos/app/ok.txt');
      file('mnt/dados/docs/dist/b.js');
      file('mnt/dados/docs/ok.txt');

      final filter = BackupFilter(
        sources: [path('casa/projetos'), path('mnt/dados/docs')],
        ignoredBuilds: [
          path('casa/projetos/app/dist'),
          path('mnt/dados/docs/dist'),
        ],
      );

      expect(await copy(filter), {'projetos/app/ok.txt', 'docs/ok.txt'});
    });

    test('caminhos com curingas, espaços e barra invertida', () async {
      file('src/Meus Cursos [2024]/dist/a.js');
      file('src/Meus Cursos [2024]/aula.txt');
      file('src/x*y?/dist/b.js');
      file('src/x*y?/ok.txt');
      file(r'src/a\b/dist/c.js');
      file(r'src/a\b/ok.txt');

      final filter = BackupFilter(
        sources: [path('src')],
        ignoredBuilds: [
          path('src/Meus Cursos [2024]/dist'),
          path('src/x*y?/dist'),
          path(r'src/a\b/dist'),
        ],
      );

      expect(await copy(filter), {
        'src/Meus Cursos [2024]/aula.txt',
        'src/x*y?/ok.txt',
        r'src/a\b/ok.txt',
      });
    });

    test('caminhos protegidos dentro da origem não são copiados', () async {
      file('home/.ssh/id_ed25519');
      file('home/.gitconfig');
      file('home/.config/google-chrome/Default/History');
      file('home/notas.txt');

      final filter = BackupFilter(
        sources: [path('home')],
        protectedPaths: [
          path('home/.ssh'),
          path('home/.gitconfig'),
          path('home/.config/google-chrome'),
          path('fora/.ssh'),
        ],
      );

      expect(await copy(filter), {'home/notas.txt'});
    });
  });

  group('inclusões', () {
    test('tipo incluído volta em qualquer nível só naquela origem', () async {
      file('src/node_modules/raiz.js');
      file('src/a/node_modules/x/node_modules/y.js');
      file('src/a/node_modules/x/.cache/z');
      file('src/a/.venv/bin/python');
      file('outra/node_modules/w.js');
      file('outra/ok.txt');

      final filter = BackupFilter(
        sources: [path('src'), path('outra')],
        included: {
          path('src'): const SourceInclusions(kinds: {'node_modules'}),
        },
      );

      expect(await copy(filter), {
        'src/node_modules/raiz.js',
        'src/a/node_modules/x/node_modules/y.js',
        'src/a/node_modules/x/.cache/z',
        'outra/ok.txt',
      });
    });

    test('caminho incluído volta sozinho, com curingas no nome', () async {
      file('src/a [1]/node_modules/x.js');
      file('src/b/node_modules/y.js');

      final filter = BackupFilter(
        sources: [path('src')],
        included: {
          path('src'): const SourceInclusions(paths: {'a [1]/node_modules'}),
        },
      );

      expect(await copy(filter), {'src/a [1]/node_modules/x.js'});
    });

    test('builds incluídos por tipo ou caminho saem das regras', () async {
      file('src/app/dist/a.js');
      file('src/app/build/b.js');
      file('src/web/dist/c.js');

      final filter = BackupFilter(
        sources: [path('src')],
        ignoredBuilds: [
          path('src/app/build'),
          path('src/app/dist'),
          path('src/web/dist'),
        ],
        included: {
          path('src'): const SourceInclusions(
            kinds: {'build'},
            paths: {'web/dist'},
          ),
        },
      );

      expect(filter.keptBuilds, [path('src/app/dist')]);
      expect(await copy(filter), {'src/app/build/b.js', 'src/web/dist/c.js'});
    });

    test('protegidos continuam fora mesmo dentro de algo incluído', () async {
      file('home/.cache/app/x');
      file('home/.cache/segredo/chave');

      final filter = BackupFilter(
        sources: [path('home')],
        protectedPaths: [path('home/.cache/segredo')],
        included: {
          path('home'): const SourceInclusions(kinds: {'.cache'}),
        },
      );

      expect(await copy(filter), {'home/.cache/app/x'});
    });
  });

  group('scanExclusions', () {
    test(
      'lista o que fica fora, com tamanho, sem descer nem ver .git',
      () async {
        file('src/app/.gitignore', 'dist/\n');
        file('src/app/dist/a.js', '12345');
        file('src/app/build/versionado.txt');
        file('src/app/node_modules/pkg/dist/x.js');
        file('src/web/.venv/bin/python');
        git('src/app', ['init', '-q']);
        git('src/app', ['add', '-f', 'build/versionado.txt']);
        Directory(path('src/app/.git/node_modules')).createSync();

        final found = await planner.scanExclusions(path('src'));

        expect(
          [for (final d in found) (d.path, d.kind)],
          [
            (path('src/app/dist'), 'dist'),
            (path('src/app/node_modules'), 'node_modules'),
            (path('src/web/.venv'), '.venv'),
          ],
        );
        expect(found.every((d) => d.bytes != null && d.bytes! > 0), isTrue);
      },
    );
  });

  group('estimate', () {
    test('mede o total e o que falta copiar', () async {
      file('src/a.bin', 'x' * 1000);
      file('src/node_modules/b.bin', 'y' * 5000);
      file('docs/c.txt', 'z' * 200);
      final filter = BackupFilter(sources: [path('src'), path('docs')]);
      final rules = File(path('rules.bin'));
      await filter.writeTo(rules);
      final dest = path('dest');
      Directory(dest).createSync();

      Future<BackupEstimate> estimate() => planner.estimate(
        filterFile: rules.path,
        sources: filter.sources,
        destination: dest,
      );

      final before = await estimate();
      expect(before.totalBytes, 1200);
      expect(before.transferBytes, 1200);
      expect(before.files, 2);
      expect(before.bySource[path('src')]!.totalBytes, 1000);
      expect(before.bySource[path('docs')]!.totalBytes, 200);
      expect(Directory(dest).listSync(), isEmpty);

      await copy(filter);
      final after = await estimate();
      expect(after.totalBytes, 1200);
      expect(after.transferBytes, 0);
    });

    test('rsync ausente vira BackupException', () async {
      final fake = FakeProcessRunner()
        ..whenStreaming(
          'rsync',
          backupRsyncArgs(
            filterFile: '/f',
            sources: ['/src'],
            destination: '/dest',
            dryRun: true,
          ),
          result: const RunResult(127, [], ''),
        );
      await expectLater(
        BackupPlanner(
          fake,
        ).estimate(filterFile: '/f', sources: ['/src'], destination: '/dest'),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('não está instalado'),
          ),
        ),
      );
      expect(fake.environments.single, {'LC_ALL': 'C'});
    });
  });

  test('RsyncStats lê o --stats em locale C', () {
    final stats = RsyncStats.parse([
      'Number of files: 204,512 (reg: 190,001, dir: 14,500, link: 11)',
      'Number of created files: 3 (reg: 3)',
      'Number of deleted files: 0',
      'Number of regular files transferred: 1,234',
      'Total file size: 16,252,823,167 bytes',
      'Total transferred file size: 1,200,000 bytes',
      'Literal data: 0 bytes',
    ])!;
    expect(stats.files, 190001);
    expect(stats.transferredFiles, 1234);
    expect(stats.totalBytes, 16252823167);
    expect(stats.transferredBytes, 1200000);
    expect(RsyncStats.parse(['Number of files: 0']), isNull);
  });

  test('backupRsyncArgs normaliza caminhos e liga espelhar', () {
    expect(
      backupRsyncArgs(
        filterFile: '/tmp/f',
        sources: ['/home/u/projetos/'],
        destination: '/media/u/Disco/backup/',
        mirror: true,
      ),
      [
        '-aH',
        '--info=progress2',
        '--no-inc-recursive',
        '--stats',
        '--delete',
        '--from0',
        '--exclude-from=/tmp/f',
        '/home/u/projetos',
        '/media/u/Disco/backup/',
      ],
    );
  });
}
