import 'package:disk_cleanup/core/process_runner.dart';

class FakeProcessRunner implements ProcessRunner {
  final _responses = <String, RunResult>{};
  final calls = <List<String>>[];

  static String _key(String exe, List<String> args) =>
      [exe, ...args].join('\u0000');

  void when(String exe, List<String> args, RunResult result) {
    _responses[_key(exe, args)] = result;
  }

  @override
  Future<RunResult> run(
    String executable,
    List<String> args, {
    CancelToken? cancel,
  }) async {
    calls.add([executable, ...args]);
    final r = _responses[_key(executable, args)];
    if (r == null) {
      throw StateError(
        'Comando inesperado: ${[executable, ...args].join(' ')}',
      );
    }
    return r;
  }
}
