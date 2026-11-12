import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../core/format.dart';
import '../../core/models.dart';
import '../../scan/large_files.dart';
import '../../scan/scan_controller.dart';
import '../cleanup_flow.dart';
import '../widgets/cleanup_widgets.dart';
import '../widgets/common.dart';

enum FileFilter {
  all('Todos', Symbols.select_all_rounded, {}),
  archives('Compactados', Symbols.folder_zip_rounded, {
    '.7z',
    '.zip',
    '.tar',
    '.gz',
    '.tgz',
    '.xz',
    '.bz2',
    '.zst',
    '.rar',
    '.nsz',
  }),
  diskImages('Imagens de disco', Symbols.album_rounded, {
    '.img',
    '.iso',
    '.qcow2',
    '.vdi',
    '.vmdk',
    '.ova',
  }),
  videos('Vídeos', Symbols.movie_rounded, {
    '.mp4',
    '.mkv',
    '.webm',
    '.mov',
    '.avi',
  }),
  old('Sem acesso há 6 meses', Symbols.history_rounded, {});

  const FileFilter(this.label, this.icon, this.extensions);

  final String label;
  final IconData icon;
  final Set<String> extensions;

  bool matches(LargeFile f, DateTime now) {
    final ext = p.extension(f.path).toLowerCase();
    return switch (this) {
      FileFilter.all => true,
      FileFilter.old => now.difference(f.lastAccess).inDays >= 182,
      _ =>
        extensions.contains(ext) ||
            (this == archives && f.path.contains('.tar.')),
    };
  }
}

CleanupItem largeFileItem(LargeFile f) => CleanupItem(
  id: 'file:${f.path}',
  category: CleanupCategory.largeFile,
  title: p.basename(f.path),
  path: f.path,
  note: '',
  bytes: f.bytes,
  risk: RiskLevel.danger,
  requiresRoot: false,
  preselected: false,
  lastModified: f.modified,
  action: TrashPathsAction([f.path]),
);

class LargeFilesPage extends StatefulWidget {
  const LargeFilesPage({super.key, required this.scan, required this.flow});

  final ScanController scan;
  final CleanupFlow flow;

  @override
  State<LargeFilesPage> createState() => _LargeFilesPageState();
}

class _LargeFilesPageState extends State<LargeFilesPage> {
  FileFilter _filter = FileFilter.all;
  String _query = '';
  final _selected = <String>{};
  final _search = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _remove(List<LargeFile> files, {bool permanent = false}) async {
    if (files.isEmpty) return;
    final result = await widget.flow.run(
      context,
      [for (final f in files) largeFileItem(f)],
      offerPermanent: true,
      initialPermanent: permanent,
    );
    if (result == null || result.cancelled || !mounted) return;
    final done = result.doneIds.map((id) => id.substring(5)).toSet();
    setState(() => _selected.removeAll(done));
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.scan, flow]),
      builder: (context, _) {
        final now = widget.scan.services.now();
        final removed = flow.removedFiles;
        final all = [
          for (final f in widget.scan.state.largeFiles)
            if (!removed.contains(f.path)) f,
        ];
        final visible = [
          for (final f in all)
            if (_filter.matches(f, now) &&
                (_query.isEmpty ||
                    p.basename(f.path).toLowerCase().contains(_query)))
              f,
        ];
        final selected = [
          for (final f in all)
            if (_selected.contains(f.path)) f,
        ];
        final bytes = selected.fold(0, (a, f) => a + f.bytes);
        final scheme = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
                _search.requestFocus(),
            const SingleActivator(LogicalKeyboardKey.delete): () =>
                _remove(selected),
            const SingleActivator(LogicalKeyboardKey.delete, shift: true): () =>
                _remove(selected, permanent: true),
            const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
                setState(() => _selected.addAll(visible.map((f) => f.path))),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: 'Arquivos grandes',
                  subtitle: 'Arquivos acima de 1 GB nos diretórios mapeados',
                  actions: [
                    SizedBox(
                      width: 260,
                      child: SearchBar(
                        focusNode: _search,
                        hintText: 'Filtrar por nome (Ctrl+F)',
                        leading: const Icon(Symbols.search_rounded),
                        onChanged: (v) =>
                            setState(() => _query = v.trim().toLowerCase()),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in FileFilter.values)
                        FilterChip(
                          avatar: Icon(f.icon, size: 18),
                          label: Text(f.label),
                          selected: _filter == f,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: visible.isEmpty
                      ? const EmptyState(
                          icon: Symbols.draft_rounded,
                          title: 'Nenhum arquivo grande aqui',
                          body: 'Nada acima de 1 GB com esse filtro nos diretórios mapeados.',
                        )
                      : LayoutBuilder(
                          builder: (context, c) {
                            final narrow = c.maxWidth < 760;
                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: visible.length,
                              itemBuilder: (context, i) {
                                final f = visible[i];
                                final sel = _selected.contains(f.path);
                                final access =
                                    'acesso ${formatAgo(f.lastAccess, now)}';
                                return Material(
                                  color: sel
                                      ? scheme.primary.withValues(alpha: 0.06)
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: () => setState(
                                      () => sel
                                          ? _selected.remove(f.path)
                                          : _selected.add(f.path),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        children: [
                                          Checkbox(
                                            value: sel,
                                            semanticLabel:
                                                'Selecionar ${p.basename(f.path)}',
                                            onChanged: (v) => setState(
                                              () => v == true
                                                  ? _selected.add(f.path)
                                                  : _selected.remove(f.path),
                                            ),
                                          ),
                                          Icon(
                                            _iconFor(f),
                                            color: scheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  p.basename(f.path),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: text.labelLarge,
                                                ),
                                                Tooltip(
                                                  message: f.path,
                                                  child: Text(
                                                    _middleEllipsis(
                                                      p.dirname(f.path),
                                                      narrow ? 40 : 70,
                                                    ),
                                                    style: text.bodySmall
                                                        ?.copyWith(
                                                          fontFamily: kMono,
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ),
                                                if (narrow)
                                                  Text(
                                                    access,
                                                    style: text.bodySmall,
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (!narrow)
                                            SizedBox(
                                              width: 140,
                                              child: Text(
                                                access,
                                                style: text.bodySmall,
                                              ),
                                            ),
                                          SizedBox(
                                            width: 90,
                                            child: Tooltip(
                                              message: formatBytesExact(
                                                f.bytes,
                                              ),
                                              child: Text(
                                                formatBytes(f.bytes),
                                                textAlign: TextAlign.right,
                                                style: text.labelLarge
                                                    ?.copyWith(
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
                              },
                            );
                          },
                        ),
                ),
                CleanupSummaryBar(
                  count: selected.length,
                  size: formatBytes(bytes),
                  risk: RiskLevel.safe,
                  labelOverride: 'Mover para a lixeira',
                  extraActions: [
                    OutlinedButton.icon(
                      onPressed: selected.isEmpty
                          ? null
                          : () => widget.scan.services.runner.run('xdg-open', [
                              p.dirname(selected.first.path),
                            ]),
                      icon: const Icon(Symbols.folder_open_rounded),
                      label: const Text('Abrir local'),
                    ),
                  ],
                  onClean: flow.canClean ? () => _remove(selected) : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static IconData _iconFor(LargeFile f) {
    final now = DateTime.now();
    for (final filter in [
      FileFilter.archives,
      FileFilter.diskImages,
      FileFilter.videos,
    ]) {
      if (filter.matches(f, now)) return filter.icon;
    }
    return Symbols.draft_rounded;
  }

  static String _middleEllipsis(String s, int max) {
    if (s.length <= max) return s;
    final half = (max - 1) ~/ 2;
    return '${s.substring(0, half)}…${s.substring(s.length - half)}';
  }
}
