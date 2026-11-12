import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../scan/project_activity.dart';
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

class UndoResult {
  const UndoResult({required this.restored, required this.failed});

  final int restored;
  final int failed;
}

class _Missing implements Exception {
  const _Missing();
}

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

    final rootItems = <CleanupItem>[];
    final commands = <RootCommand>[];
    final owner = <int>[];
    final handledAsRoot = <CleanupItem>{};
    for (final item in pending.where(_runsAsRoot)) {
      handledAsRoot.add(item);
      final List<RootCommand> itemCommands;
      try {
        itemCommands = switch (item.action) {
          RootAction(:final commands) => commands,
          DockerAction(:final op, :final ids) => [DockerCli(op, ids)],
          _ => const [],
        };
      } on ArgumentError {
        failed++;
        continue;
      }
      final k = rootItems.length;
      rootItems.add(item);
      for (final c in itemCommands) {
        commands.add(c);
        owner.add(k);
      }
    }
    if (rootItems.isNotEmpty) {
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
      if (handledAsRoot.contains(item)) continue;
      try {
        if (await _runItem(item, deleter, undo)) {
          done.add(item);
        } else {
          failed++;
        }
      } on _Missing {
        skipped++;
      } on Object {
        failed++;
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

  static bool _runsAsRoot(CleanupItem item) =>
      item.action is RootAction ||
      (item.action is DockerAction && item.requiresRoot);

  Future<bool> _runItem(
    CleanupItem item,
    SafeDeleter deleter,
    List<TrashedEntry> undo,
  ) async {
    switch (item.action) {
      case RootAction():
        return false;
      case DockerAction(:final op, :final ids):
        return services.docker.execute(op, ids);
      case EmptyTrashAction():
        return await services.trash.empty() == 0;
      case TrashPathsAction(:final paths):
        var ok = true;
        for (final path in paths) {
          if (!await deleter.canRemove(path)) {
            ok = false;
            continue;
          }
          try {
            final entry = await services.trash.moveToTrash(path);
            if (entry != null) undo.add(entry);
          } on FileSystemException {
            ok = false;
          }
        }
        return ok;
      case DeletePathsAction(:final paths):
        final outcomes = [for (final path in paths) await deleter.delete(path)];
        if (outcomes.every((o) => o == DeleteOutcome.missing)) {
          throw const _Missing();
        }
        return !outcomes.any(
          (o) => o == DeleteOutcome.refused || o == DeleteOutcome.failed,
        );
    }
  }

  Future<UndoResult> undo(List<TrashedEntry> entries) async {
    var restored = 0;
    var failed = 0;
    for (final e in entries) {
      try {
        await services.trash.restore(e);
        restored++;
      } on Object {
        failed++;
      }
    }
    return UndoResult(restored: restored, failed: failed);
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

DateTime? projectModifiedNow(String artifactPath, List<BuildRule> rules) =>
    newestProjectModification(
      p.dirname(artifactPath),
      extraPruned: rules.map((r) => r.dirName),
    );
