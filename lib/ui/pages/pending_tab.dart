import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../backup/backup_controller.dart';
import '../../backup/pending_store.dart';
import '../widgets/backup_widgets.dart';
import '../widgets/common.dart';
import '../widgets/conflict_review.dart';

const _newerOptions = [
  ConflictOption(PendingAction.later, 'Decidir depois'),
  ConflictOption(PendingAction.sendLocal, 'Enviar o do computador'),
  ConflictOption(PendingAction.bringFromDisk, 'Trazer o do disco'),
  ConflictOption(PendingAction.keepBoth, 'Manter os dois'),
];

const _deleteOptions = [
  ConflictOption(PendingAction.later, 'Decidir depois'),
  ConflictOption(PendingAction.deleteFromDisk, 'Apagar do disco'),
  ConflictOption(PendingAction.keepOnDisk, 'Manter no disco'),
];

class PendingTab extends StatefulWidget {
  const PendingTab({super.key, required this.controller});

  final BackupController controller;

  @override
  State<PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends State<PendingTab> {
  BackupController get c => widget.controller;
  final Map<String, PendingAction> _decisions = {};

  int get _chosen =>
      _decisions.values.where((a) => a != PendingAction.later).length;

  void _setAll(PendingKind kind, PendingAction action) => setState(() {
    for (final i in c.pending) {
      if (i.kind == kind) _decisions[i.key] = action;
    }
  });

  Future<void> _apply() async {
    final count = _chosen;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Symbols.rule_rounded),
        title: Text(
          count == 1 ? 'Aplicar 1 decisão?' : 'Aplicar $count decisões?',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            [
              if (_decisions.containsValue(PendingAction.deleteFromDisk))
                'O que você marcou para apagar sai do disco do backup e não '
                    'tem como desfazer.',
              'Os arquivos substituídos ficam guardados numa pasta à parte.',
            ].join(' '),
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await c.resolvePending(Map.of(_decisions));
    if (!mounted) return;
    setState(() {
      final left = {for (final i in c.pending) i.key};
      _decisions.removeWhere((k, _) => !left.contains(k));
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error ?? 'Decisões aplicadas.')));
  }

  Widget _section(
    String title,
    String description,
    PendingKind kind,
    List<ConflictOption<PendingAction>> options,
  ) {
    final items = [
      for (final i in c.pending)
        if (i.kind == kind) i,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final byKey = {for (final i in items) i.key: i};
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardTitle('$title (${items.length})', description),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Para todos:',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                for (final o in options.skip(1))
                  OutlinedButton(
                    onPressed: () => _setAll(kind, o.value),
                    child: Text(o.label),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ConflictReview<PendingAction>(
              conflicts: [for (final i in items) i.asConflict()],
              options: options,
              localLabel: 'No computador',
              backupLabel: 'No disco',
              actionOf: (x) => _decisions[x.path] ?? PendingAction.later,
              isOverridden: (x) =>
                  (_decisions[x.path] ?? PendingAction.later) !=
                  PendingAction.later,
              onChanged: (x, a) => setState(() {
                if (a == null || a == PendingAction.later) {
                  _decisions.remove(x.path);
                } else if (byKey.containsKey(x.path)) {
                  _decisions[x.path] = a;
                }
              }),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final idle = c.phase == BackupPhase.idle && !c.resolving;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: c.pending.isEmpty
                ? const EmptyState(
                    icon: Symbols.task_alt_rounded,
                    title: 'Nada pendente',
                    body:
                        'Quando um arquivo mudar no disco do backup, ou o '
                        'Espelhar for apagar algo de lá, ele aparece aqui '
                        'para você decidir.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      ContentWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (c.resolving) ...[
                              const LinearProgressIndicator(),
                              const SizedBox(height: 16),
                            ],
                            _section(
                              'Mais novos no disco',
                              'Foram alterados no disco do backup depois da '
                                  'versão do computador. O backup não os '
                                  'sobrescreveu.',
                              PendingKind.diskNewer,
                              _newerOptions,
                            ),
                            _section(
                              'Seriam apagados do disco',
                              'Você apagou do computador e o Espelhar ia '
                                  'apagar do backup. Eles continuam lá até '
                                  'você decidir.',
                              PendingKind.wouldDelete,
                              _deleteOptions,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (c.pending.isNotEmpty)
            BottomBar(
              children: [
                if (!idle && !c.resolving)
                  const Text('Espere o backup terminar.'),
                FilledButton(
                  onPressed: idle && _chosen > 0 ? _apply : null,
                  child: Text(
                    _chosen == 0
                        ? 'Aplicar'
                        : 'Aplicar $_chosen '
                              '${_chosen == 1 ? 'decisão' : 'decisões'}',
                  ),
                ),
              ],
            ),
        ],
      );
    },
  );
}
