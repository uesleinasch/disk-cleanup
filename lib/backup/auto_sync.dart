import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/backup_settings.dart';
import 'backup_controller.dart';
import 'mount_watcher.dart';

enum AutoSyncTrigger { connect, interval }

class AutoSyncRun {
  const AutoSyncRun({
    required this.trigger,
    required this.startedAt,
    this.outcome,
    this.disk,
  });

  final AutoSyncTrigger trigger;
  final DateTime startedAt;
  final BackupStepStatus? outcome;
  final String? disk;

  bool get running => outcome == null;
}

const kAutoSyncIntervals = [0, 1, 6, 12, 24, 168];

bool autoSyncDue(BackupSettings s, DateTime now, {DateTime? lastAttempt}) {
  if (s.autoSyncHours <= 0) return false;
  final every = Duration(hours: s.autoSyncHours);
  final last = s.lastBackupAt;
  if (last != null && now.difference(last) < every) return false;
  if (lastAttempt != null && now.difference(lastAttempt) < every) return false;
  return true;
}

class AutoSyncScheduler extends ChangeNotifier {
  AutoSyncScheduler({
    required this.backup,
    this.watcher,
    DateTime Function()? now,
    this.pollInterval = const Duration(minutes: 1),
    this.connectDelay = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now;

  final BackupController backup;
  final MountWatcher? watcher;
  final DateTime Function() _now;
  final Duration pollInterval;
  final Duration connectDelay;

  Timer? _timer;
  Timer? _delayed;
  StreamSubscription<MountEvent>? _sub;
  bool? _connected;
  DateTime? _lastAttempt;
  bool _checking = false;

  AutoSyncRun? last;

  BackupSettings get _config => backup.config;

  bool get enabled => _config.autoSyncOnConnect || _config.autoSyncHours > 0;

  void start() {
    _sub ??= watcher?.events.listen((e) {
      if (e.action == MountAction.other) return;
      _delayed?.cancel();
      _delayed = Timer(connectDelay, check);
    });
    watcher?.start();
    _timer ??= Timer.periodic(pollInterval, (_) => check());
    unawaited(check());
  }

  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      final target = _config.target;
      final dest = target == null
          ? null
          : await backup.services.backup.disks.resolve(target);
      final connected = dest != null;
      final arrived = connected && _connected == false;
      _connected = connected;
      if (!connected || !enabled) return;
      final now = _now();
      final AutoSyncTrigger trigger;
      if (arrived && _config.autoSyncOnConnect) {
        trigger = AutoSyncTrigger.connect;
      } else if (autoSyncDue(_config, now, lastAttempt: _lastAttempt)) {
        trigger = AutoSyncTrigger.interval;
      } else {
        return;
      }
      await _run(trigger, now);
    } finally {
      _checking = false;
    }
  }

  Future<void> _run(AutoSyncTrigger trigger, DateTime now) async {
    if (backup.phase != BackupPhase.idle || backup.busyElsewhere) return;
    await backup.refresh();
    if (!backup.canRun) return;
    _lastAttempt = now;
    final disk = backup.config.target?.label;
    last = AutoSyncRun(trigger: trigger, startedAt: now, disk: disk);
    notifyListeners();
    await backup.start(auto: true);
    final outcome = backup.outcome;
    last = AutoSyncRun(
      trigger: trigger,
      startedAt: now,
      outcome: outcome,
      disk: disk,
    );
    if (outcome != BackupStepStatus.failed &&
        backup.phase == BackupPhase.finished) {
      await backup.dismiss();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _delayed?.cancel();
    _sub?.cancel();
    watcher?.stop();
    super.dispose();
  }
}
