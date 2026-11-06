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
