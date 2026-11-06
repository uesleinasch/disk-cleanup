import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RunResult {
  const RunResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final List<int> stdout;
  final String stderr;

  String get stdoutText => utf8.decode(stdout, allowMalformed: true);
}

class ScanCancelled implements Exception {
  const ScanCancelled();

  @override
  String toString() => 'ScanCancelled';
}

class CancelToken {
  final _listeners = <void Function()>[];
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void Function() onCancel(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

abstract class ProcessRunner {
  Future<RunResult> run(
    String executable,
    List<String> args, {
    CancelToken? cancel,
  });
}

class SystemProcessRunner implements ProcessRunner {
  @override
  Future<RunResult> run(
    String executable,
    List<String> args, {
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw const ScanCancelled();
    final Process process;
    try {
      process = await Process.start(executable, args);
    } on ProcessException catch (e) {
      return RunResult(127, const [], e.message);
    }
    final removeListener = cancel?.onCancel(
      () => process.kill(ProcessSignal.sigkill),
    );
    try {
      final out = <int>[];
      final outDone = process.stdout.forEach(out.addAll);
      final errFuture = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode;
      await outDone;
      final err = await errFuture;
      if (cancel?.isCancelled ?? false) throw const ScanCancelled();
      return RunResult(code, out, err);
    } finally {
      removeListener?.call();
    }
  }
}
