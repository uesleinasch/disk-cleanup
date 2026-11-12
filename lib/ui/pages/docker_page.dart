import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cleanup/cleanup_controller.dart';
import '../../cleanup/docker_service.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../scan/scan_controller.dart';
import '../cleanup_flow.dart';
import '../widgets/cleanup_widgets.dart';
import '../widgets/common.dart';
import '../widgets/risk_chip.dart';

class DockerPage extends StatelessWidget {
  const DockerPage({super.key, required this.scan, required this.flow});

  final ScanController scan;
  final CleanupFlow flow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([scan, flow]),
      builder: (context, _) {
        final docker = scan.state.docker;
        final items = [
          for (final i in scan.state.items)
            if (i.category == CleanupCategory.docker) i,
        ];
        final selected = [
          for (final i in items)
            if (scan.isSelected(i.id)) i,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Docker',
              subtitle: docker == null || !docker.available
                  ? null
                  : '${docker.stopped.length} containers parados · '
                        '${docker.unusedImages.length} imagens sem uso',
              actions: [
                IconButton(
                  tooltip: 'Atualizar varredura (F5)',
                  onPressed: scan.running ? null : scan.scan,
                  icon: const Icon(Symbols.refresh_rounded),
                ),
              ],
            ),
            Expanded(child: _body(context, docker, items)),
            if (docker != null && docker.available && !docker.needsRoot ||
                selected.isNotEmpty)
              CleanupSummaryBar(
                count: selected.length,
                size: totalSizeLabel(selected),
                risk: highestRisk(selected),
                labelOverride: withSize('Remover', totalSizeLabel(selected)),
                onClean: flow.canClean
                    ? () async {
                        final result = await flow.run(context, selected);
                        if (result == null || result.cancelled) return;
                        try {
                          scan.replaceDocker(
                            await scan.services.docker.inventory(),
                          );
                        } on Object catch (e) {
                          debugPrint('Falha ao reler o Docker: $e');
                        }
                      }
                    : null,
              ),
          ],
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    DockerInventory? docker,
    List<CleanupItem> items,
  ) {
    if (docker == null || !docker.available) {
      return const EmptyState(
        icon: Symbols.deployed_code_rounded,
        title: 'Docker não encontrado',
        body: 'O Docker não está instalado ou o serviço está parado. Inicie o Docker e atualize a varredura.',
      );
    }
    if (docker.needsRoot && items.isEmpty) {
      return EmptyState(
        icon: Symbols.admin_panel_settings_rounded,
        title: 'O Docker precisa de permissão de administrador',
        body: 'Seu usuário não está no grupo docker. Para ver o uso, o disk-cleanup precisa ler como administrador. Nada é alterado.',
        action: OutlinedButton(
          onPressed: scan.readDockerAsRoot,
          child: const Text('Ler com senha de administrador'),
        ),
      );
    }
    final groups = <(String, String, CleanupItem?, List<(String, String, int)>)>[
      (
        'Build cache',
        'Camadas intermediárias de builds. O próximo docker build recria o que precisar.',
        _find(items, 'docker:buildcache'),
        const [],
      ),
      (
        'Containers parados',
        'Remover apaga o que foi gravado dentro do container e não está em volume.',
        _find(items, 'docker:containers'),
        [
          for (final c in docker.stopped)
            (c.name, '${c.image} · ${c.status}', c.bytes),
        ],
      ),
      (
        'Imagens sem uso',
        'Podem ser baixadas de novo com docker pull, se o registro ainda tiver a versão.',
        _find(items, 'docker:images'),
        [
          for (final i in docker.unusedImages)
            (i.repoTag, i.id.substring(0, 12), i.bytes),
        ],
      ),
      (
        'Volumes sem uso',
        'Volumes guardam dados de bancos e serviços. Confira antes de remover.',
        _find(items, 'docker:volumes'),
        [
          for (final v in docker.unusedVolumes)
            (v.name, 'Sem container ligado', v.bytes),
        ],
      ),
    ];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth < 840 ? 2 : 4;
                  final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final (icon, label, total, rec) in [
                        (
                          Symbols.layers_rounded,
                          'Imagens',
                          docker.imagesBytes,
                          _find(items, 'docker:images')?.bytes ?? 0,
                        ),
                        (
                          Symbols.deployed_code_rounded,
                          'Containers',
                          docker.containersBytes,
                          _find(items, 'docker:containers')?.bytes ?? 0,
                        ),
                        (
                          Symbols.database_rounded,
                          'Volumes',
                          docker.volumesBytes,
                          _find(items, 'docker:volumes')?.bytes ?? 0,
                        ),
                        (
                          Symbols.construction_rounded,
                          'Build cache',
                          docker.buildCacheBytes,
                          docker.buildCacheReclaimable,
                        ),
                      ])
                        Container(
                          width: w,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: scheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    icon,
                                    size: 18,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(label, style: text.labelMedium),
                                ],
                              ),
                              Text(
                                formatBytes(total),
                                style: text.headlineSmall?.copyWith(
                                  fontFeatures: kTabular,
                                ),
                              ),
                              Text(
                                '${formatBytes(rec)} recuperáveis',
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              for (final (title, desc, item, rows) in groups)
                if (item != null) ...[
                  CleanupItemTile(
                    item: item,
                    selected: scan.isSelected(item.id),
                    onChanged: (_) => scan.toggle(item.id),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 56, bottom: 4),
                    child: Text(
                      desc,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final (name, detail, bytes) in rows.take(8))
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 56,
                        right: 100,
                        top: 2,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$name  ·  $detail',
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                fontFamily: kMono,
                              ),
                            ),
                          ),
                          Text(
                            formatBytes(bytes),
                            style: text.bodySmall?.copyWith(
                              fontFeatures: kTabular,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (rows.length > 8)
                    Padding(
                      padding: const EdgeInsets.only(left: 56, top: 2),
                      child: Text(
                        'e mais ${rows.length - 8}',
                        style: text.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 16),
                ] else
                  ListTile(
                    leading: const RiskChip(level: RiskLevel.safe),
                    title: Text(title),
                    subtitle: const Text('Nada para remover'),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  static CleanupItem? _find(List<CleanupItem> items, String id) =>
      items.where((i) => i.id == id).firstOrNull;
}
