import 'package:disk_cleanup/core/system_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const home = '/home/u';

  test('recusa a raiz, pastas de sistema e o que há dentro delas', () {
    for (final path in [
      '/',
      '/etc',
      '/usr',
      '/usr/local/lib',
      '/var',
      '/var/log',
      '/tmp/x',
      '/run',
      '/run/media',
      '/root',
      '/proc/1',
      '/lib64',
      '/snap/x',
    ]) {
      expect(isForbiddenMappedDir(path, home: home), isTrue, reason: path);
    }
  });

  test('recusa ancestrais do home e caminhos relativos ou vazios', () {
    for (final path in ['/home', '/home/', '', 'dados', '/home/u/../..']) {
      expect(isForbiddenMappedDir(path, home: home), isTrue, reason: path);
    }
  });

  test('aceita home, subpastas, discos montados e outras pastas', () {
    for (final path in [
      '/home/u',
      '/home/u/projetos',
      '/home/outro',
      '/run/media/u/Disco',
      '/media/u/Disco',
      '/mnt/dados',
      '/dados',
    ]) {
      expect(isForbiddenMappedDir(path, home: home), isFalse, reason: path);
    }
  });

  test('home dentro de /var segue permitido', () {
    expect(isForbiddenMappedDir('/var/home/u/x', home: '/var/home/u'), isFalse);
    expect(isForbiddenMappedDir('/var/home', home: '/var/home/u'), isTrue);
  });

  test('allowedMappedDirs filtra só os proibidos', () {
    expect(allowedMappedDirs(['/home/u', '/etc', '/mnt/d'], home: home), [
      '/home/u',
      '/mnt/d',
    ]);
  });
}
