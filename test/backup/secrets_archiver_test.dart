import 'dart:convert';
import 'dart:io';

import 'package:disk_cleanup/backup/secrets_archiver.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_process_runner.dart';

const _gitArgs = [
  'config',
  '--global',
  '--get-regexp',
  r'^(includeif\..*\.path|core\.excludesfile)$',
];

const _pinentry = r'''#!/bin/sh
dir=$(dirname "$0")
echo "OK pinentry de teste"
repeat=0
while IFS= read -r line; do
  case "$line" in
    SETREPEAT*) repeat=1; echo OK ;;
    GETPIN*)
      if [ "$(cat "$dir/modo")" = cancelar ]; then
        echo "ERR 83886179 Operation cancelled <Pinentry>"
      else
        [ "$repeat" = 1 ] && echo "S PIN_REPEATED"
        echo "D $(cat "$dir/senha")"
        echo OK
      fi ;;
    BYE*) echo OK; exit 0 ;;
    *) echo OK ;;
  esac
done
''';

void main() {
  late Directory tmp;
  late String home;

  String path(String rel) => p.join(tmp.path, rel);

  void file(String rel, [String content = 'x']) {
    File(p.join(home, rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('secrets_');
    home = path('home');
    Directory(home).createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('secretsFileName', () {
    expect(
      secretsFileName(DateTime(2026, 3, 7)),
      'secrets-2026-03-07.tar.gz.gpg',
    );
  });

  group('detect', () {
    test('só o que existe, com .gitconfig-* e arquivos citados no git', () async {
      file('.ssh/id_ed25519');
      file('.gitconfig');
      file('.gitconfig-trabalho');
      file('.gitconfig.bak');
      file('.config/git/ignore');
      file('.local/share/keyrings/login.keyring');
      file('.gitignore_empresa');
      file('.config/git/trabalho.inc');
      final fake = FakeProcessRunner()
        ..when(
          'git',
          _gitArgs,
          RunResult(
            0,
            utf8.encode(
              'includeif.gitdir:~/trabalho/.path ~/.gitconfig-trabalho\n'
              'includeif.gitdir:~/outro/.path ${p.join(home, '.config/git/trabalho.inc')}\n'
              'includeif.onbranch:x.path /etc/fora-do-home\n'
              'includeif.gitdir:~/z/.path ~/nao-existe\n'
              'core.excludesfile ~/.gitignore_empresa\n',
            ),
            '',
          ),
        );

      final items = await SecretsArchiver(home: home, runner: fake).detect();

      expect(items, [
        '.ssh',
        '.gitconfig',
        '.config/git',
        '.local/share/keyrings',
        '.gitconfig-trabalho',
        '.gitignore_empresa',
      ]);
    });

    test('git sem configuração global não atrapalha', () async {
      file('.ssh/config');
      final fake = FakeProcessRunner()
        ..when('git', _gitArgs, const RunResult(1, [], ''));
      expect(await SecretsArchiver(home: home, runner: fake).detect(), [
        '.ssh',
      ]);
    });
  });

  test('relativeToHome aceita só caminhos dentro do home', () {
    final s = SecretsArchiver(home: '/home/user', runner: FakeProcessRunner());
    expect(s.relativeToHome('/home/user/chave.pem'), 'chave.pem');
    expect(s.relativeToHome('/home/user/a/../b.pem'), 'b.pem');
    expect(s.relativeToHome('/home/user'), isNull);
    expect(s.relativeToHome('/etc/ssl/chave.pem'), isNull);
    expect(s.relativeToHome('/home/userx/chave.pem'), isNull);
  });

  group('archive com runner simulado', () {
    final date = DateTime(2026, 11, 9);

    Future<SecretsResult> archive(RunResult tar, RunResult gpg) {
      final dest = path('destino');
      Directory(dest).createSync(recursive: true);
      final partial = p.join(dest, '.secrets-2026-11-09.tar.gz.gpg.parcial');
      File(partial).writeAsStringSync('cifrado');
      final fake = FakeProcessRunner()
        ..whenPiped(
          Command('tar', [
            'czf',
            '-',
            '-C',
            home,
            '--exclude=.gnupg/S.*',
            '--exclude=.gnupg/*.lock',
            '--exclude=.gnupg/.#lk*',
            '--',
            '.ssh',
          ]),
          Command('gpg', [
            '--yes',
            '--pinentry-mode',
            'ask',
            '--symmetric',
            '--cipher-algo',
            'AES256',
            '--no-symkey-cache',
            '--output',
            partial,
          ]),
          tar,
          gpg,
        );
      return SecretsArchiver(
        home: home,
        runner: fake,
      ).archive(items: ['.ssh'], destination: dest, date: date);
    }

    bool partialExists() =>
        File(path('destino/.secrets-2026-11-09.tar.gz.gpg.parcial'))
            .existsSync();

    test('sucesso renomeia o parcial', () async {
      final r = await archive(
        const RunResult(0, [], ''),
        const RunResult(0, [], ''),
      );
      expect(r.outcome, SecretsOutcome.ok);
      expect(r.path, path('destino/secrets-2026-11-09.tar.gz.gpg'));
      expect(r.bytes, 7);
      expect(partialExists(), isFalse);
    });

    test('tar com arquivo alterado durante a leitura vira aviso', () async {
      final r = await archive(
        const RunResult(1, [], 'tar: .gnupg/x: file changed as we read it\n'),
        const RunResult(0, [], ''),
      );
      expect(r.outcome, SecretsOutcome.warnings);
      expect(r.warnings, ['tar: .gnupg/x: file changed as we read it']);
    });

    final failures = {
      'janela fechada': (
        const RunResult(143, [], ''),
        const RunResult(
          2,
          [],
          'gpg: problem with the agent: Operation cancelled\n'
          'gpg: symmetric encryption of \'[stdin]\' failed: Operation cancelled\n',
        ),
        SecretsOutcome.cancelled,
        'janela de senha foi fechada',
      ),
      'sem pinentry gráfico': (
        const RunResult(143, [], ''),
        const RunResult(
          2,
          [],
          'gpg: problem with the agent: Inappropriate ioctl for device\n',
        ),
        SecretsOutcome.failed,
        'pinentry-gnome3',
      ),
      'agent sem pinentry': (
        const RunResult(143, [], ''),
        const RunResult(2, [], 'gpg: problem with the agent: No pinentry\n'),
        SecretsOutcome.failed,
        'pinentry-gnome3',
      ),
      'gpg ausente': (
        notStarted,
        const RunResult(127, [], ''),
        SecretsOutcome.failed,
        'pacote gnupg',
      ),
      'tar não leu tudo': (
        const RunResult(
          2,
          [],
          'tar: .ssh/id: Cannot open: Permission denied\n'
          'tar: Exiting with failure status due to previous errors\n',
        ),
        const RunResult(0, [], ''),
        SecretsOutcome.failed,
        'previous errors',
      ),
    };

    for (final MapEntry(key: name, value: (tar, gpg, outcome, text))
        in failures.entries) {
      test('$name apaga o parcial', () async {
        final r = await archive(tar, gpg);
        expect(r.outcome, outcome);
        expect(r.message, contains(text));
        expect(r.path, isNull);
        expect(partialExists(), isFalse);
      });
    }
  });

  group('gpg real com pinentry de teste', () {
    late Map<String, String> env;

    setUp(() {
      final gnupg = Directory(path('gnupg'))..createSync();
      Process.runSync('chmod', ['700', gnupg.path]);
      final script = File(path('pinentry/pinentry.sh'))
        ..parent.createSync()
        ..writeAsStringSync(_pinentry);
      Process.runSync('chmod', ['755', script.path]);
      File(path('pinentry/senha')).writeAsStringSync('senha de teste');
      File(path('pinentry/modo')).writeAsStringSync('responder');
      File(p.join(gnupg.path, 'gpg-agent.conf'))
          .writeAsStringSync('pinentry-program ${script.path}\n');
      env = {'GNUPGHOME': gnupg.path};
      addTearDown(
        () => Process.runSync('gpgconf', [
          '--kill',
          'gpg-agent',
        ], environment: env),
      );

      file('.ssh/id_ed25519', 'chave privada');
      file('.ssh/config', 'Host x');
      file('.gnupg/S.gpg-agent', 'socket');
      file('.gnupg/pubring.kbx', 'chaves');
      file('.gnupg/.#lk0x1234', 'trava');
      Directory(path('destino')).createSync();
    });

    SecretsArchiver archiver() => SecretsArchiver(
      home: home,
      runner: SystemProcessRunner(),
      environment: env,
    );

    List<String> decrypt(String file) {
      final tarball = path('aberto.tar.gz');
      final r = Process.runSync('gpg', [
        '--pinentry-mode',
        'ask',
        '--output',
        tarball,
        '--decrypt',
        file,
      ], environment: env);
      if (r.exitCode != 0) return [];
      final list = Process.runSync('tar', ['tzf', tarball]);
      return (list.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty && !l.endsWith('/'))
          .toList()
        ..sort();
    }

    test(
      'cifra pelo pinentry, sem sockets e travas, sem cache da senha',
      () async {
        final r = await archiver().archive(
          items: ['.ssh', '.gnupg'],
          destination: path('destino'),
          date: DateTime(2026, 11, 9),
        );

        expect(r.outcome, SecretsOutcome.ok, reason: r.message);
        expect(r.bytes, greaterThan(0));
        expect(
          Process.runSync('file', ['-b', r.path!]).stdout,
          anyOf(
            contains('GPG symmetrically encrypted data (AES256 cipher)'),
            contains('PGP symmetric key encrypted data - AES with 256-bit key'),
          ),
        );
        expect(
          Directory(path('destino')).listSync().map((e) => p.basename(e.path)),
          ['secrets-2026-11-09.tar.gz.gpg'],
        );

        File(path('pinentry/modo')).writeAsStringSync('cancelar');
        expect(decrypt(r.path!), isEmpty);

        File(path('pinentry/modo')).writeAsStringSync('responder');
        expect(decrypt(r.path!), [
          '.gnupg/pubring.kbx',
          '.ssh/config',
          '.ssh/id_ed25519',
        ]);
      },
    );

    test('fechar a janela de senha cancela e não deixa arquivo', () async {
      File(path('pinentry/modo')).writeAsStringSync('cancelar');

      final r = await archiver().archive(
        items: ['.ssh'],
        destination: path('destino'),
        date: DateTime(2026, 11, 9),
      );

      expect(r.outcome, SecretsOutcome.cancelled, reason: r.message);
      expect(Directory(path('destino')).listSync(), isEmpty);
    });

    group('extrair', () {
      late String packed;
      late Directory staging;

      setUp(() async {
        final r = await archiver().archive(
          items: ['.ssh'],
          destination: path('destino'),
          date: DateTime(2026, 11, 9),
        );
        packed = r.path!;
        staging = Directory(path('staging'))..createSync();
      });

      test('descriptografa pelo pinentry e abre na pasta temporária', () async {
        final r = await archiver().extract(file: packed, staging: staging.path);
        expect(r.outcome, SecretsOutcome.ok, reason: r.message);
        expect(
          File(p.join(staging.path, '.ssh/id_ed25519')).readAsStringSync(),
          'chave privada',
        );
      });

      test('senha errada falha sem abrir nada', () async {
        File(path('pinentry/senha')).writeAsStringSync('outra senha');
        final r = await archiver().extract(file: packed, staging: staging.path);
        expect(r.outcome, SecretsOutcome.failed);
        expect(r.message, contains('Senha errada'));
        expect(staging.listSync(), isEmpty);
      });

      test('fechar a janela de senha cancela', () async {
        File(path('pinentry/modo')).writeAsStringSync('cancelar');
        final r = await archiver().extract(file: packed, staging: staging.path);
        expect(r.outcome, SecretsOutcome.cancelled, reason: r.message);
        expect(staging.listSync(), isEmpty);
      });
    });
  });
}
