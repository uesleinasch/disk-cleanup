import 'dart:convert';
import 'dart:io';

import 'package:disk_cleanup/backup/disk_targets.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/settings/backup_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

const _lsblkArgs = [
  '-J',
  '-b',
  '-p',
  '-o',
  'NAME,LABEL,UUID,FSTYPE,HOTPLUG,SIZE,FSAVAIL,MOUNTPOINT',
];
const _findmnt = [
  '-J',
  '-b',
  '--list',
  '-o',
  'TARGET,SOURCE,FSTYPE,UUID,LABEL,AVAIL',
];

RunResult _json(Object value) =>
    RunResult(0, utf8.encode(jsonEncode(value)), '');

Map<String, Object?> _fs(
  String target,
  String source, {
  String fstype = 'ext4',
  String? uuid,
  String? label,
  int avail = 1000,
}) => {
  'target': target,
  'source': source,
  'fstype': fstype,
  'uuid': uuid,
  'label': label,
  'avail': avail,
};

void main() {
  group('parseLsblk', () {
    final targets = parseLsblk(
      File('test/fixtures/lsblk.json').readAsStringSync(),
    );

    test('lista só partições montadas úteis, externas primeiro', () {
      expect(targets.map((t) => t.mountPoint), [
        '/media/user/Disco externo',
        '/media/user/PENDRIVE',
        '/mnt/dados',
      ]);
    });

    test('lê campos numéricos e booleanos em texto ou número', () {
      final hd = targets.first;
      expect(hd.device, '/dev/sda1');
      expect(hd.name, 'Disco externo');
      expect(hd.uuid, '88270be3-0000-4e3d-ac16-1aa7d563da2b');
      expect(hd.fsType, 'ext4');
      expect(hd.hotplug, isTrue);
      expect(hd.size, 1000202240512);
      expect(hd.available, 912790462464);
      expect(hd.problem, isNull);

      final pen = targets[1];
      expect(pen.hotplug, isTrue);
      expect(pen.size, 64019759104);
      expect(pen.problem, contains('exFAT'));
    });

    test('desce em LUKS/LVM e não marca disco interno como externo', () {
      final dados = targets.last;
      expect(dados.device, '/dev/mapper/dados');
      expect(dados.fsType, 'btrfs');
      expect(dados.hotplug, isFalse);
      expect(dados.problem, isNull);
    });

    test('JSON sem blockdevices devolve lista vazia', () {
      expect(parseLsblk('{}'), isEmpty);
    });
  });

  test('backupFsProblem', () {
    for (final ok in ['ext4', 'btrfs', 'xfs', 'nfs4']) {
      expect(backupFsProblem(ok), isNull, reason: ok);
    }
    expect(backupFsProblem('vfat'), contains('FAT32'));
    expect(backupFsProblem('ntfs3'), contains('NTFS'));
    expect(backupFsProblem('fuseblk'), contains('NTFS'));
    expect(backupFsProblem('exfat'), contains('Formate em ext4'));
    expect(backupFsProblem('cifs'), contains('(cifs) não é suportado'));
    expect(backupFsProblem(null), contains('desconhecido'));
  });

  group('DiskTargets', () {
    test('list usa lsblk e devolve vazio se ele falhar', () async {
      final fake = FakeProcessRunner()
        ..when(
          'lsblk',
          _lsblkArgs,
          RunResult(0, File('test/fixtures/lsblk.json').readAsBytesSync(), ''),
        );
      expect(await DiskTargets(fake).list(), hasLength(3));
      final broken = FakeProcessRunner()
        ..when('lsblk', _lsblkArgs, const RunResult(127, [], ''));
      expect(await DiskTargets(broken).list(), isEmpty);
    });

    test('targetFor guarda id, rótulo e caminho relativo', () async {
      final fake = FakeProcessRunner()
        ..when(
          'findmnt',
          [..._findmnt, '-T', '/media/user/Disco externo/copias/'],
          _json({
            'filesystems': [
              _fs(
                '/media/user/Disco externo',
                '/dev/sda1',
                uuid: 'u-1',
                label: 'Disco externo',
              ),
            ],
          }),
        )
        ..when(
          'findmnt',
          [..._findmnt, '-T', '/media/user/Disco externo'],
          _json({
            'filesystems': [
              _fs('/media/user/Disco externo', '/dev/sda1', uuid: 'u-1'),
            ],
          }),
        );
      final targets = DiskTargets(fake);
      expect(
        await targets.targetFor('/media/user/Disco externo/copias/'),
        const BackupTarget(
          id: 'u-1',
          label: 'Disco externo',
          relPath: 'copias',
        ),
      );
      expect(
        await targets.targetFor('/media/user/Disco externo'),
        const BackupTarget(id: 'u-1', label: 'Disco externo'),
      );
    });

    test('sem UUID (NFS) usa a origem da montagem como id', () async {
      final fake = FakeProcessRunner()
        ..when(
          'findmnt',
          [..._findmnt, '-T', '/mnt/nas/backups'],
          _json({
            'filesystems': [
              _fs('/mnt/nas', 'servidor:/export', fstype: 'nfs4'),
            ],
          }),
        );
      expect(
        await DiskTargets(fake).targetFor('/mnt/nas/backups'),
        const BackupTarget(
          id: 'servidor:/export',
          label: 'nas',
          relPath: 'backups',
        ),
      );
    });

    test('resolve acha o disco mesmo em outro ponto de montagem', () async {
      final fake = FakeProcessRunner()
        ..when(
          'findmnt',
          _findmnt,
          _json({
            'filesystems': [
              _fs('/', '/dev/nvme0n1p2', uuid: 'raiz'),
              _fs('/media/outro/Disco externo', '/dev/sdc1', uuid: 'u-1'),
            ],
          }),
        );
      final targets = DiskTargets(fake);
      expect(
        await targets.resolve(
          const BackupTarget(
            id: 'u-1',
            label: 'Disco externo',
            relPath: 'copias',
          ),
        ),
        '/media/outro/Disco externo/copias',
      );
      expect(
        await targets.resolve(const BackupTarget(id: 'u-1', label: 'X')),
        '/media/outro/Disco externo',
      );
      expect(
        await targets.resolve(const BackupTarget(id: 'sumiu', label: 'X')),
        isNull,
      );
    });

    test('mountOf lê o findmnt real', () async {
      final m = await DiskTargets(SystemProcessRunner()).mountOf('/');
      expect(m, isNotNull);
      expect(m!.target, '/');
      expect(m.fsType, isNotNull);
    });

    test('isWritable', () async {
      final dir = Directory.systemTemp.createTempSync('disk_targets_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final targets = DiskTargets(FakeProcessRunner());
      expect(await targets.isWritable(dir.path), isTrue);
      expect(dir.listSync(), isEmpty);
      expect(await targets.isWritable('${dir.path}/nao-existe'), isFalse);
    });
  });
}
