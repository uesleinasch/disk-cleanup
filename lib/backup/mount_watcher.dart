import 'dart:async';

import '../core/process_runner.dart';

enum MountAction { mount, umount, other }

class MountEvent {
  const MountEvent(this.action, this.target);

  final MountAction action;
  final String target;
}

final _hexEscape = RegExp(r'\\x([0-9a-fA-F]{2})');

MountEvent? parseFindmntPoll(String line) {
  final space = line.indexOf(' ');
  if (space <= 0) return null;
  final action = switch (line.substring(0, space)) {
    'mount' => MountAction.mount,
    'umount' => MountAction.umount,
    _ => MountAction.other,
  };
  final target = line
      .substring(space + 1)
      .replaceAllMapped(
        _hexEscape,
        (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
      );
  return MountEvent(action, target);
}

class MountWatcher {
  MountWatcher(
    this._runner, {
    this.restartDelay = const Duration(seconds: 5),
    this.maxRestartDelay = const Duration(minutes: 5),
  });

  final ProcessRunner _runner;
  final Duration restartDelay;
  final Duration maxRestartDelay;

  final _events = StreamController<MountEvent>.broadcast();
  CancelToken? _cancel;
  bool _running = false;

  Stream<MountEvent> get events => _events.stream;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_loop());
  }

  Future<void> _loop() async {
    var delay = restartDelay;
    while (_running) {
      final cancel = _cancel = CancelToken();
      final started = DateTime.now();
      try {
        final r = await _runner.runStreaming(
          'findmnt',
          const ['--poll', '-n', '-r', '-o', 'ACTION,TARGET'],
          onLine: (line) {
            final e = parseFindmntPoll(line);
            if (e != null && !_events.isClosed) _events.add(e);
          },
          cancel: cancel,
        );
        if (r.exitCode == 127) return;
      } on ScanCancelled {
        return;
      }
      if (!_running) return;
      delay = DateTime.now().difference(started) > maxRestartDelay
          ? restartDelay
          : delay * 2 > maxRestartDelay
          ? maxRestartDelay
          : delay * 2;
      await Future<void>.delayed(delay);
    }
  }

  void stop() {
    _running = false;
    _cancel?.cancel();
  }

  Future<void> dispose() async {
    stop();
    await _events.close();
  }
}
