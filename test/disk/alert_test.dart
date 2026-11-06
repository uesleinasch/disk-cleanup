import 'package:disk_cleanup/disk/alert.dart';
import 'package:disk_cleanup/disk/disk_info.dart';
import 'package:disk_cleanup/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

VolumeUsage _vol(int size, int available) => VolumeUsage(
  device: 'd',
  fsType: 'ext4',
  mountPoint: '/',
  size: size,
  used: size - available,
  available: available,
);

void main() {
  final s = Settings.defaults('/home/u');

  test('44,0 GB livres de 502,5 GB é warning', () {
    expect(
      evaluateAlert(_vol(502500000000, 44000000000), s),
      AlertLevel.warning,
    );
  });
  test('4,6 GB livres de 502,5 GB é critical', () {
    expect(
      evaluateAlert(_vol(502500000000, 4600000000), s),
      AlertLevel.critical,
    );
  });
  test('128,3 GB livres de 502,5 GB é ok', () {
    expect(evaluateAlert(_vol(502500000000, 128300000000), s), AlertLevel.ok);
  });
  test('25 GB de 1000 GB é critical (2,5% vence os 25 GB)', () {
    expect(
      evaluateAlert(_vol(1000000000000, 25000000000), s),
      AlertLevel.critical,
    );
  });
  test('18 GB de 100 GB é warning (abaixo de 20 GB)', () {
    expect(
      evaluateAlert(_vol(100000000000, 18000000000), s),
      AlertLevel.warning,
    );
  });
  test('limites são estritos', () {
    expect(evaluateAlert(_vol(100000000000, 20000000000), s), AlertLevel.ok);
    expect(evaluateAlert(_vol(1000000000000, 150000000000), s), AlertLevel.ok);
  });
  test('size 0 é ok', () {
    expect(evaluateAlert(_vol(0, 0), s), AlertLevel.ok);
  });
}
