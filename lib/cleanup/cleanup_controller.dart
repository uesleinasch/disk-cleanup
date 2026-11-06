import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../services.dart';
import '../settings/settings.dart';
import 'privileged_runner.dart';
import 'safe_deleter.dart';
import 'trash_service.dart';

class CleanupResult {
  const CleanupResult({
    this.freedBytes = 0,
    this.succeeded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.cancelled = false,
    this.undo = const [],
    this.doneIds = const [],
  });

  final int freedBytes;
  final int succeeded;
  final int skipped;
  final int failed;
  final bool cancelled;
  final List<TrashedEntry> undo;
  final List<String> doneIds;
}

RiskLevel highestRisk(List<CleanupItem> items) => items.fold(
  RiskLevel.safe,
  (worst, i) => i.risk.index > worst.index ? i.risk : worst,
);

bool batchNeedsRoot(List<CleanupItem> items) =>
    items.any((i) => i.requiresRoot);

class CleanupController {
  CleanupController(this.services);

  final Services services;

  Future<CleanupResult> execute(List<CleanupItem> items) async {
    final settings = await services.settingsStore.load(services.home);
    final now = services.now();
    var skipped = 0;
    final pending = <CleanupItem>[];
    for (final item in items) {
      if (_stillValid(item, settings, now)) {
        pending.add(item);
      } else {
        skipped++;
      }
    }

    final done = <CleanupItem>[];
    var failed = 0;

    final rootItems = [
      for (final i in pending)
        if (i.action is RootAction) i,
    ];
    if (rootItems.isNotEmpty) {
      final commands = <RootCommand>[];
      final owner = <int>[];
      for (var k = 0; k < rootItems.length; k++) {
        for (final c in (rootItems[k].action as RootAction).commands) {
          commands.add(c);
          owner.add(k);
        }
      }
      final batch = await services.root.run(commands);
      if (batch.cancelled) {
        return CleanupResult(cancelled: true, skipped: skipped);
      }
      final ok = List.filled(rootItems.length, true);
      for (var i = 0; i < commands.length; i++) {
        if (batch.exitCodes[i] != 0) ok[owner[i]] = false;
      }
      for (var k = 0; k < rootItems.length; k++) {
        ok[k] ? done.add(rootItems[k]) : failed++;
      }
    }

    final deleter = services.deleter(settings);
    final undo = <TrashedEntry>[];
    for (final item in pending) {
      switch (item.action) {
        case RootAction():
          break;
        case DockerAction(:final op, :final ids):
          (await services.docker.execute(op, ids)) ? done.add(item) : failed++;
        case EmptyTrashAction():
          await services.trash.empty();
          done.add(item);
        case TrashPathsAction(:final paths):
          var ok = true;
          for (final path in paths) {
            try {
              final entry = await services.trash.moveToTrash(path);
              if (entry != null) undo.add(entry);
            } on FileSystemException {
              ok = false;
            }
          }
          ok ? done.add(item) : failed++;
        case DeletePathsAction(:final paths):
          final outcomes = [
            for (final path in paths) await deleter.delete(path),
          ];
          if (outcomes.every((o) => o == DeleteOutcome.missing)) {
            skipped++;
          } else if (outcomes.any(
            (o) => o == DeleteOutcome.refused || o == DeleteOutcome.failed,
          )) {
            failed++;
          } else {
            done.add(item);
          }
      }
    }

    return CleanupResult(
      freedBytes: done.fold(0, (a, i) => a + i.bytes),
      succeeded: done.length,
      skipped: skipped,
      failed: failed,
      undo: undo,
      doneIds: [for (final i in done) i.id],
    );
  }

  Future<void> undo(List<TrashedEntry> entries) async {
    for (final e in entries) {
      await services.trash.restore(e);
    }
  }

  bool _stillValid(CleanupItem item, Settings s, DateTime now) {
    final action = item.action;
    final firstPath = switch (action) {
      DeletePathsAction(:final paths) => paths.firstOrNull,
      TrashPathsAction(:final paths) => paths.firstOrNull,
      _ => null,
    };
    if (firstPath != null &&
        FileSystemEntity.typeSync(firstPath, followLinks: false) ==
            FileSystemEntityType.notFound) {
      return false;
    }
    if (item.category == CleanupCategory.build &&
        s.protectActiveProjects &&
        firstPath != null) {
      final modified = projectModifiedNow(firstPath, s.buildRules);
      if (modified != null &&
          now.difference(modified) <= Duration(days: s.activeProjectDays)) {
        return false;
      }
    }
    return true;
  }
}

DateTime? projectModifiedNow(String artifactPath, List<BuildRule> rules) {
  final projectDir = Directory(p.dirname(artifactPath));
  final names = rules.map((r) => r.dirName).toSet();
  DateTime? newest;
  try {
    for (final e in projectDir.listSync(followLinks: false)) {
      if (names.contains(p.basename(e.path))) continue;
      final m = e.statSync().modified;
      if (newest == null || m.isAfter(newest)) newest = m;
    }
  } on FileSystemException {
    return null;
  }
  return newest;
}
