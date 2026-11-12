import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../backup/backup_controller.dart';
import '../../backup/backup_planner.dart';
import '../../core/format.dart';
import 'common.dart';

String _folders(int n) => n == 1 ? '1 pasta' : '$n pastas';

String _sizeOf(Iterable<ExcludedDir> dirs) {
  final known = [for (final d in dirs) ?d.bytes];
  if (known.isEmpty) return 'Desconhecido';
  final total = formatBytes(known.fold(0, (a, b) => a + b));
  final unknown = dirs.length - known.length;
  return unknown == 0 ? total : '$total, $unknown sem tamanho';
}

String kindLabel(String kind) =>
    isBuildKind(kind) ? '$kind (ignorado pelo git)' : kind;

class SourceExclusions extends StatelessWidget {
  const SourceExclusions({
    super.key,
    required this.controller,
    required this.source,
  });

  final BackupController controller;
  final String source;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scan = c.exclusions[source];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final out = [
      for (final d in scan?.dirs ?? const <ExcludedDir>[])
        if (!c.isIncluded(source, d)) d,
    ];
    final summary = switch (scan) {
      null || ExclusionScan(failed: true) =>
        'Dependências, caches e builds ignorados pelo git',
      ExclusionScan(loading: true) => 'Procurando…',
      _ when out.isEmpty => 'Nada fica fora desta pasta',
      _ => '${_folders(out.length)}, ${_sizeOf(out)}',
    };
    final groups = <String, List<ExcludedDir>>{};
    for (final d in scan?.dirs ?? const <ExcludedDir>[]) {
      groups.putIfAbsent(d.kind, () => []).add(d);
    }
    final locked = c.protectedIn(source);

    return ExpansionTile(
      key: Key('exclusoes-$source'),
      dense: true,
      tilePadding: const EdgeInsets.only(left: 40),
      childrenPadding: const EdgeInsets.only(left: 40, bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text('O que fica fora do backup'),
      subtitle: Text(summary),
      onExpansionChanged: (open) {
        if (open) c.loadExclusions(source);
      },
      children: [
        if (scan == null || scan.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else if (scan.failed)
          Text(
            'Não foi possível ver o que fica fora desta pasta.',
            style: text.bodyMedium?.copyWith(color: scheme.error),
          )
        else if (groups.isEmpty)
          Text('Nada fica fora desta pasta.', style: text.bodyMedium)
        else ...[
          Text(
            'Marque o que deve entrar no backup.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          for (final MapEntry(key: kind, value: dirs) in groups.entries)
            _KindGroup(controller: c, source: source, kind: kind, dirs: dirs),
        ],
        for (final (path, section) in locked)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.lock_rounded),
            title: Text(
              p.relative(path, from: source),
              style: const TextStyle(fontFamily: kMono),
            ),
            subtitle: Text('Entra pela seção $section'),
          ),
        if (scan != null && !scan.loading)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => c.loadExclusions(source, force: true),
              icon: const Icon(Symbols.refresh_rounded),
              label: const Text('Procurar de novo'),
            ),
          ),
      ],
    );
  }
}

class _KindGroup extends StatelessWidget {
  const _KindGroup({
    required this.controller,
    required this.source,
    required this.kind,
    required this.dirs,
  });

  final BackupController controller;
  final String source;
  final String kind;
  final List<ExcludedDir> dirs;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final state = c.kindState(source, kind);
    final included = dirs.where((d) => c.isIncluded(source, d)).length;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: Key('tipo-$source-$kind'),
      dense: true,
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Checkbox(
        tristate: true,
        value: state,
        onChanged: (_) => c.setKindIncluded(source, kind, state != true),
      ),
      title: Text(kindLabel(kind), style: const TextStyle(fontFamily: kMono)),
      subtitle: Text(
        [
          _folders(dirs.length),
          _sizeOf(dirs),
          if (state == true)
            'todas entram no backup'
          else if (included > 0)
            '$included entram no backup',
        ].join(', '),
      ),
      children: [
        for (final d in dirs)
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.only(left: 40),
            value: c.isIncluded(source, d),
            onChanged: (v) => c.setPathIncluded(source, d, v ?? false),
            title: Text(
              p.relative(d.path, from: source),
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(fontFamily: kMono),
            ),
            secondary: Text(
              d.bytes == null ? 'Desconhecido' : formatBytes(d.bytes!),
              style: text.labelLarge?.copyWith(
                fontFeatures: kTabular,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
