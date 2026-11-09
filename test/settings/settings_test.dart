import 'dart:io';

import 'package:disk_cleanup/settings/settings.dart';
import 'package:disk_cleanup/settings/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('padrões', () {
    final s = Settings.defaults('/home/u');
    expect(s.mappedDirs, ['/home/u']);
    expect(s.warnPercent, 15);
    expect(s.warnBytes, 20000000000);
    expect(s.critPercent, 5);
    expect(s.critBytes, 5000000000);
    expect(s.protectActiveProjects, true);
    expect(s.activeProjectDays, 14);
    expect(s.buildRules, kDefaultBuildRules);
    expect(s.window, isNull);
  });

  test('round-trip JSON preserva todos os campos', () {
    final s = Settings.defaults('/home/u').copyWith(
      mappedDirs: ['/a', '/b'],
      warnPercent: 12,
      critBytes: 123,
      protectActiveProjects: false,
      activeProjectDays: 7,
      buildRules: [const BuildRule('out', '*.proj')],
      themeMode: ThemeMode.dark,
      bannerSnoozedUntil: DateTime.utc(2026, 11, 7, 10),
      window: const WindowBounds(
        x: 10,
        y: 20.5,
        width: 900,
        height: 700,
        maximized: true,
      ),
    );
    expect(Settings.fromJson(s.toJson(), '/home/u'), s);
  });

  group('backup', () {
    final full = const BackupSettings().copyWith(
      sources: ['/home/u/projetos', '/mnt/dados/docs'],
      target: const BackupTarget(
        id: '1234-abcd',
        label: 'Disco externo',
        relPath: 'copias',
      ),
      folderName: 'meu-backup',
      browsers: ['brave'],
      secretsEnabled: false,
      secretItems: ['.ssh', 'chave.pem'],
      mirror: true,
      lastBackupAt: DateTime.utc(2026, 11, 8, 22, 15),
      reminderDays: 14,
    );

    test('padrões', () {
      const b = BackupSettings();
      expect(Settings.defaults('/home/u').backup, b);
      expect(b.sources, isEmpty);
      expect(b.target, isNull);
      expect(b.folderName, 'backup');
      expect(b.browsers, isNull);
      expect(b.secretsEnabled, isTrue);
      expect(b.secretItems, isNull);
      expect(b.mirror, isFalse);
      expect(b.lastBackupAt, isNull);
      expect(b.reminderDays, 7);
    });

    test('round-trip JSON preserva todos os campos', () {
      final s = Settings.defaults('/home/u').copyWith(backup: full);
      expect(Settings.fromJson(s.toJson(), '/home/u'), s);
    });

    test('JSON sem a chave backup mantém o resto e carrega os padrões', () {
      final old =
          Settings.defaults('/home/u')
              .copyWith(mappedDirs: ['/a'], warnPercent: 12)
              .toJson()
            ..remove('backup');
      final s = Settings.fromJson(old, '/home/u');
      expect(s.mappedDirs, ['/a']);
      expect(s.warnPercent, 12);
      expect(s.backup, const BackupSettings());
    });

    test('bloco backup parcial completa com os padrões', () {
      final s = Settings.fromJson({
        'backup': {
          'sources': ['/x'],
        },
      }, '/home/u');
      expect(s.backup, const BackupSettings(sources: ['/x']));
    });

    test('igualdade considera listas e destino', () {
      expect(full.copyWith(), full);
      expect(full.hashCode, full.copyWith().hashCode);
      expect(full.copyWith(browsers: ['brave', 'chrome']), isNot(full));
      expect(full.copyWith(secretItems: ['.ssh']), isNot(full));
      expect(
        full.copyWith(
          target: const BackupTarget(id: '1234-abcd', label: 'Disco externo'),
        ),
        isNot(full),
      );
      expect(const BackupSettings(browsers: []), isNot(const BackupSettings()));
    });

    test('clearTarget remove o destino', () {
      expect(full.copyWith(clearTarget: true).target, isNull);
      expect(full.copyWith().target, full.target);
    });
  });

  test('matchesMarker com nome exato e glob', () {
    const rule = BuildRule('bin', '*.csproj');
    expect(rule.matchesMarker('Api.csproj'), isTrue);
    expect(rule.matchesMarker('Api.cs'), isFalse);
    const exact = BuildRule('build', 'pubspec.yaml');
    expect(exact.matchesMarker('pubspec.yaml'), isTrue);
    expect(exact.matchesMarker('xpubspec.yaml'), isFalse);
  });

  group('SettingsStore', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('settings_test');
      path = '${dir.path}/sub/settings.json';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('arquivo inexistente devolve padrões', () async {
      expect(
        await SettingsStore(path).load('/home/u'),
        Settings.defaults('/home/u'),
      );
    });

    test('JSON inválido devolve padrões e cria .bak', () async {
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('{ nao e json');
      final s = await SettingsStore(path).load('/home/u');
      expect(s, Settings.defaults('/home/u'));
      expect(File('$path.bak').existsSync(), isTrue);
      expect(File(path).existsSync(), isFalse);
    });

    test('save seguido de load devolve o mesmo valor', () async {
      final store = SettingsStore(path);
      final s = Settings.defaults('/home/u').copyWith(
        themeMode: ThemeMode.light,
        window: const WindowBounds(x: 1, y: 2, width: 800, height: 600),
      );
      await store.save(s);
      expect(await store.load('/home/u'), s);
    });

    test('defaultPath respeita XDG_CONFIG_HOME', () {
      expect(
        SettingsStore.defaultPath({'XDG_CONFIG_HOME': '/x'}, '/h'),
        '/x/disk-cleanup/settings.json',
      );
      expect(
        SettingsStore.defaultPath({}, '/h'),
        '/h/.config/disk-cleanup/settings.json',
      );
    });
  });
}
