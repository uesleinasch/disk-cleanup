import 'dart:convert';

import '../core/models.dart';
import '../core/process_runner.dart';
import 'privileged_runner.dart';

const _dfArgs = ['system', 'df', '-v', '--format', '{{json .}}'];

final _sizePattern = RegExp(r'^([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]*)$');

const _units = {
  'B': 1,
  'KB': 1000,
  'MB': 1000000,
  'GB': 1000000000,
  'TB': 1000000000000,
};

int parseDockerSize(String s) {
  final token = s.trim().split(RegExp(r'\s+')).first;
  final m = _sizePattern.firstMatch(token);
  if (m == null) return 0;
  final factor = _units[m[2]!.toUpperCase()];
  final value = double.tryParse(m[1]!);
  if (factor == null || value == null) return 0;
  return (value * factor).round();
}

class DockerContainer {
  const DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    required this.bytes,
  });

  final String id;
  final String name;
  final String image;
  final String status;
  final int bytes;
}

class DockerImage {
  const DockerImage({
    required this.id,
    required this.repoTag,
    required this.bytes,
  });

  final String id;
  final String repoTag;
  final int bytes;
}

class DockerVolume {
  const DockerVolume({required this.name, required this.bytes});

  final String name;
  final int bytes;
}

class DockerInventory {
  const DockerInventory({
    required this.available,
    required this.needsRoot,
    required this.imagesBytes,
    required this.containersBytes,
    required this.volumesBytes,
    required this.buildCacheBytes,
    required this.buildCacheReclaimable,
    required this.stopped,
    required this.unusedImages,
    required this.unusedVolumes,
  });

  const DockerInventory.unavailable()
    : this._empty(available: false, needsRoot: false);

  const DockerInventory.needsRootOnly()
    : this._empty(available: true, needsRoot: true);

  const DockerInventory._empty({
    required this.available,
    required this.needsRoot,
  }) : imagesBytes = 0,
       containersBytes = 0,
       volumesBytes = 0,
       buildCacheBytes = 0,
       buildCacheReclaimable = 0,
       stopped = const [],
       unusedImages = const [],
       unusedVolumes = const [];

  final bool available;
  final bool needsRoot;
  final int imagesBytes;
  final int containersBytes;
  final int volumesBytes;
  final int buildCacheBytes;
  final int buildCacheReclaimable;
  final List<DockerContainer> stopped;
  final List<DockerImage> unusedImages;
  final List<DockerVolume> unusedVolumes;

  DockerInventory withNeedsRoot(bool value) => DockerInventory(
    available: available,
    needsRoot: value,
    imagesBytes: imagesBytes,
    containersBytes: containersBytes,
    volumesBytes: volumesBytes,
    buildCacheBytes: buildCacheBytes,
    buildCacheReclaimable: buildCacheReclaimable,
    stopped: stopped,
    unusedImages: unusedImages,
    unusedVolumes: unusedVolumes,
  );

  List<CleanupItem> toItems() {
    CleanupItem item({
      required String id,
      required String title,
      required String note,
      required int bytes,
      required RiskLevel risk,
      required DockerOp op,
      List<String> ids = const [],
    }) => CleanupItem(
      id: id,
      category: CleanupCategory.docker,
      title: title,
      note: note,
      bytes: bytes,
      risk: risk,
      requiresRoot: needsRoot,
      preselected: risk == RiskLevel.safe,
      action: DockerAction(op, ids),
    );

    return [
      if (buildCacheReclaimable > 0)
        item(
          id: 'docker:buildcache',
          title: 'Build cache',
          note: 'Camadas intermediárias de builds. O próximo docker build recria o que precisar.',
          bytes: buildCacheReclaimable,
          risk: RiskLevel.safe,
          op: DockerOp.pruneBuildCache,
        ),
      if (stopped.isNotEmpty)
        item(
          id: 'docker:containers',
          title: 'Containers parados',
          note: 'Remover apaga o que foi gravado dentro do container e não está em volume.',
          bytes: stopped.fold(0, (a, c) => a + c.bytes),
          risk: RiskLevel.attention,
          op: DockerOp.removeContainers,
          ids: [for (final c in stopped) c.id],
        ),
      if (unusedImages.isNotEmpty)
        item(
          id: 'docker:images',
          title: 'Imagens sem uso',
          note: 'Podem ser baixadas de novo com docker pull, se o registro ainda tiver a versão.',
          bytes: unusedImages.fold(0, (a, i) => a + i.bytes),
          risk: RiskLevel.attention,
          op: DockerOp.removeImages,
          ids: [for (final i in unusedImages) i.id],
        ),
      if (unusedVolumes.isNotEmpty)
        item(
          id: 'docker:volumes',
          title: 'Volumes sem uso',
          note: 'Volumes guardam dados de bancos e serviços. Confira antes de remover.',
          bytes: unusedVolumes.fold(0, (a, v) => a + v.bytes),
          risk: RiskLevel.attention,
          op: DockerOp.removeVolumes,
          ids: [for (final v in unusedVolumes) v.name],
        ),
    ];
  }
}

class DockerService {
  DockerService(this._runner, this._root);

  final ProcessRunner _runner;
  final PrivilegedRunner _root;
  bool _needsRoot = false;

  Future<DockerInventory> inventory() async {
    final result = await _runner.run('docker', _dfArgs);
    if (result.exitCode == 0) {
      _needsRoot = false;
      return _parse(result.stdoutText);
    }
    final err = result.stderr.toLowerCase();
    if (result.exitCode == 127) return const DockerInventory.unavailable();
    if (err.contains('permission denied')) {
      _needsRoot = true;
      return const DockerInventory.needsRootOnly();
    }
    return const DockerInventory.unavailable();
  }

  Future<DockerInventory> inventoryAsRoot() async {
    final batch = await _root.run([DockerCli(DockerOp.inventory, [])]);
    _needsRoot = true;
    if (batch.cancelled || batch.exitCodes[0] != 0) {
      return const DockerInventory.needsRootOnly();
    }
    final json = batch.stdout
        .split(RegExp('[\n\u0000]'))
        .takeWhile((l) => !l.startsWith('__dc_status'))
        .join('\n');
    return _parse(json).withNeedsRoot(true);
  }

  Future<bool> execute(DockerOp op, List<String> ids) async {
    if (_needsRoot) {
      final batch = await _root.run([DockerCli(op, ids)]);
      return !batch.cancelled && batch.exitCodes[0] == 0;
    }
    final args = switch (op) {
      DockerOp.inventory => _dfArgs,
      DockerOp.pruneBuildCache => ['builder', 'prune', '-f'],
      DockerOp.removeContainers => ['rm', ...ids],
      DockerOp.removeImages => ['rmi', ...ids],
      DockerOp.removeVolumes => ['volume', 'rm', ...ids],
    };
    final result = await _runner.run('docker', args);
    return result.exitCode == 0;
  }

  DockerInventory _parse(String text) {
    try {
      final json = jsonDecode(text.trim()) as Map<String, dynamic>;
      List<Map<String, dynamic>> list(String key) => [
        for (final e in (json[key] as List? ?? const []))
          Map<String, dynamic>.from(e as Map),
      ];
      int size(Map<String, dynamic> e) =>
          parseDockerSize((e['Size'] as String?) ?? '');

      final images = list('Images');
      final containers = list('Containers');
      final volumes = list('Volumes');
      final cache = list('BuildCache');

      String stripSha(String id) =>
          id.startsWith('sha256:') ? id.substring(7) : id;

      return DockerInventory(
        available: true,
        needsRoot: false,
        imagesBytes: images.fold(0, (a, e) => a + size(e)),
        containersBytes: containers.fold(0, (a, e) => a + size(e)),
        volumesBytes: volumes.fold(0, (a, e) => a + size(e)),
        buildCacheBytes: cache.fold(0, (a, e) => a + size(e)),
        buildCacheReclaimable: cache
            .where((e) => e['InUse'] == 'false')
            .fold(0, (a, e) => a + size(e)),
        stopped: [
          for (final c in containers)
            if (c['State'] == 'exited' || c['State'] == 'created')
              DockerContainer(
                id: c['ID'] as String,
                name: c['Names'] as String,
                image: c['Image'] as String,
                status: c['Status'] as String,
                bytes: size(c),
              ),
        ],
        unusedImages: [
          for (final i in images)
            if (i['Containers'] == '0')
              DockerImage(
                id: stripSha(i['ID'] as String),
                repoTag: '${i['Repository']}:${i['Tag']}',
                bytes: size(i),
              ),
        ],
        unusedVolumes: [
          for (final v in volumes)
            if (v['Links'] == '0')
              DockerVolume(name: v['Name'] as String, bytes: size(v)),
        ],
      );
    } on Object {
      return const DockerInventory.unavailable();
    }
  }
}
