import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cleanup/cleanup_controller.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../theme/severity_colors.dart';
import 'common.dart';
import 'risk_chip.dart';

IconData categoryIcon(CleanupCategory c) => switch (c) {
  CleanupCategory.trash => Symbols.delete_rounded,
  CleanupCategory.cache => Symbols.cached_rounded,
  CleanupCategory.build => Symbols.build_rounded,
  CleanupCategory.system => Symbols.receipt_long_rounded,
  CleanupCategory.docker => Symbols.deployed_code_rounded,
  CleanupCategory.largeFile => Symbols.draft_rounded,
};

String itemSizeLabel(CleanupItem i) =>
    i.sizeUnknown ? 'Desconhecido' : formatBytes(i.bytes);

String? totalSizeLabel(Iterable<CleanupItem> items) {
  final known = items.fold(0, (a, i) => i.sizeUnknown ? a : a + i.bytes);
  if (!items.any((i) => i.sizeUnknown)) return formatBytes(known);
  return known == 0 ? null : 'pelo menos ${formatBytes(known)}';
}

String withSize(String verb, String? size) =>
    size == null ? verb : '$verb $size';

class CleanupItemTile extends StatelessWidget {
  const CleanupItemTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onChanged,
    this.trailingNote,
  });

  final CleanupItem item;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final String? trailingNote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.06)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (v) => onChanged(v ?? false),
                semanticLabel: 'Selecionar ${item.title}',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Icon(
                          categoryIcon(item.category),
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                        Text(item.title, style: text.labelLarge),
                        if (item.requiresRoot) const RootRequiredIndicator(),
                      ],
                    ),
                    if (item.path != null)
                      Tooltip(
                        message: item.path!,
                        child: Text(
                          item.path!,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            fontFamily: kMono,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (item.note.isNotEmpty)
                      Text(
                        item.note,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              RiskChip(level: item.risk),
              const SizedBox(width: 12),
              SizedBox(
                width: item.sizeUnknown ? null : 84,
                child: Tooltip(
                  message: item.sizeUnknown
                      ? 'Sem permissão de leitura'
                      : formatBytesExact(item.bytes),
                  child: item.sizeUnknown
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.lock_rounded,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              itemSizeLabel(item),
                              style: text.labelLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          formatBytes(item.bytes),
                          textAlign: TextAlign.right,
                          style: text.labelLarge?.copyWith(
                            fontFeatures: kTabular,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class CleanupSummaryBar extends StatelessWidget {
  const CleanupSummaryBar({
    super.key,
    required this.count,
    required this.size,
    required this.risk,
    required this.onClean,
    this.onClearSelection,
    this.labelOverride,
    this.extraActions = const [],
  });

  final int count;
  final String? size;
  final RiskLevel risk;
  final VoidCallback? onClean;
  final VoidCallback? onClearSelection;
  final String? labelOverride;
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = risk == RiskLevel.danger;
    final label = labelOverride ?? withSize(danger ? 'Apagar' : 'Limpar', size);
    final summary = size == null
        ? '$count selecionados · tamanho desconhecido'
        : '$count selecionados · $size serão liberados';
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Text(
              summary,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontFeatures: kTabular),
            ),
          ),
          if (onClearSelection != null)
            TextButton(
              onPressed: count == 0 ? null : onClearSelection,
              child: const Text('Limpar seleção'),
            ),
          ...extraActions,
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: count == 0 ? null : onClean,
            child: Text(label),
          ),
        ],
      ),
    );
  }
}

class CleanupDecision {
  const CleanupDecision({required this.permanent});

  final bool permanent;
}

String? dockerWarning(CleanupItem i) => switch (i.action) {
  DockerAction(op: DockerOp.removeContainers) =>
    'Dados gravados dentro dos containers e fora de volumes serão perdidos.',
  DockerAction(op: DockerOp.removeImages) =>
    'Imagens construídas localmente precisarão de um novo build.',
  DockerAction(op: DockerOp.removeVolumes) =>
    'Volumes podem conter dados de banco que não existem em outro lugar.',
  _ => null,
};

Future<CleanupDecision?> showCleanupConfirmDialog(
  BuildContext context, {
  required List<CleanupItem> items,
  bool offerPermanent = false,
  bool initialPermanent = false,
}) {
  return showDialog<CleanupDecision>(
    context: context,
    builder: (context) => _CleanupConfirmDialog(
      items: items,
      offerPermanent: offerPermanent,
      initialPermanent: initialPermanent,
    ),
  );
}

class _CleanupConfirmDialog extends StatefulWidget {
  const _CleanupConfirmDialog({
    required this.items,
    required this.offerPermanent,
    required this.initialPermanent,
  });

  final List<CleanupItem> items;
  final bool offerPermanent;
  final bool initialPermanent;

  @override
  State<_CleanupConfirmDialog> createState() => _CleanupConfirmDialogState();
}

class _CleanupConfirmDialogState extends State<_CleanupConfirmDialog> {
  late bool _permanent = widget.initialPermanent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    final text = Theme.of(context).textTheme;
    final items = widget.items;
    final total =
        totalSizeLabel(items) ??
        (items.length == 1 ? '1 item' : '${items.length} itens');
    final risk = highestRisk(items);
    final needsRoot = batchNeedsRoot(items);
    final personal = widget.offerPermanent;
    final destructive = risk == RiskLevel.danger && (!personal || _permanent);

    final (
      IconData icon,
      Color iconColor,
      String title,
      String body,
    ) = switch (risk) {
      RiskLevel.safe => (
        Symbols.cleaning_services_rounded,
        scheme.secondary,
        'Limpar $total?',
        'Estes itens são recriados automaticamente quando necessário. '
            'Nenhum arquivo pessoal será apagado.',
      ),
      RiskLevel.attention => (
        Symbols.warning_rounded,
        sev.warning,
        'Remover $total?',
        'Revise os avisos abaixo antes de continuar.',
      ),
      RiskLevel.danger when personal => (
        _permanent ? Symbols.delete_forever_rounded : Symbols.delete_rounded,
        scheme.error,
        _permanent
            ? 'Apagar ${items.length} arquivos permanentemente?'
            : 'Mover ${items.length} arquivos para a lixeira?',
        'São arquivos seus: o disk-cleanup não sabe se existe outra cópia.',
      ),
      RiskLevel.danger => (
        Symbols.delete_forever_rounded,
        scheme.error,
        'Apagar $total permanentemente?',
        'Estes itens vão sair da lixeira e não poderão ser recuperados.',
      ),
    };

    final consequence = switch (risk) {
      RiskLevel.safe =>
        items.any((i) => i.category == CleanupCategory.build)
            ? 'O próximo build de cada projeto vai reinstalar as dependências.'
            : 'A próxima instalação vai baixar os pacotes de novo e pode demorar mais.',
      RiskLevel.attention => null,
      RiskLevel.danger =>
        personal && !_permanent
            ? 'Dá para desfazer. O espaço só volta quando a lixeira for esvaziada.'
            : 'Não há como desfazer.',
    };
    final warnings = {for (final i in items) ?dockerWarning(i)};

    final confirmLabel = switch (risk) {
      RiskLevel.safe => 'Limpar $total',
      RiskLevel.attention => 'Remover $total',
      RiskLevel.danger when personal && !_permanent => 'Mover para a lixeira',
      RiskLevel.danger => 'Apagar $total',
    };

    return AlertDialog(
      scrollable: true,
      icon: Icon(icon, color: iconColor),
      title: Text(title, textAlign: TextAlign.center),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 112).clamp(240, 512),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    for (final i in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                i.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              itemSizeLabel(i),
                              style: text.labelLarge?.copyWith(
                                fontFeatures: kTabular,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (personal) ...[
              const SizedBox(height: 16),
              Text('O que fazer com os arquivos', style: text.titleSmall),
              RadioGroup<bool>(
                groupValue: _permanent,
                onChanged: (v) => setState(() => _permanent = v ?? false),
                child: const Column(
                  children: [
                    RadioListTile<bool>(
                      value: false,
                      title: Text('Mover para a lixeira'),
                      subtitle: Text(
                        'Dá para desfazer. O espaço só volta quando a lixeira for esvaziada.',
                      ),
                    ),
                    RadioListTile<bool>(
                      value: true,
                      title: Text('Apagar permanentemente'),
                      subtitle: Text(
                        'Libera o espaço na hora. Não há como recuperar.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (needsRoot) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Symbols.admin_panel_settings_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'O sistema vai pedir sua senha de administrador para concluir.',
                    ),
                  ),
                ],
              ),
            ],
            for (final w in warnings) ...[
              const SizedBox(height: 12),
              _RiskLine(level: RiskLevel.attention, text: w),
            ],
            if (consequence != null) ...[
              const SizedBox(height: 12),
              _RiskLine(level: risk, text: consequence),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () =>
              Navigator.pop(context, CleanupDecision(permanent: _permanent)),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

class _RiskLine extends StatelessWidget {
  const _RiskLine({required this.level, required this.text});

  final RiskLevel level;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RiskChip(level: level),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ],
  );
}
