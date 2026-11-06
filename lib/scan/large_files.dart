import '../core/process_runner.dart';
import 'build_finder.dart' show findPathLiteral;

class LargeFile {
  const LargeFile({
    required this.path,
    required this.bytes,
    required this.lastAccess,
    required this.modified,
  });

  final String path;
  final int bytes;
  final DateTime lastAccess;
  final DateTime modified;
}

class LargeFileFinder {
  LargeFileFinder(this._runner);

  final ProcessRunner _runner;

  Future<List<LargeFile>> find(
    List<String> roots, {
    int minBytes = 1000000000,
    List<String> excludeRoots = const [],
    CancelToken? cancel,
  }) async {
    if (roots.isEmpty) return [];
    final result = await _runner.run('find', [
      ...roots,
      '-xdev',
      if (excludeRoots.isNotEmpty) ...[
        '(',
        for (var i = 0; i < excludeRoots.length; i++) ...[
          if (i > 0) '-o',
          '-path',
          findPathLiteral(excludeRoots[i]),
        ],
        ')',
        '-prune',
        '-o',
      ],
      '-type',
      'f',
      '-size',
      '+${minBytes - 1}c',
      '-printf',
      r'%s\t%A@\t%T@\t%p\0',
    ], cancel: cancel);

    final byPath = <String, LargeFile>{};
    for (final record in result.stdoutText.split('\x00')) {
      final file = _parse(record);
      if (file != null) byPath[file.path] = file;
    }
    return byPath.values.toList()..sort((a, b) => b.bytes.compareTo(a.bytes));
  }

  static LargeFile? _parse(String record) {
    if (record.isEmpty) return null;
    final first = record.indexOf('\t');
    if (first < 0) return null;
    final second = record.indexOf('\t', first + 1);
    if (second < 0) return null;
    final third = record.indexOf('\t', second + 1);
    if (third < 0) return null;
    final bytes = int.tryParse(record.substring(0, first));
    final access = double.tryParse(record.substring(first + 1, second));
    final modified = double.tryParse(record.substring(second + 1, third));
    final path = record.substring(third + 1);
    if (bytes == null || access == null || modified == null || path.isEmpty) {
      return null;
    }
    return LargeFile(
      path: path,
      bytes: bytes,
      lastAccess: _fromEpoch(access),
      modified: _fromEpoch(modified),
    );
  }

  static DateTime _fromEpoch(double seconds) =>
      DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}
