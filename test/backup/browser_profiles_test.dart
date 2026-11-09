import 'dart:convert';
import 'dart:io';

import 'package:disk_cleanup/backup/browser_profiles.dart';
import 'package:disk_cleanup/backup/rsync_runner.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _localState(Map<String, Map<String, Object?>> cache) => jsonEncode({
  'profile': {'info_cache': cache},
});

void main() {
  late Directory home;
  late BrowserProfiles browsers;
  final alive = <int>{};

  String path(String rel) => p.join(home.path, rel);

  void file(String rel, [String content = 'x']) {
    File(path(rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  void lock(String profileRel, String target) =>
      Link(path('$profileRel/SingletonLock')).createSync(target);

  setUp(() {
    home = Directory.systemTemp.createTempSync('browsers_');
    alive.clear();
    browsers = BrowserProfiles(
      home: home.path,
      rsync: RsyncRunner(SystemProcessRunner()),
      hostname: 'maquina',
      pidAlive: alive.contains,
    );
  });

  tearDown(() => home.deleteSync(recursive: true));

  test('parseLocalState lê nome e conta, Default primeiro', () {
    final profiles = parseLocalState(
      _localState({
        'Profile 3': {'name': 'Pessoal', 'user_name': 'pessoal@example.com'},
        'Default': {'name': 'Trabalho', 'user_name': ''},
        'Profile 1': {'user_name': 'outra@example.com'},
      }),
    );
    expect(profiles.map((p) => p.dir), ['Default', 'Profile 1', 'Profile 3']);
    expect(profiles.first.name, 'Trabalho');
    expect(profiles.first.account, isNull);
    expect(profiles[1].name, 'Profile 1');
    expect(profiles.last.account, 'pessoal@example.com');
    expect(parseLocalState('{}'), isEmpty);
  });

  group('detect', () {
    test('só conta pasta com Local State; primeiro caminho existente', () {
      file(
        '.config/BraveSoftware/Brave-Browser/Local State',
        _localState({
          'Default': {'name': 'Trabalho'},
        }),
      );
      file('.config/chromium/lixo.txt');
      file('snap/chromium/common/chromium/Local State', '{}');
      file('.var/app/com.google.Chrome/config/google-chrome/Local State', '{');

      final found = browsers.detect();

      expect(found.map((b) => b.spec.id), ['brave', 'chrome', 'chromium']);
      expect(found.first.profiles.single.name, 'Trabalho');
      expect(found[1].isFlatpak, isTrue);
      expect(found[1].profiles, isEmpty);
      expect(found[2].path, path('snap/chromium/common/chromium'));
    });

    test('nada instalado devolve lista vazia', () {
      expect(browsers.detect(), isEmpty);
    });
  });

  group('isOpen', () {
    BrowserInstall install(String rel) {
      file('$rel/Local State', '{}');
      return BrowserInstall(spec: kBrowserCatalog[1], path: path(rel));
    }

    test('sem lock está fechado', () {
      expect(browsers.isOpen(install('.config/google-chrome')), isFalse);
    });

    test('lock desta máquina com processo vivo está aberto', () {
      final b = install('.config/google-chrome');
      lock('.config/google-chrome', 'maquina-4242');
      alive.add(4242);
      expect(browsers.isOpen(b), isTrue);
    });

    test('lock com processo morto ou de outra máquina é sobra', () {
      final b = install('.config/google-chrome');
      lock('.config/google-chrome', 'maquina-4242');
      expect(browsers.isOpen(b), isFalse);

      Link(path('.config/google-chrome/SingletonLock')).deleteSync();
      lock('.config/google-chrome', 'outra-maquina-4242');
      alive.add(4242);
      expect(browsers.isOpen(b), isFalse);
    });

    test('nome de máquina com hífen continua funcionando', () {
      final hifen = BrowserProfiles(
        home: home.path,
        rsync: RsyncRunner(SystemProcessRunner()),
        hostname: 'note-do-user',
        pidAlive: (pid) => pid == 77,
      );
      final b = install('.config/google-chrome');
      lock('.config/google-chrome', 'note-do-user-77');
      expect(hifen.isOpen(b), isTrue);
    });

    test('Flatpak com lock conta como aberto', () {
      final b = install('.var/app/com.google.Chrome/config/google-chrome');
      lock('.var/app/com.google.Chrome/config/google-chrome', 'maquina-2');
      expect(browsers.isOpen(b), isTrue);
    });

    test('lock ilegível conta como aberto', () {
      final b = install('.config/google-chrome');
      lock('.config/google-chrome', 'semnumero');
      expect(browsers.isOpen(b), isTrue);
    });
  });

  test('copia o perfil sem cache, locks e métricas', () async {
    const rel = '.config/google-chrome';
    file('$rel/Local State', '{}');
    file('$rel/Default/History', 'h');
    file('$rel/Default/Login Data', 'l');
    file('$rel/Default/Cache/Cache_Data/f_0001');
    file('$rel/Default/Code Cache/js/a');
    file('$rel/Default/Service Worker/CacheStorage/x');
    file('$rel/Safe Browsing/lista');
    file('$rel/BrowserMetrics/a.pma');
    Link(path('$rel/SingletonCookie')).createSync('123');
    final filter = File(path('regras'));
    await writeBrowserFilter(filter);
    final install = browsers.detect().single;

    final backup = path('destino/backup');
    final r = await browsers.copy(
      install,
      backupDir: backup,
      filterFile: filter.path,
    );

    expect(r.outcome, RsyncOutcome.ok);
    final dest = p.join(backup, 'navegadores', 'chrome');
    final copied = {
      for (final e in Directory(dest).listSync(recursive: true))
        if (e is File) p.relative(e.path, from: dest),
    };
    expect(copied, {'Local State', 'Default/History', 'Default/Login Data'});
    expect(Link(p.join(dest, 'SingletonCookie')).existsSync(), isFalse);
  });
}
