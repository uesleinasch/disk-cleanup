import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../core/format.dart';
import '../../scan/scan_controller.dart';
import '../../settings/settings_controller.dart';
import '../theme/severity_colors.dart';
import '../widgets/common.dart';

class DirectoriesPage extends StatefulWidget {
  const DirectoriesPage({
    super.key,
    required this.scan,
    required this.settings,
  });

  final ScanController scan;
  final SettingsController settings;

  @override
  State<DirectoriesPage> createState() => _DirectoriesPageState();
}

class _DirectoriesPageState extends State<DirectoriesPage> {
  String? _selected;
  bool _showDetailNarrow = false;

  Future<void> _add() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => _AddDirectoryDialog(scan: widget.scan),
    );
    if (path == null) return;
    await widget.settings.update(
      (s) => s.mappedDirs.contains(path)
          ? s
          : s.copyWith(mappedDirs: [...s.mappedDirs, path]),
    );
    setState(() => _selected = path);
    await widget.scan.scan();
  }

  Future<void> _unmap(String dir) async {
    await widget.settings.update(
      (s) => s.copyWith(mappedDirs: [...s.mappedDirs]..remove(dir)),
    );
    if (!mounted) return;
    setState(() {
      _selected = null;
      _showDetailNarrow = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$dir não é mais mapeado. Não apaga nada.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.scan, widget.settings]),
      builder: (context, _) {
        final dirs = widget.settings.value.mappedDirs;
        final selected = dirs.contains(_selected)
            ? _selected
            : dirs.firstOrNull;
        return LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth + 220 >= 1200;
            final list = _DirList(
              dirs: dirs,
              selected: selected,
              scan: widget.scan,
              onSelect: (d) => setState(() {
                _selected = d;
                _showDetailNarrow = true;
              }),
            );
            final detail = selected == null
                ? const SizedBox.shrink()
                : _DirDetail(
                    dir: selected,
                    scan: widget.scan,
                    onUnmap: () => _unmap(selected),
                    onBack: wide
                        ? null
                        : () => setState(() => _showDetailNarrow = false),
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: 'Diretórios',
                  subtitle: '${dirs.length} diretórios mapeados',
                  actions: [
                    FilledButton.icon(
                      onPressed: _add,
                      icon: const Icon(Symbols.create_new_folder_rounded),
                      label: const Text('Adicionar diretório'),
                    ),
                  ],
                ),
                if (widget.scan.running)
                  ScanProgressView(
                    progress: widget.scan.state.progress,
                    onCancel: widget.scan.cancel,
                  ),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: list),
                            SizedBox(width: 412 + 24, child: detail),
                          ],
                        )
                      : (_showDetailNarrow && selected != null ? detail : list),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DirList extends StatelessWidget {
  const _DirList({
    required this.dirs,
    required this.selected,
    required this.scan,
    required this.onSelect,
  });

  final List<String> dirs;
  final String? selected;
  final ScanController scan;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    final text = Theme.of(context).textTheme;
    final state = scan.state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        for (final dir in dirs)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: dir == selected
                  ? scheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(dir),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.folder_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dir,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelLarge?.copyWith(
                                fontFamily: kMono,
                              ),
                            ),
                            _status(context, dir, sev, scheme, text),
                          ],
                        ),
                      ),
                      Text(
                        state.lockedDirs.contains(dir)
                            ? '—'
                            : state.mappedDirs[dir] == null
                            ? '…'
                            : formatBytes(state.mappedDirs[dir]!.total),
                        style: text.titleMedium?.copyWith(
                          fontFeatures: kTabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _status(
    BuildContext context,
    String dir,
    SeverityColors sev,
    ColorScheme scheme,
    TextTheme text,
  ) {
    final state = scan.state;
    if (scan.running && state.progress.currentDir == dir) {
      return Text('Varrendo…', style: text.bodySmall);
    }
    if (state.lockedDirs.contains(dir)) {
      return Row(
        children: [
          Icon(
            Symbols.admin_panel_settings_rounded,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Precisa de senha de administrador para medir',
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ),
        ],
      );
    }
    final delta = state.weeklyDeltas[dir];
    if (delta == null) {
      return Text('Sem histórico ainda', style: text.bodySmall);
    }
    final up = delta > 0;
    final big = delta >= 5000000000;
    final color = big ? sev.warning : scheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(
          up ? Symbols.trending_up_rounded : Symbols.trending_down_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${up ? '+' : '−'}${formatBytes(delta.abs())} desde a última semana',
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _DirDetail extends StatelessWidget {
  const _DirDetail({
    required this.dir,
    required this.scan,
    required this.onUnmap,
    this.onBack,
  });

  final String dir;
  final ScanController scan;
  final VoidCallback onUnmap;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final result = scan.state.mappedDirs[dir];
    final locked = scan.state.lockedDirs.contains(dir);
    final children = [...?result?.entries]
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
    final max = children.isEmpty ? 1 : children.first.bytes;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: 'Voltar',
                  onPressed: onBack,
                  icon: const Icon(Symbols.arrow_back_rounded),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dir,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(fontFamily: kMono),
                    ),
                    Text(
                      locked || result == null
                          ? 'Tamanho desconhecido'
                          : formatBytes(result.total),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Abrir no gerenciador de arquivos',
                onPressed: () => scan.services.runner.run('xdg-open', [dir]),
                icon: const Icon(Symbols.folder_open_rounded),
              ),
              IconButton(
                tooltip: 'Parar de mapear (não apaga nada)',
                onPressed: onUnmap,
                icon: const Icon(Symbols.visibility_off_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (locked)
            EmptyState(
              icon: Symbols.admin_panel_settings_rounded,
              title: 'Este diretório pertence ao sistema',
              body: 'Para medir o tamanho, o disk-cleanup precisa ler como administrador. Nada é alterado.',
              action: OutlinedButton(
                onPressed: () => scan.measureLocked(dir),
                child: const Text('Medir com senha de administrador'),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  for (final c in children)
                    SizeBarRow(
                      label: p.basename(c.path),
                      bytes: c.bytes,
                      fraction: c.bytes / (max == 0 ? 1 : max),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AddDirectoryDialog extends StatefulWidget {
  const _AddDirectoryDialog({required this.scan});

  final ScanController scan;

  @override
  State<_AddDirectoryDialog> createState() => _AddDirectoryDialogState();
}

class _AddDirectoryDialogState extends State<_AddDirectoryDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Escolher',
      initialDirectory: widget.scan.services.home,
    );
    if (path != null && mounted) {
      setState(() {
        _controller.text = path;
        _error = null;
      });
    }
  }

  void _submit() {
    var path = _controller.text.trim();
    final home = widget.scan.services.home;
    if (path == '~' || path.startsWith('~/')) path = home + path.substring(1);
    path = p.normalize(path);
    if (!p.isAbsolute(path) || !Directory(path).existsSync()) {
      setState(() => _error = 'Esse diretório não existe');
      return;
    }
    Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Adicionar diretório'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'O disk-cleanup mede o diretório a cada varredura, procura builds e arquivos grandes nele e mostra quanto ele cresceu.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(fontFamily: kMono),
                  decoration: InputDecoration(
                    labelText: 'Caminho',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _pick, child: const Text('Escolher…')),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Adicionar e medir')),
    ],
  );
}
