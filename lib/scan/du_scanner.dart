import 'dart:convert';

import '../core/process_runner.dart';

class DirEntrySize {
  const DirEntrySize(this.path, this.bytes);

  final String path;
  final int bytes;
}

class DuResult {
  const DuResult({
    required this.entries,
    required this.total,
    required this.errors,
    required this.permissionDenied,
  });

  final List<DirEntrySize> entries;
  final int total;
  final int errors;
  final bool permissionDenied;
}

class DuScanner {
  DuScanner(this._runner);

  final ProcessRunner _runner;

  Future<DuResult> childrenSizes(String dir, {CancelToken? cancel}) async {
    _throwIfCancelled(cancel);
    final result = await _runner.run('du', [
      '-x',
      '-a',
      '-d1',
      '-B1',
      '-0',
      dir,
    ], cancel: cancel);
    final self = _normalize(dir);
    final entries = <DirEntrySize>[];
    var total = 0;
    var foundSelf = false;
    for (final record in _records(result)) {
      if (_normalize(record.path) == self) {
        total = record.bytes;
        foundSelf = true;
      } else {
        entries.add(DirEntrySize(record.path, record.bytes));
      }
    }
    final stderrLines = result.stderr.split('\n');
    final errors = stderrLines.where((l) => l.startsWith('du: ')).length;
    final denied =
        !foundSelf &&
        stderrLines.any(
          (l) => l.contains('Permission denied') && l.contains("'$dir'"),
        );
    return DuResult(
      entries: entries,
      total: total,
      errors: errors,
      permissionDenied: denied,
    );
  }

  Future<Map<String, int>> sizesOf(
    List<String> paths, {
    CancelToken? cancel,
  }) async {
    if (paths.isEmpty) return {};
    _throwIfCancelled(cancel);
    final result = await _runner.run('du', [
      '-sx',
      '-B1',
      '-0',
      ...paths,
    ], cancel: cancel);
    return {for (final r in _records(result)) _normalize(r.path): r.bytes};
  }

  static void _throwIfCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const ScanCancelled();
  }

  static String _normalize(String path) => path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;

  static Iterable<({int bytes, String path})> _records(RunResult r) sync* {
    final text = utf8.decode(r.stdout, allowMalformed: true);
    for (final record in text.split('\x00')) {
      final tab = record.indexOf('\t');
      if (tab <= 0) continue;
      final bytes = int.tryParse(record.substring(0, tab).trim());
      if (bytes == null) continue;
      yield (bytes: bytes, path: record.substring(tab + 1));
    }
  }
}
