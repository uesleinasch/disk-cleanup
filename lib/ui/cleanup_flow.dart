import 'package:flutter/material.dart';

import '../cleanup/cleanup_controller.dart';
import '../cleanup/trash_service.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../scan/scan_controller.dart';
import 'widgets/cleanup_widgets.dart';

const _filePrefix = 'file:';

class CleanupFlow extends ChangeNotifier {
  CleanupFlow({required this.scan, required this.cleanup});

  final ScanController scan;
  final CleanupController cleanup;

  bool _busy = false;
  final Set<String> _removedFiles = {};
  DateTime? _removedAt;

  bool get busy => _busy;

  bool get canClean => !_busy && !scan.running;

  Set<String> get removedFiles =>
      _removedAt == scan.state.updatedAt ? _removedFiles : const {};

  Future<CleanupResult?> run(
    BuildContext context,
    List<CleanupItem> items, {
    bool offerPermanent = false,
    bool initialPermanent = false,
  }) async {
    if (items.isEmpty || !canClean) return null;
    final messenger = ScaffoldMessenger.of(context);
    _setBusy(true);
    try {
      final decision = await showCleanupConfirmDialog(
        context,
        items: items,
        offerPermanent: offerPermanent,
        initialPermanent: initialPermanent,
      );
      if (decision == null) return null;
      final toRun = decision.permanent
          ? [for (final i in items) _asPermanent(i)]
          : items;
      final CleanupResult result;
      try {
        result = await cleanup.execute(toRun);
      } on Object catch (e) {
        debugPrint('Falha na limpeza: $e');
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('A limpeza falhou. Nada mais foi apagado.'),
            ),
          );
        return null;
      }
      _markRemovedFiles(result.doneIds);
      scan.removeItems(result.doneIds);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_message(result)),
            action: result.undo.isEmpty
                ? null
                : SnackBarAction(
                    label: 'Desfazer',
                    onPressed: () => _undo(messenger, result.undo),
                  ),
          ),
        );
      return result;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _undo(
    ScaffoldMessengerState messenger,
    List<TrashedEntry> entries,
  ) async {
    var restored = 0;
    var failed = 0;
    for (final e in entries) {
      UndoResult r;
      try {
        r = await cleanup.undo([e]);
      } on Object {
        r = const UndoResult(restored: 0, failed: 1);
      }
      restored += r.restored;
      failed += r.failed;
      if (r.failed == 0 && _removedFiles.remove(e.originalPath)) {
        notifyListeners();
      }
    }
    if (failed == 0) return;
    if (!messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(undoMessage(restored, failed))));
  }

  static String undoMessage(int restored, int failed) {
    final r = restored == 1 ? '1 restaurado' : '$restored restaurados';
    final f = failed == 1 ? '1 não pôde voltar' : '$failed não puderam voltar';
    return '$r, $f.';
  }

  void _markRemovedFiles(List<String> doneIds) {
    final paths = [
      for (final id in doneIds)
        if (id.startsWith(_filePrefix)) id.substring(_filePrefix.length),
    ];
    if (paths.isEmpty) return;
    if (_removedAt != scan.state.updatedAt) {
      _removedFiles.clear();
      _removedAt = scan.state.updatedAt;
    }
    _removedFiles.addAll(paths);
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  static String _message(CleanupResult r) {
    if (r.cancelled) return 'Senha não informada. Nada foi apagado.';
    final parts = <String>[];
    if (r.undo.isNotEmpty) {
      parts.add(
        '${r.succeeded} arquivos movidos para a lixeira '
        '(${formatBytes(r.freedBytes)}).',
      );
    } else {
      parts.add('${formatBytes(r.freedBytes)} liberados.');
    }
    if (r.skipped > 0) parts.add('${r.skipped} ignorados por terem mudado.');
    if (r.failed > 0) parts.add('${r.failed} falharam.');
    return parts.join(' ');
  }

  static CleanupItem _asPermanent(CleanupItem i) => switch (i.action) {
    TrashPathsAction(:final paths) => CleanupItem(
      id: i.id,
      category: i.category,
      title: i.title,
      path: i.path,
      note: i.note,
      bytes: i.bytes,
      risk: i.risk,
      requiresRoot: i.requiresRoot,
      preselected: i.preselected,
      sizeUnknown: i.sizeUnknown,
      lastModified: i.lastModified,
      action: DeletePathsAction(paths),
    ),
    _ => i,
  };
}
