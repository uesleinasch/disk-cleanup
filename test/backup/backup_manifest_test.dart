import 'dart:io';

import 'package:disk_cleanup/backup/backup_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('manifesto-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('grava e lê o manifesto', () async {
    final manifest = BackupManifest(
      date: DateTime(2026, 11, 10, 8),
      hostname: 'maquina',
      home: '/home/ana',
      folderName: 'backup',
      sources: const [
        ManifestSource(path: '/home/ana/projetos', name: 'projetos'),
      ],
      browsers: const [
        ManifestBrowser(
          id: 'brave',
          label: 'Brave',
          profilePath: '/home/ana/.config/BraveSoftware/Brave-Browser',
        ),
      ],
    );
    await BackupManifest.write(tmp.path, manifest);

    final read = (await BackupManifest.load(tmp.path))!;
    expect(read.toJson(), manifest.toJson());
    expect(read.fromManifest, isTrue);
    expect(File(p.join(tmp.path, '$kManifestName.tmp')).existsSync(), isFalse);
  });

  test('sem manifesto, deduz as pastas pelo nome', () async {
    Directory(p.join(tmp.path, 'projetos')).createSync();
    Directory(p.join(tmp.path, 'fotos')).createSync();
    Directory(p.join(tmp.path, '.substituidos')).createSync();
    Directory(p.join(tmp.path, 'navegadores', 'chrome'))
        .createSync(recursive: true);

    final read = (await BackupManifest.load(
      tmp.path,
      knownSources: ['/home/ana/projetos'],
      home: '/home/ana',
    ))!;
    expect(read.fromManifest, isFalse);
    expect(
      [for (final s in read.sources) (s.name, s.path)],
      [('fotos', ''), ('projetos', '/home/ana/projetos')],
    );
    expect([for (final b in read.browsers) b.id], ['chrome']);
    expect(read.browsers.single.profilePath, startsWith('/home/ana/'));
  });

  test('pasta inexistente não tem manifesto', () async {
    expect(await BackupManifest.load(p.join(tmp.path, 'nada')), isNull);
  });

  test('lista os pacotes de segredos do mais recente ao mais antigo', () {
    for (final n in [
      'secrets-2026-11-01.tar.gz.gpg',
      'secrets-2026-11-09.tar.gz.gpg',
      '.secrets-2026-11-10.tar.gz.gpg.parcial',
      'LEIA-ME-RESTAURAR.md',
    ]) {
      File(p.join(tmp.path, n)).writeAsStringSync('x');
    }
    expect(listSecretsFiles(tmp.path), [
      'secrets-2026-11-09.tar.gz.gpg',
      'secrets-2026-11-01.tar.gz.gpg',
    ]);
  });
}
