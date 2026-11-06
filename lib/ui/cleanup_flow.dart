import 'package:flutter/material.dart';

import '../cleanup/cleanup_controller.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../scan/scan_controller.dart';
import 'widgets/cleanup_widgets.dart';

class CleanupFlow {
  const CleanupFlow({required this.scan, required this.cleanup});

  final ScanController scan;
  final CleanupController cleanup;

  Future<CleanupResult?> run(
    BuildContext context,
    List<CleanupItem> items, {
    bool offerPermanent = false,
    bool initialPermanent = false,
    VoidCallback? onUndone,
  }) async {
    if (items.isEmpty) return null;
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
    final result = await cleanup.execute(toRun);
    scan.removeItems(result.doneIds);
    if (!context.mounted) return result;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(_message(result)),
        action: result.undo.isEmpty
            ? null
            : SnackBarAction(
                label: 'Desfazer',
                onPressed: () async {
                  await cleanup.undo(result.undo);
                  onUndone?.call();
                },
              ),
      ),
    );
    return result;
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
      lastModified: i.lastModified,
      action: DeletePathsAction(paths),
    ),
    _ => i,
  };
}
