import 'dart:io';

import 'package:disk_cleanup/backup/restore_readme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

RestoreInfo _with({
  RestoredSecrets? secrets,
  List<RestoredBrowser> browsers = const [],
  GitTools gitTools = const GitTools(),
  String? device,
}) => RestoreInfo(
  date: DateTime(2026, 11, 9),
  destination: '/media/user/Disco externo',
  home: '/home/user',
  folderName: 'backup',
  sources: const ['/home/user/projetos', '/mnt/dados/docs'],
  ignoredBuilds: 123,
  backupBytes: 16255978431,
  secrets: secrets,
  browsers: browsers,
  gitTools: gitTools,
  device: device,
);

const _secrets = RestoredSecrets(
  fileName: 'secrets-2026-11-09.tar.gz.gpg',
  items: ['.ssh', '.gitconfig', '.gnupg', '.local/share/keyrings'],
);

const _chrome = RestoredBrowser(
  id: 'chrome',
  label: 'Google Chrome',
  profilePath: '/home/user/.config/google-chrome',
);

List<String> _headings(String md) => [
  for (final l in md.split('\n'))
    if (l.startsWith('## ')) l,
];

void main() {
  test('shellQuote', () {
    expect(shellQuote('backup/projetos'), 'backup/projetos');
    expect(shellQuote('Meus Cursos'), "'Meus Cursos'");
    expect(shellQuote("d'água"), r"'d'\''água'");
    expect(shellQuote(r'$HOME'), r"'$HOME'");
  });

  test('GitTools lê lfs e delta do .gitconfig', () {
    const text =
        '[filter "lfs"]\n\tprocess = git-lfs filter-process\n'
        '[core]\n\tpager = delta\n';
    final t = GitTools.fromGitconfig(text);
    expect(t.lfs, isTrue);
    expect(t.delta, isTrue);
    final none = GitTools.fromGitconfig('[user]\n\tname = Alguém\n');
    expect(none.lfs, isFalse);
    expect(none.delta, isFalse);
  });

  test('só pastas: sem seções de segredos e navegadores', () {
    final md = restoreReadme(_with());
    expect(_headings(md), [
      '## 1. Pacotes',
      '## 2. Projetos',
      '## 3. Antes de desconectar o disco',
    ]);
    expect(md, contains("DESTINO='/media/user/Disco externo'"));
    expect(md, contains('sudo apt install rsync git\n'));
    expect(md, contains('`projetos` e `docs` (16,3 GB)'));
    expect(
      md,
      contains(
        'rsync -aH --info=progress2 "\$DESTINO"/backup/projetos "\$HOME"/\n',
      ),
    );
    expect(
      md,
      contains(
        'rsync -aH --info=progress2 "\$DESTINO"/backup/docs /mnt/dados/\n',
      ),
    );
    expect(md, contains('nem 123 pastas de build'));
    expect(md, contains('```bash\nsync\n```'));
    expect(md, isNot(contains('gpg')));
    expect(md, contains('Gerado pelo disk-cleanup em 09/11/2026'));
  });

  test('completo: segredos, keyring antes dos navegadores, ferramentas', () {
    final md = restoreReadme(
      _with(
        secrets: _secrets,
        browsers: [_chrome],
        gitTools: const GitTools(lfs: true, delta: true),
        device: '/dev/sda1',
      ),
    );
    expect(_headings(md), [
      '## 1. Pacotes',
      '## 2. Chaves e configurações',
      '## 3. Projetos',
      '## 4. Navegadores',
      '## 5. Antes de desconectar o disco',
    ]);
    expect(md, contains('sudo apt install rsync git gnupg git-lfs\n'));
    expect(md, contains('dandavison/delta'));
    expect(
      md,
      contains(
        'cd ~ && gpg -d "\$DESTINO"/backup/secrets-2026-11-09.tar.gz.gpg | tar xzf -\n'
        'chmod 700 ~/.ssh\n',
      ),
    );
    expect(md, contains('rm -f ~/.gnupg/.#lk*'));
    expect(md, contains('gh auth login'));
    expect(md, contains('voltou no passo 2. Faça logout e login'));
    expect(
      md,
      contains(
        'rsync -aH "\$DESTINO"/backup/navegadores/chrome/ '
        '"\$HOME"/.config/google-chrome/\n',
      ),
    );
    expect(md, contains('sync && udisksctl unmount -b /dev/sda1'));
    expect(md, contains('| `backup/navegadores/` | Perfis de Google Chrome'));
  });

  test('navegadores sem keyring avisam que as senhas não voltam', () {
    final md = restoreReadme(
      _with(
        secrets: const RestoredSecrets(
          fileName: 'secrets-2026-11-09.tar.gz.gpg',
          items: ['.ssh'],
        ),
        browsers: [_chrome],
      ),
    );
    expect(md, contains('sem as senhas salvas'));
    expect(md, isNot(contains('voltou no passo')));
    expect(md, isNot(contains('chmod 700 ~/.gnupg')));
    expect(md, isNot(contains('gh auth login')));
  });

  test('os comandos gerados restauram caminhos com espaço e apóstrofo', () {
    final tmp = Directory.systemTemp.createTempSync('restore_readme_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final home = p.join(tmp.path, 'home');
    final dest = p.join(tmp.path, "Disco d'água");
    final source = p.join(home, 'Meus Projetos');
    File(p.join(dest, 'minha cópia', 'Meus Projetos', 'app', 'main.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}');
    Directory(home).createSync();

    final md = restoreReadme(
      RestoreInfo(
        date: DateTime(2026, 11, 9),
        destination: dest,
        home: home,
        folderName: 'minha cópia',
        sources: [source],
      ),
    );
    final commands = md
        .split('\n')
        .where((l) => l.startsWith('DESTINO=') || l.startsWith('rsync '))
        .join('\n');

    final r = Process.runSync(
      'bash',
      ['-c', commands],
      environment: {'HOME': home},
    );

    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(
      File(p.join(source, 'app', 'main.dart')).readAsStringSync(),
      'void main() {}',
    );
  });
}
