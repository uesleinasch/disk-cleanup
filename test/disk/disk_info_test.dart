import 'dart:convert';

import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/disk/disk_info.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

const _dfArgs = [
  '-B1',
  '--output=source,fstype,size,used,avail,target',
  '-x',
  'tmpfs',
  '-x',
  'devtmpfs',
  '-x',
  'squashfs',
  '-x',
  'overlay',
  '-x',
  'efivarfs',
];

const _output = '''
Filesystem     Type       1B-blocks         Used        Avail Mounted on
/dev/nvme0n1p2 ext4    502500000000 330000000000  44000000000 /
/dev/sdb1      exfat   1000000000000 500000000000 480000000000 /media/u/Meu Disco
''';

RunResult _ok(String text, [int code = 0]) =>
    RunResult(code, utf8.encode(text), '');

void main() {
  test('parseDf lê duas linhas, inclusive ponto de montagem com espaço', () {
    final vols = parseDf(_output);
    expect(vols, hasLength(2));
    expect(vols[0].device, '/dev/nvme0n1p2');
    expect(vols[0].fsType, 'ext4');
    expect(vols[0].mountPoint, '/');
    expect(vols[0].size, 502500000000);
    expect(vols[0].used, 330000000000);
    expect(vols[0].available, 44000000000);
    expect(vols[0].reserved, 502500000000 - 330000000000 - 44000000000);
    expect(vols[1].mountPoint, '/media/u/Meu Disco');
    expect(vols[1].reserved, 1000000000000 - 500000000000 - 480000000000);
  });

  test('parseDf pula linhas inválidas', () {
    expect(parseDf('Filesystem Type\nlixo\n/dev/a ext4 x y z /\n'), isEmpty);
  });

  test('volumes chama df com os argumentos esperados', () async {
    final runner = FakeProcessRunner()..when('df', _dfArgs, _ok(_output));
    final vols = await DiskInfoService(runner).volumes();
    expect(vols, hasLength(2));
    expect(runner.calls.single, ['df', ..._dfArgs]);
  });

  test('volumes devolve o parse mesmo com saída não zero', () async {
    final runner = FakeProcessRunner()..when('df', _dfArgs, _ok(_output, 1));
    expect(await DiskInfoService(runner).volumes(), hasLength(2));
  });

  test('freeFraction é zero com size 0', () {
    final v = VolumeUsage(
      device: 'd',
      fsType: 'f',
      mountPoint: '/',
      size: 0,
      used: 0,
      available: 0,
    );
    expect(v.freeFraction, 0);
  });
}
