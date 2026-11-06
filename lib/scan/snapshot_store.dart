import 'dart:convert';
import 'dart:io';

class Snapshot {
  const Snapshot({required this.takenAt, required this.state});

  final DateTime takenAt;
  final Map<String, dynamic> state;
}

int? weeklyDelta(int currentBytes, int? weekAgoBytes) =>
    weekAgoBytes == null ? null : currentBytes - weekAgoBytes;

class SnapshotStore {
  SnapshotStore(this.dir);

  final String dir;

  static final _fileName = RegExp(r'^snapshot-\d+\.json$');

  Future<void> save(Snapshot s) async {
    final directory = Directory(dir);
    await directory.create(recursive: true);
    final name = 'snapshot-${s.takenAt.millisecondsSinceEpoch}.json';
    final tmp = File('$dir/$name.tmp');
    final body = jsonEncode({
      'takenAt': s.takenAt.toIso8601String(),
      'state': s.state,
    });
    await tmp.writeAsString(body, flush: true);
    await tmp.rename('$dir/$name');
  }

  Future<Snapshot?> latest() async {
    Snapshot? best;
    for (final entry in await _load()) {
      if (best == null || entry.snapshot.takenAt.isAfter(best.takenAt)) {
        best = entry.snapshot;
      }
    }
    return best;
  }

  Future<Snapshot?> closestTo(
    DateTime target, {
    Duration tolerance = const Duration(days: 3),
  }) async {
    Snapshot? best;
    Duration? bestDistance;
    for (final entry in await _load()) {
      final s = entry.snapshot;
      final distance = s.takenAt.difference(target).abs();
      if (distance > tolerance) continue;
      final better =
          best == null ||
          distance < bestDistance! ||
          (distance == bestDistance && s.takenAt.isBefore(best.takenAt));
      if (better) {
        best = s;
        bestDistance = distance;
      }
    }
    return best;
  }

  Future<void> prune({
    Duration keep = const Duration(days: 90),
    DateTime? now,
  }) async {
    final cutoff = (now ?? DateTime.now()).subtract(keep);
    for (final entry in await _load()) {
      if (entry.snapshot.takenAt.isBefore(cutoff)) {
        try {
          await entry.file.delete();
        } on FileSystemException {
          continue;
        }
      }
    }
  }

  Future<List<({File file, Snapshot snapshot})>> _load() async {
    final directory = Directory(dir);
    if (!await directory.exists()) return const [];
    final result = <({File file, Snapshot snapshot})>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!_fileName.hasMatch(entity.uri.pathSegments.last)) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        final takenAt = DateTime.parse((json as Map)['takenAt'] as String);
        final state = Map<String, dynamic>.from(json['state'] as Map);
        result.add((
          file: entity,
          snapshot: Snapshot(takenAt: takenAt, state: state),
        ));
      } on Object {
        continue;
      }
    }
    return result;
  }
}
