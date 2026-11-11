import '../core/process_runner.dart';
import 'backup_planner.dart';

class RsyncProgress {
  const RsyncProgress({
    required this.bytes,
    required this.percent,
    required this.bytesPerSecond,
    required this.remaining,
  });

  final int bytes;
  final int percent;
  final int bytesPerSecond;
  final Duration remaining;
}

const _rateUnits = {
  'B': 1,
  'kB': 1024,
  'MB': 1024 * 1024,
  'GB': 1024 * 1024 * 1024,
  'TB': 1024 * 1024 * 1024 * 1024,
};

final _progress = RegExp(
  r'^\s*([\d,]+)\s+(\d{1,3})%\s+([\d.]+)([kMGT]?B)/s\s+(\d+):(\d{2}):(\d{2})',
);

RsyncProgress? parseRsyncProgress(String line) {
  final m = _progress.firstMatch(line);
  if (m == null) return null;
  return RsyncProgress(
    bytes: int.parse(m[1]!.replaceAll(',', '')),
    percent: int.parse(m[2]!),
    bytesPerSecond: (double.parse(m[3]!) * _rateUnits[m[4]!]!).round(),
    remaining: Duration(
      hours: int.parse(m[5]!),
      minutes: int.parse(m[6]!),
      seconds: int.parse(m[7]!),
    ),
  );
}

enum RsyncOutcome { ok, warnings, failed }

class RsyncResult {
  const RsyncResult(
    this.outcome, {
    this.stats,
    this.warnings = const [],
    this.error,
  });

  final RsyncOutcome outcome;
  final RsyncStats? stats;
  final List<String> warnings;
  final String? error;
}

const _maxWarnings = 500;

RsyncResult interpretRsync(RunResult r, Iterable<String> stdoutLines) {
  final stats = RsyncStats.parse(stdoutLines);
  final stderr = [
    for (final line in r.stderr.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  switch (r.exitCode) {
    case 0:
      return RsyncResult(RsyncOutcome.ok, stats: stats);
    case 23 || 24:
      return RsyncResult(
        RsyncOutcome.warnings,
        stats: stats,
        warnings: stderr
            .where((l) => !l.startsWith('rsync error:'))
            .take(_maxWarnings)
            .toList(),
      );
    case 127:
      return const RsyncResult(
        RsyncOutcome.failed,
        error: 'O rsync não está instalado. Instale o pacote rsync.',
      );
    default:
      final tail = stderr.length > 3
          ? stderr.sublist(stderr.length - 3)
          : stderr;
      return RsyncResult(
        RsyncOutcome.failed,
        stats: stats,
        error: tail.isEmpty
            ? 'O rsync terminou com o código ${r.exitCode}.'
            : tail.join('\n'),
      );
  }
}

class RsyncRunner {
  RsyncRunner(this._runner);

  final ProcessRunner _runner;

  ProcessRunner get runner => _runner;

  Future<RsyncResult> run(
    List<String> args, {
    void Function(RsyncProgress)? onProgress,
    CancelToken? cancel,
  }) async {
    final lines = <String>[];
    final r = await _runner.runStreaming(
      'rsync',
      args,
      onLine: (line) {
        final progress = parseRsyncProgress(line);
        if (progress == null) {
          lines.add(line);
        } else {
          onProgress?.call(progress);
        }
      },
      environment: const {'LC_ALL': 'C'},
      cancel: cancel,
    );
    return interpretRsync(r, lines);
  }

  Future<RsyncResult> copy({
    required String filterFile,
    required List<String> sources,
    required String destination,
    bool mirror = false,
    void Function(RsyncProgress)? onProgress,
    CancelToken? cancel,
  }) => run(
    backupRsyncArgs(
      filterFile: filterFile,
      sources: sources,
      destination: destination,
      mirror: mirror,
    ),
    onProgress: onProgress,
    cancel: cancel,
  );
}
