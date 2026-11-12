import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cleanup/cleanup_controller.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../scan/scan_controller.dart';
import '../cleanup_flow.dart';
import '../theme/severity_colors.dart';
import '../widgets/cleanup_widgets.dart';
import '../widgets/common.dart';

enum CleanupTab {
  trash('Lixeira', Symbols.delete_rounded, {CleanupCategory.trash}),
  caches('Caches', Symbols.cached_rounded, {
    CleanupCategory.cache,
    CleanupCategory.system,
  }),
  builds('Builds', Symbols.build_rounded, {CleanupCategory.build});

  const CleanupTab(this.label, this.icon, this.categories);

  final String label;
  final IconData icon;
  final Set<CleanupCategory> categories;
}

class CleanupPage extends StatefulWidget {
  const CleanupPage({super.key, required this.scan, required this.flow});

  final ScanController scan;
  final CleanupFlow flow;

  @override
  State<CleanupPage> createState() => _CleanupPageState();
}

class _CleanupPageState extends State<CleanupPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: CleanupTab.values.length,
    vsync: this,
    initialIndex: 1,
  )..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static const _hints = {
    CleanupTab.trash: 'Itens na lixeira ainda ocupam espaço. Esvaziar é permanente: confira antes.',
    CleanupTab.caches: 'Caches guardam downloads para acelerar instalações. Apagar é seguro: tudo é baixado de novo quando necessário.',
    CleanupTab.builds: 'Pastas geradas por builds. Projetos modificados nos últimos dias não vêm marcados.',
  };

  List<CleanupItem> _itemsOf(CleanupTab tab) => [
    for (final i in widget.scan.state.items)
      if (tab.categories.contains(i.category) && i.id != 'trash:all') i,
  ];

  String _tabLabel(CleanupTab t, bool scanned) {
    if (!scanned) return t.label;
    final size = totalSizeLabel(_itemsOf(t));
    return size == null ? t.label : '${t.label} ($size)';
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final flow = widget.flow;
    return ListenableBuilder(
      listenable: Listenable.merge([scan, flow]),
      builder: (context, _) {
        final scanned = scan.state.updatedAt != null;
        final tab = CleanupTab.values[_tabs.index];
        final items = _itemsOf(tab);
        final selected = [
          for (final i in items)
            if (scan.isSelected(i.id)) i,
        ];
        final size = totalSizeLabel(selected);
        final allTrash =
            tab == CleanupTab.trash &&
            items.isNotEmpty &&
            selected.length == items.length;
        final emptyTrashItem = scan.state.items
            .where((i) => i.id == 'trash:all')
            .firstOrNull;
        final toRun = allTrash && emptyTrashItem != null
            ? [emptyTrashItem]
            : selected;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
              for (final i in items) {
                if (!scan.isSelected(i.id)) scan.toggle(i.id);
              }
            },
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Limpeza',
                subtitle: scan.state.updatedAt == null
                    ? 'Ainda não varrido'
                    : 'Atualizado ${formatAgo(scan.state.updatedAt!, scan.services.now())}',
                actions: [
                  IconButton(
                    tooltip: 'Atualizar varredura (F5)',
                    onPressed: scan.running ? null : scan.scan,
                    icon: const Icon(Symbols.refresh_rounded),
                  ),
                ],
              ),
              if (scan.running)
                ScanProgressView(
                  progress: scan.state.progress,
                  onCancel: scan.cancel,
                ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final t in CleanupTab.values)
                    Tab(
                      icon: Icon(t.icon),
                      iconMargin: EdgeInsets.zero,
                      text: _tabLabel(t, scanned),
                    ),
                ],
              ),
              Expanded(
                child: !scanned && items.isEmpty
                    ? EmptyState(
                        icon: Symbols.search_rounded,
                        title: scan.running
                            ? 'Varrendo o disco…'
                            : 'Ainda não varrido',
                        body: scan.running
                            ? 'Os itens aparecem aqui quando a varredura terminar.'
                            : 'Atualize a varredura para ver o que dá para limpar.',
                      )
                    : items.isEmpty
                    ? EmptyState(
                        icon: Symbols.check_circle_rounded,
                        iconColor: Theme.of(context)
                            .extension<SeverityColors>()!
                            .success,
                        title: 'Nada para limpar aqui',
                        body: 'A próxima varredura vai mostrar o que voltar a acumular.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        children: [
                          Text(
                            _hints[tab]!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 12),
                          for (final i in items)
                            CleanupItemTile(
                              item: i,
                              selected: scan.isSelected(i.id),
                              onChanged: (_) => scan.toggle(i.id),
                            ),
                        ],
                      ),
              ),
              if (scanned || items.isNotEmpty)
                CleanupSummaryBar(
                  count: selected.length,
                  size: size,
                  risk: highestRisk(selected),
                  labelOverride: allTrash
                      ? (size == null
                            ? 'Esvaziar lixeira'
                            : 'Esvaziar lixeira ($size)')
                      : null,
                  onClearSelection: () {
                    for (final i in selected) {
                      scan.toggle(i.id);
                    }
                  },
                  onClean: flow.canClean
                      ? () async {
                          final result = await flow.run(context, toRun);
                          if (result != null && allTrash && !result.cancelled) {
                            scan.removeItems(items.map((i) => i.id));
                          }
                        }
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}
