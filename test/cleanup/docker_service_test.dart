import 'dart:io';

import 'package:disk_cleanup/cleanup/docker_service.dart';
import 'package:disk_cleanup/cleanup/privileged_runner.dart';
import 'package:disk_cleanup/core/models.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

const _dfArgs = ['system', 'df', '-v', '--format', '{{json .}}'];

RunResult _ok(String out, {int code = 0, String err = ''}) =>
    RunResult(code, out.codeUnits, err);

String _fixture() =>
    File('test/fixtures/docker_system_df_v.json').readAsStringSync();

DockerService _service(FakeProcessRunner fake) =>
    DockerService(fake, PrivilegedRunner(fake));

void main() {
  group('parseDockerSize', () {
    test('unidades SI decimais', () {
      expect(parseDockerSize('1.2GB'), 1200000000);
      expect(parseDockerSize('512kB'), 512000);
      expect(parseDockerSize('512KB'), 512000);
      expect(parseDockerSize('0B'), 0);
      expect(parseDockerSize('53.51MB'), 53510000);
      expect(parseDockerSize('2TB'), 2000000000000);
      expect(parseDockerSize('10B'), 10);
    });

    test('forma com virtual usa o primeiro token', () {
      expect(parseDockerSize('2.1MB (virtual 722MB)'), 2100000);
    });

    test('entrada inválida vira 0', () {
      expect(parseDockerSize(''), 0);
      expect(parseDockerSize('N/A'), 0);
    });
  });

  group('inventory', () {
    test('fixture gera totais e listas coerentes', () async {
      final fake = FakeProcessRunner()
        ..when('docker', _dfArgs, _ok(_fixture()));
      final inv = await _service(fake).inventory();

      expect(inv.available, isTrue);
      expect(inv.needsRoot, isFalse);
      expect(inv.imagesBytes, 1922512000);
      expect(inv.containersBytes, 1882100000);
      expect(inv.volumesBytes, 1553518190);
      expect(inv.buildCacheBytes, 1765800000);
      expect(inv.buildCacheReclaimable, 1465800000);
      expect(inv.unusedImages.map((i) => i.repoTag), [
        'example/api:latest',
        '<none>:<none>',
      ]);
      expect(inv.unusedImages.first.bytes, 1200000000);
      expect(inv.unusedImages.first.id, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(inv.stopped.map((c) => c.name), ['app-db-1', 'app-tmp-1']);
      expect(inv.stopped.first.status, 'Exited (0) 2 weeks ago');
      expect(inv.stopped.first.image, 'example/api');
      expect(inv.stopped.first.bytes, 1880000000);
      expect(inv.unusedVolumes.map((v) => v.name).first, 'vol-old');
      expect(inv.unusedVolumes, hasLength(2));
      expect(inv.unusedVolumes.first.bytes, 1500000000);
      expect(fake.calls, [
        ['docker', ..._dfArgs],
      ]);
    });

    test('docker ausente (127) fica indisponível sem exceção', () async {
      final fake = FakeProcessRunner()
        ..when('docker', _dfArgs, const RunResult(127, [], 'not found'));
      final inv = await _service(fake).inventory();
      expect(inv.available, isFalse);
      expect(inv.needsRoot, isFalse);
    });

    test('permission denied pede root sem chamar pkexec', () async {
      final fake = FakeProcessRunner()
        ..when(
          'docker',
          _dfArgs,
          const RunResult(
            1,
            [],
            'permission denied while trying to connect to the Docker daemon socket',
          ),
        );
      final inv = await _service(fake).inventory();
      expect(inv.needsRoot, isTrue);
      expect(inv.available, isTrue);
      expect(fake.calls.any((c) => c.first == 'pkexec'), isFalse);
    });

    test('daemon parado fica indisponível', () async {
      final fake = FakeProcessRunner()
        ..when(
          'docker',
          _dfArgs,
          const RunResult(
            1,
            [],
            'Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?',
          ),
        );
      final inv = await _service(fake).inventory();
      expect(inv.available, isFalse);
      expect(inv.needsRoot, isFalse);
    });

    test('saída inválida fica indisponível sem exceção', () async {
      final fake = FakeProcessRunner()..when('docker', _dfArgs, _ok('lixo'));
      final inv = await _service(fake).inventory();
      expect(inv.available, isFalse);
    });
  });

  group('inventoryAsRoot', () {
    test('lê o JSON do stdout do lote', () async {
      final fake = FakeProcessRunner();
      final script = buildRootScript([DockerCli(DockerOp.inventory, [])]);
      fake.when('pkexec', [
        '/bin/sh',
        '-c',
        script,
      ], _ok('${_fixture().replaceAll('\n', '')}\n__dc_status 0 0\n'));
      final inv = await _service(fake).inventoryAsRoot();
      expect(inv.available, isTrue);
      expect(inv.needsRoot, isTrue);
      expect(inv.buildCacheReclaimable, 1465800000);
      expect(inv.stopped, hasLength(2));
    });

    test('cancelado devolve needsRoot sem dados', () async {
      final fake = FakeProcessRunner();
      final script = buildRootScript([DockerCli(DockerOp.inventory, [])]);
      fake.when('pkexec', [
        '/bin/sh',
        '-c',
        script,
      ], const RunResult(126, [], ''));
      final inv = await _service(fake).inventoryAsRoot();
      expect(inv.needsRoot, isTrue);
      expect(inv.stopped, isEmpty);
      expect(inv.imagesBytes, 0);
    });
  });

  group('toItems', () {
    late DockerInventory inv;
    setUp(() async {
      final fake = FakeProcessRunner()
        ..when('docker', _dfArgs, _ok(_fixture()));
      inv = await _service(fake).inventory();
    });

    test('um item por grupo com riscos e pré-seleção', () {
      final items = inv.toItems();
      expect(items.map((i) => i.id), [
        'docker:buildcache',
        'docker:containers',
        'docker:images',
        'docker:volumes',
      ]);
      final cache = items[0];
      expect(cache.risk, RiskLevel.safe);
      expect(cache.preselected, isTrue);
      expect(cache.bytes, 1465800000);
      expect(cache.category, CleanupCategory.docker);
      expect(cache.title, 'Build cache');
      final action = cache.action as DockerAction;
      expect(action.op, DockerOp.pruneBuildCache);
      expect(action.ids, isEmpty);
      for (final i in items.skip(1)) {
        expect(i.risk, RiskLevel.attention);
        expect(i.preselected, isFalse);
        expect(i.requiresRoot, isFalse);
      }
      final containers = items[1].action as DockerAction;
      expect(containers.op, DockerOp.removeContainers);
      expect(containers.ids, hasLength(2));
      expect(items[1].title, 'Containers parados');
      expect(items[2].title, 'Imagens sem uso');
      expect(items[3].title, 'Volumes sem uso');
      expect((items[3].action as DockerAction).ids, contains('vol-old'));
    });

    test('grupos vazios são omitidos e requiresRoot segue needsRoot', () {
      const empty = DockerInventory(
        available: true,
        needsRoot: true,
        imagesBytes: 0,
        containersBytes: 0,
        volumesBytes: 0,
        buildCacheBytes: 0,
        buildCacheReclaimable: 10,
        stopped: [],
        unusedImages: [],
        unusedVolumes: [],
      );
      final items = empty.toItems();
      expect(items, hasLength(1));
      expect(items.single.requiresRoot, isTrue);
    });
  });

  group('execute', () {
    test('sem root roda docker direto', () async {
      final fake = FakeProcessRunner()
        ..when('docker', ['builder', 'prune', '-f'], _ok(''))
        ..when('docker', ['rm', 'a', 'b'], _ok(''))
        ..when('docker', ['rmi', 'a'], _ok('', code: 1))
        ..when('docker', ['volume', 'rm', 'v'], _ok(''));
      final s = _service(fake);
      expect(await s.execute(DockerOp.pruneBuildCache, []), isTrue);
      expect(await s.execute(DockerOp.removeContainers, ['a', 'b']), isTrue);
      expect(await s.execute(DockerOp.removeImages, ['a']), isFalse);
      expect(await s.execute(DockerOp.removeVolumes, ['v']), isTrue);
    });

    test('com root usa PrivilegedRunner', () async {
      final fake = FakeProcessRunner();
      final script = buildRootScript([
        DockerCli(DockerOp.removeContainers, ['abcdef123456']),
      ]);
      fake.when('pkexec', ['/bin/sh', '-c', script], _ok('__dc_status 0 0\n'));
      final s = _service(fake);
      fake.when('docker', _dfArgs, _ok('x', code: 1, err: 'permission denied'));
      await s.inventory();
      expect(
        await s.execute(DockerOp.removeContainers, ['abcdef123456']),
        isTrue,
      );
      expect(fake.calls.last.first, 'pkexec');
    });
  });
}
