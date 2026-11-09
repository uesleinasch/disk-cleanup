import 'package:disk_cleanup/core/process_runner.dart';

class FakeProcessRunner implements ProcessRunner {
  final _responses = <String, RunResult>{};
  final _streams = <String, ({List<String> lines, RunResult result})>{};
  final calls = <List<String>>[];
  final environments = <Map<String, String>?>[];

  static String _key(String exe, List<String> args) =>
      [exe, ...args].join('\u0000');

  void when(String exe, List<String> args, RunResult result) {
    _responses[_key(exe, args)] = result;
  }

  void whenStreaming(
    String exe,
    List<String> args, {
    List<String> lines = const [],
    RunResult result = const RunResult(0, [], ''),
  }) {
    _streams[_key(exe, args)] = (lines: lines, result: result);
  }

  @override
  Future<RunResult> run(
    String executable,
    List<String> args, {
    CancelToken? cancel,
  }) async {
    calls.add([executable, ...args]);
    final r = _responses[_key(executable, args)];
    if (r == null) throw _unexpected(executable, args);
    return r;
  }

  @override
  Future<RunResult> runStreaming(
    String executable,
    List<String> args, {
    required void Function(String line) onLine,
    CancelToken? cancel,
    Map<String, String>? environment,
  }) async {
    calls.add([executable, ...args]);
    environments.add(environment);
    final s = _streams[_key(executable, args)];
    if (s == null) throw _unexpected(executable, args);
    for (final line in s.lines) {
      if (cancel?.isCancelled ?? false) throw const ScanCancelled();
      onLine(line);
      await Future<void>.delayed(Duration.zero);
    }
    if (cancel?.isCancelled ?? false) throw const ScanCancelled();
    return s.result;
  }

  static StateError _unexpected(String exe, List<String> args) =>
      StateError('Comando inesperado: ${[exe, ...args].join(' ')}');
}
