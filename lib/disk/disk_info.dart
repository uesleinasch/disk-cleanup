import '../core/process_runner.dart';

class VolumeUsage {
  const VolumeUsage({
    required this.device,
    required this.fsType,
    required this.mountPoint,
    required this.size,
    required this.used,
    required this.available,
  });

  final String device;
  final String fsType;
  final String mountPoint;
  final int size;
  final int used;
  final int available;

  int get reserved => size - used - available;

  double get freeFraction => size <= 0 ? 0 : available / size;
}

List<VolumeUsage> parseDf(String output) {
  final volumes = <VolumeUsage>[];
  final fields = RegExp(r'^(\S+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(.+)$');
  for (final line in output.split('\n').skip(1)) {
    final m = fields.firstMatch(line.trimRight());
    if (m == null) continue;
    volumes.add(
      VolumeUsage(
        device: m[1]!,
        fsType: m[2]!,
        size: int.parse(m[3]!),
        used: int.parse(m[4]!),
        available: int.parse(m[5]!),
        mountPoint: m[6]!,
      ),
    );
  }
  return volumes;
}

class DiskInfoService {
  DiskInfoService(this._runner);

  final ProcessRunner _runner;

  Future<List<VolumeUsage>> volumes() async {
    final result = await _runner.run('df', const [
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
    ], environment: cLocaleEnvironment);
    return parseDf(result.stdoutText);
  }
}
