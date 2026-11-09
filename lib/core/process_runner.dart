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

class Command {
  const Command(this.executable, this.args);

  final String executable;
  final List<String> args;

  @override
  String toString() => [executable, ...args].join(' ');
}

const notStarted = RunResult(-1, [], '');

abstract class ProcessRunner {
  Future<(RunResult, RunResult)> runPiped(
    Command producer,
    Command consumer, {
    CancelToken? cancel,
    Map<String, String>? environment,
  });

  Future<RunResult> run(
    String executable,
    List<String> args, {
    CancelToken? cancel,
  });

  Future<RunResult> runStreaming(
    String executable,
    List<String> args, {
    required void Function(String line) onLine,
    CancelToken? cancel,
    Map<String, String>? environment,
  });
}

class SystemProcessRunner implements ProcessRunner {
  SystemProcessRunner({this.termGrace = const Duration(seconds: 5)});

  final Duration termGrace;

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
    final cancelled = Completer<void>();
    void onCancel() {
      process.kill(ProcessSignal.sigkill);
      if (!cancelled.isCompleted) cancelled.complete();
    }

    final removeListener = cancel?.onCancel(onCancel);
    if (cancel?.isCancelled ?? false) onCancel();

    final out = <int>[];
    final err = <int>[];
    final outSub = process.stdout.listen(out.addAll);
    final errSub = process.stderr.listen(err.addAll);
    try {
      final code = Future.wait<void>([
        process.exitCode,
        outSub.asFuture<void>(),
        errSub.asFuture<void>(),
      ]);
      await Future.any<void>([code, cancelled.future]);
      if (cancelled.isCompleted) throw const ScanCancelled();
      return RunResult(
        await process.exitCode,
        out,
        utf8.decode(err, allowMalformed: true),
      );
    } finally {
      removeListener?.call();
      if (cancelled.isCompleted) {
        unawaited(outSub.cancel());
        unawaited(errSub.cancel());
      }
    }
  }

  @override
  Future<RunResult> runStreaming(
    String executable,
    List<String> args, {
    required void Function(String line) onLine,
    CancelToken? cancel,
    Map<String, String>? environment,
  }) async {
    if (cancel?.isCancelled ?? false) throw const ScanCancelled();
    final Process process;
    try {
      process = await Process.start(executable, args, environment: environment);
    } on ProcessException catch (e) {
      return RunResult(127, const [], e.message);
    }
    final cancelled = Completer<void>();
    void onCancel() {
      if (!cancelled.isCompleted) cancelled.complete();
    }

    final removeListener = cancel?.onCancel(onCancel);
    if (cancel?.isCancelled ?? false) onCancel();

    final err = <int>[];
    final outSub = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (line.isNotEmpty && !cancelled.isCompleted) onLine(line);
        });
    final errSub = process.stderr.listen(err.addAll);
    try {
      final done = Future.wait<void>([
        process.exitCode,
        outSub.asFuture<void>(),
        errSub.asFuture<void>(),
      ]);
      await Future.any<void>([done, cancelled.future]);
      if (cancelled.isCompleted) {
        await _terminate(process);
        throw const ScanCancelled();
      }
      return RunResult(
        await process.exitCode,
        const [],
        utf8.decode(err, allowMalformed: true),
      );
    } finally {
      removeListener?.call();
      if (cancelled.isCompleted) {
        unawaited(outSub.cancel());
        unawaited(errSub.cancel());
      }
    }
  }

  @override
  Future<(RunResult, RunResult)> runPiped(
    Command producer,
    Command consumer, {
    CancelToken? cancel,
    Map<String, String>? environment,
  }) async {
    if (cancel?.isCancelled ?? false) throw const ScanCancelled();
    final Process first;
    try {
      first = await Process.start(
        producer.executable,
        producer.args,
        environment: environment,
      );
    } on ProcessException catch (e) {
      return (RunResult(127, const [], e.message), notStarted);
    }
    final Process second;
    try {
      second = await Process.start(
        consumer.executable,
        consumer.args,
        environment: environment,
      );
    } on ProcessException catch (e) {
      first.kill(ProcessSignal.sigkill);
      await first.exitCode;
      return (notStarted, RunResult(127, const [], e.message));
    }

    final cancelled = Completer<void>();
    void onCancel() {
      if (!cancelled.isCompleted) cancelled.complete();
    }

    final removeListener = cancel?.onCancel(onCancel);
    if (cancel?.isCancelled ?? false) onCancel();

    unawaited(second.stdin.done.catchError((Object _) {}));
    unawaited(first.stdout.pipe(second.stdin).catchError((Object _) {}));
    unawaited(
      second.exitCode.then((code) {
        if (code != 0) first.kill(ProcessSignal.sigterm);
      }),
    );

    final firstErr = <int>[];
    final secondErr = <int>[];
    final secondOut = <int>[];
    final subs = [
      first.stderr.listen(firstErr.addAll),
      second.stderr.listen(secondErr.addAll),
      second.stdout.listen(secondOut.addAll),
    ];
    try {
      final exits = Future.wait([first.exitCode, second.exitCode]);
      await Future.any<void>([exits, cancelled.future]);
      if (cancelled.isCompleted) {
        await Future.wait([_terminate(first), _terminate(second)]);
        throw const ScanCancelled();
      }
      await Future.wait([for (final s in subs) s.asFuture<void>()])
          .timeout(const Duration(seconds: 2), onTimeout: () => const []);
      return (
        RunResult(
          await first.exitCode,
          const [],
          utf8.decode(firstErr, allowMalformed: true),
        ),
        RunResult(
          await second.exitCode,
          secondOut,
          utf8.decode(secondErr, allowMalformed: true),
        ),
      );
    } finally {
      removeListener?.call();
      for (final s in subs) {
        unawaited(s.cancel());
      }
    }
  }

  Future<void> _terminate(Process process) async {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(termGrace);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }
}
