import 'package:path/path.dart' as p;

import '../core/format.dart';
import 'backup_planner.dart';
import 'browser_profiles.dart';

const kRestoreReadmeName = 'LEIA-ME-RESTAURAR.md';

final _safe = RegExp(r'^[A-Za-z0-9_./=+:@,-]+$');

String shellQuote(String s) =>
    _safe.hasMatch(s) ? s : "'${s.replaceAll("'", r"'\''")}'";

class RestoredSecrets {
  const RestoredSecrets({required this.fileName, required this.items});

  final String fileName;
  final List<String> items;

  bool get hasKeyring => items.any(
    (i) =>
        i == '.local/share/keyrings' || p.isWithin(i, '.local/share/keyrings'),
  );
}

class RestoredBrowser {
  const RestoredBrowser({
    required this.id,
    required this.label,
    required this.profilePath,
  });

  final String id;
  final String label;
  final String profilePath;
}

class GitTools {
  const GitTools({this.lfs = false, this.delta = false});

  factory GitTools.fromGitconfig(String text) => GitTools(
    lfs: RegExp(r'^\s*\[filter\s+"lfs"\]', multiLine: true).hasMatch(text),
    delta: RegExp(r'=\s*delta\b', multiLine: true).hasMatch(text),
  );

  final bool lfs;
  final bool delta;
}

class RestoreInfo {
  const RestoreInfo({
    required this.date,
    required this.destination,
    required this.home,
    required this.folderName,
    required this.sources,
    this.ignoredBuilds = 0,
    this.backupBytes,
    this.secrets,
    this.browsers = const [],
    this.gitTools = const GitTools(),
    this.device,
  });

  final DateTime date;
  final String destination;
  final String home;
  final String folderName;
  final List<String> sources;
  final int ignoredBuilds;
  final int? backupBytes;
  final RestoredSecrets? secrets;
  final List<RestoredBrowser> browsers;
  final GitTools gitTools;
  final String? device;
}

String _joinPt(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';

String restoreReadme(RestoreInfo info) {
  final out = StringBuffer();
  var section = 0;
  void heading(String title) => out
    ..writeln()
    ..writeln('## ${++section}. $title')
    ..writeln();
  void code(List<String> lines) => out
    ..writeln('```bash')
    ..writeAll(lines.map((l) => '$l\n'))
    ..writeln('```');

  String inBackup(String rel) =>
      '"\$DESTINO"/${shellQuote(p.join(info.folderName, rel))}';
  String local(String path) {
    if (path == info.home) return '"\$HOME"';
    if (p.isWithin(info.home, path)) {
      return '"\$HOME"/${shellQuote(p.relative(path, from: info.home))}';
    }
    return shellQuote(path);
  }

  final secrets = info.secrets;
  final secretsFile = secrets == null
      ? null
      : '"\$DESTINO"/${shellQuote(secrets.fileName)}';
  final day =
      '${info.date.day.toString().padLeft(2, '0')}/'
      '${info.date.month.toString().padLeft(2, '0')}/${info.date.year}';

  out
    ..writeln('# Restauração do backup')
    ..writeln()
    ..writeln(
      'Gerado pelo disk-cleanup em $day. '
      'Este arquivo é reescrito a cada backup.',
    )
    ..writeln()
    ..writeln(
      'Com o disk-cleanup instalado, o jeito mais simples é a aba '
      '**Backup > Restaurar**: ela mostra o que já existe no computador '
      'antes de copiar. Os passos abaixo fazem o mesmo à mão.',
    )
    ..writeln()
    ..writeln('| Item | O que é |')
    ..writeln('| --- | --- |');
  final names = _joinPt([for (final s in info.sources) '`${p.basename(s)}`']);
  final size = info.backupBytes == null
      ? ''
      : ' (${formatBytes(info.backupBytes!)})';
  out.writeln(
    '| `${info.folderName}/` | Cópia de $names$size, sem dependências, '
    'caches e builds ignorados pelo git |',
  );
  if (info.browsers.isNotEmpty) {
    out.writeln(
      '| `${info.folderName}/$kBrowserFolder/` | Perfis de '
      '${_joinPt([for (final b in info.browsers) b.label])}, sem cache |',
    );
  }
  if (secrets != null) {
    out.writeln(
      '| `${secrets.fileName}` | '
      '${secrets.items.map((i) => '`$i`').join(', ')} '
      '(criptografado com AES256; sem a senha não abre) |',
    );
  }

  out
    ..writeln()
    ..writeln(
      'Abra um terminal e defina onde o disco está montado. '
      'Em outra máquina o caminho muda: ajuste antes de seguir.',
    )
    ..writeln();
  code(['DESTINO=${shellQuote(info.destination)}']);

  heading('Pacotes');
  final packages = [
    'rsync',
    'git',
    if (secrets != null) 'gnupg',
    if (info.gitTools.lfs) 'git-lfs',
  ];
  code(['sudo apt install ${packages.join(' ')}']);
  if (info.gitTools.delta) {
    out
      ..writeln()
      ..writeln(
        'O `.gitconfig` usa o `delta` como pager; sem ele o `git diff` e o '
        '`git log` falham. Instale pelo pacote `.deb` em '
        'https://github.com/dandavison/delta/releases.',
      );
  }

  int? keysSection;
  if (secrets != null) {
    heading('Chaves e configurações');
    keysSection = section;
    out
      ..writeln('O `gpg` abre uma janela pedindo a senha definida no backup.')
      ..writeln();
    code([
      'cd ~ && gpg -d $secretsFile | tar xzf -',
      if (secrets.items.contains('.ssh')) ...[
        'chmod 700 ~/.ssh',
        'chmod 600 ~/.ssh/*',
        'chmod 644 ~/.ssh/*.pub',
      ],
      if (secrets.items.contains('.gnupg')) ...[
        'chmod 700 ~/.gnupg',
        'rm -f ~/.gnupg/.#lk*',
      ],
    ]);
    out
      ..writeln()
      ..writeln('Para só conferir o conteúdo, sem extrair:')
      ..writeln();
    code(['gpg -d $secretsFile | tar tzf -']);
    if (secrets.items.any((i) => i.startsWith('.gitconfig'))) {
      out
        ..writeln()
        ..writeln(
          'Se o nome de usuário mudar, ajuste os caminhos absolutos do '
          '`.gitconfig` (por exemplo, `core.excludesfile`). '
          'Logins de ferramentas como o `gh` não estão no backup: '
          'rode `gh auth login` de novo.',
        );
    }
  }

  heading('Projetos');
  out
    ..writeln('Cada pasta volta para onde estava:')
    ..writeln();
  code([
    for (final s in info.sources)
      'rsync -aH --info=progress2 ${inBackup(p.basename(s))} '
          '${local(p.dirname(s))}/',
  ]);
  out
    ..writeln()
    ..writeln(
      'Não foram copiadas as pastas ${kBackupAlwaysExcluded.map((n) => '`$n`').join(', ')}'
      '${info.ignoredBuilds > 0 ? ', nem ${info.ignoredBuilds} pastas de build ignoradas pelo git (`dist`, `build`, `bin`, `target`, `out`)' : ''}. '
      'Reinstale as dependências em cada projeto '
      '(`npm install`, `dotnet restore`, `python -m venv .venv`, `stack build` etc.).',
    );

  if (info.browsers.isNotEmpty) {
    heading('Navegadores');
    if (secrets != null && secrets.hasKeyring) {
      out.writeln(
        'Senhas e cookies dependem do keyring do sistema, que voltou no '
        'passo $keysSection. Faça logout e login **antes** de abrir os '
        'navegadores. Se o keyring pedir senha, é a senha de login da '
        'época do backup.',
      );
    } else {
      out.writeln(
        'O keyring do sistema não está neste backup: os perfis voltam, '
        'mas sem as senhas salvas.',
      );
    }
    out
      ..writeln()
      ..writeln(
        'Instale cada navegador, abra e feche uma vez, '
        'confira que ele está fechado e copie o perfil de volta:',
      )
      ..writeln();
    code([
      for (final b in info.browsers)
        'rsync -aH ${inBackup('$kBrowserFolder/${b.id}')}/ '
            '${local(b.profilePath)}/',
    ]);
  }

  heading('Antes de desconectar o disco');
  code([
    if (info.device == null)
      'sync'
    else
      'sync && udisksctl unmount -b ${shellQuote(info.device!)}',
  ]);
  return out.toString();
}
