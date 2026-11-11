import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../backup/backup_controller.dart';
import '../../backup/restore_controller.dart';
import '../../backup/restore_planner.dart';
import '../../core/format.dart';
import '../theme/severity_colors.dart';
import '../widgets/backup_widgets.dart';
import '../widgets/common.dart';
import '../widgets/conflict_review.dart';

const _ruleOptions = [
  ConflictOption(ConflictAction.newerWins, 'Mais recente'),
  ConflictOption(ConflictAction.keepLocal, 'Manter o atual'),
  ConflictOption(ConflictAction.useBackup, 'Usar o backup'),
  ConflictOption(ConflictAction.keepBoth, 'Manter os dois'),
];

const _fileOptions = [
  ConflictOption(ConflictAction.keepLocal, 'Manter o atual'),
  ConflictOption(ConflictAction.useBackup, 'Usar o backup'),
  ConflictOption(ConflictAction.keepBoth, 'Manter os dois'),
];

String _plural(int n, String one, String many) => n == 1 ? one : many;

String _tilde(String path, String home) => path == home
    ? '~'
    : p.isWithin(home, path)
    ? '~/${p.relative(path, from: home)}'
    : path;

class RestoreTab extends StatefulWidget {
  const RestoreTab({super.key, required this.controller});

  final RestoreController controller;

  @override
  State<RestoreTab> createState() => _RestoreTabState();
}

class _RestoreTabState extends State<RestoreTab> {
  RestoreController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (c.phase == RestorePhase.idle && c.choices.isEmpty) c.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, c.backup]),
    builder: (context, _) {
      final (body, bar) = switch (c.phase) {
        RestorePhase.idle || RestorePhase.loading => (
          _SelectView(controller: c),
          _SelectBar(controller: c),
        ),
        RestorePhase.analyzing => (
          _ItemsView(controller: c),
          BottomBar(
            children: [
              OutlinedButton(
                onPressed: c.cancel,
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
        RestorePhase.reviewing => (
          _ReviewView(controller: c),
          _ReviewBar(controller: c),
        ),
        RestorePhase.running || RestorePhase.finished => (
          _ItemsView(controller: c),
          BottomBar(
            children: [
              if (c.phase == RestorePhase.running)
                OutlinedButton(
                  onPressed: c.cancel,
                  child: const Text('Cancelar'),
                )
              else
                FilledButton(
                  onPressed: c.dismiss,
                  child: const Text('Concluir'),
                ),
            ],
          ),
        ),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: body),
          bar,
        ],
      );
    },
  );
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ],
  );
}

class _Problems extends StatelessWidget {
  const _Problems(this.messages);

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Symbols.error_rounded, size: 20, color: scheme.error),
                const SizedBox(width: 12),
                Expanded(child: Text(m)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SelectView extends StatelessWidget {
  const _SelectView({required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final problems = [
      if (c.loadError != null) c.loadError!,
      for (final m in c.problems)
        if (m != 'Escolha o que restaurar.') m,
    ];
    return _Scroll(
      children: [
        if (c.phase == RestorePhase.loading) const LinearProgressIndicator(),
        if (problems.isNotEmpty) ...[
          _Problems(problems),
          const SizedBox(height: 8),
        ],
        _SourceCard(controller: c),
        if (c.choices.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ChoicesCard(controller: c),
          const SizedBox(height: 16),
          _DestinationCard(controller: c),
        ],
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.controller});

  final RestoreController controller;

  Future<void> _open(BuildContext context) async {
    final dir = await getDirectoryPath(
      confirmButtonText: 'Abrir',
      initialDirectory: controller.backupDir,
    );
    if (dir != null) await controller.load(dir: dir);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final m = c.manifest;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (m?.date != null) 'feito ${formatAgo(m!.date!, DateTime.now())}',
      if (m?.hostname != null) 'no computador ${m!.hostname}',
      if (m != null && !m.fromManifest)
        'backup antigo, os destinos foram deduzidos pelos nomes',
    ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle(
            'Backup',
            'De onde os arquivos voltam. Nada é apagado do backup.',
          ),
          if (c.backupDir != null)
            Text(
              c.backupDir!,
              style: text.bodyMedium?.copyWith(fontFamily: kMono),
            ),
          if (details.isNotEmpty)
            Text(
              details.join(', '),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: c.busy ? null : () => _open(context),
                icon: const Icon(Symbols.folder_open_rounded, size: 20),
                label: const Text('Abrir outro backup…'),
              ),
              TextButton(
                onPressed: c.busy ? null : () => c.load(),
                child: const Text('Usar o disco configurado'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoicesCard extends StatelessWidget {
  const _ChoicesCard({required this.controller});

  final RestoreController controller;

  Future<void> _pickFiles(BuildContext context, RestoreChoice choice) async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => _BackupBrowser(
        root: choice.backupPath,
        title: choice.label,
        initial: controller.subpaths[choice.id] ?? const [],
      ),
    );
    if (picked != null) controller.setSubpaths(choice.id, picked);
  }

  Future<void> _pickTarget(BuildContext context, RestoreChoice choice) async {
    final dir = await getDirectoryPath(
      confirmButtonText: 'Restaurar aqui',
      initialDirectory: controller.home,
    );
    if (dir != null) controller.setCustomTarget(choice.id, dir);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'O que restaurar',
            'Restaure tudo ou só alguns itens. Antes de copiar, o app mostra '
                'o que já existe no computador para você decidir.',
          ),
          for (final choice in c.choices) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: c.selected.contains(choice.id),
              onChanged: (_) => c.toggle(choice.id),
              secondary: Icon(switch (choice.kind) {
                RestoreKind.secrets => Symbols.key_rounded,
                RestoreKind.folder => Symbols.folder_rounded,
                RestoreKind.browser => Symbols.public_rounded,
              }),
              title: Text(choice.label),
              subtitle: Text(
                [
                  if (c.subpaths[choice.id] case final picked?)
                    '${picked.length} ${_plural(picked.length, 'item escolhido', 'itens escolhidos')}',
                  switch (c.targetFor(choice)) {
                    final t? => 'para ${_tilde(t, c.home)}',
                    null => 'destino desconhecido',
                  },
                ].join(' · '),
                style: text.bodySmall?.copyWith(
                  color: c.targetFor(choice) == null
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 56, bottom: 8),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (choice.kind == RestoreKind.secrets &&
                      c.secretsFiles.length > 1)
                    DropdownButton<String>(
                      value: c.secretsFile,
                      items: [
                        for (final f in c.secretsFiles)
                          DropdownMenuItem(value: f, child: Text(f)),
                      ],
                      onChanged: (v) => v == null ? null : c.setSecretsFile(v),
                    ),
                  if (choice.kind == RestoreKind.secrets)
                    Text(
                      'Pede a senha do pacote na janela do sistema.',
                      style: text.bodySmall,
                    ),
                  if (choice.kind == RestoreKind.browser)
                    Text(
                      'Feche o ${choice.label} antes. Restaure as chaves junto '
                      'para as senhas salvas voltarem.',
                      style: text.bodySmall,
                    ),
                  if (choice.kind == RestoreKind.folder)
                    TextButton(
                      onPressed: () => _pickFiles(context, choice),
                      child: const Text('Escolher arquivos…'),
                    ),
                  if (choice.kind == RestoreKind.folder &&
                      c.subpaths.containsKey(choice.id))
                    TextButton(
                      onPressed: () => c.setSubpaths(choice.id, null),
                      child: const Text('Pasta inteira'),
                    ),
                  if (choice.kind == RestoreKind.folder)
                    TextButton(
                      onPressed: () => _pickTarget(context, choice),
                      child: const Text('Outro destino…'),
                    ),
                  if (c.customTargets.containsKey(choice.id))
                    TextButton(
                      onPressed: () => c.setCustomTarget(choice.id, null),
                      child: const Text('Destino padrão'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'Para onde',
            'O que for substituído no computador fica guardado numa pasta '
                'à parte, para você recuperar se precisar.',
          ),
          RadioGroup<RestoreDestination>(
            groupValue: c.destination,
            onChanged: (v) => v == null ? null : c.setDestination(v),
            child: Column(
              children: [
                const RadioListTile(
                  contentPadding: EdgeInsets.zero,
                  value: RestoreDestination.original,
                  title: Text('No lugar original'),
                  subtitle: Text('Os arquivos voltam para onde estavam.'),
                ),
                RadioListTile(
                  contentPadding: EdgeInsets.zero,
                  value: RestoreDestination.separate,
                  title: const Text('Numa pasta separada'),
                  subtitle: Text(
                    'Em ${_tilde(c.separateRoot, c.home)}, sem tocar nos '
                    'arquivos atuais.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectBar extends StatelessWidget {
  const _SelectBar({required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final n = c.selected.length;
    final ready = c.phase == RestorePhase.idle && c.choices.isNotEmpty;
    return BottomBar(
      children: [
        Text(
          n == 0
              ? 'Nada escolhido.'
              : '$n ${_plural(n, 'item escolhido', 'itens escolhidos')}.',
        ),
        TextButton(
          onPressed: ready && !c.busyElsewhere
              ? () {
                  c.selectAll();
                  c.analyze();
                }
              : null,
          child: const Text('Restaurar tudo'),
        ),
        FilledButton.icon(
          onPressed: ready && c.canAnalyze ? c.analyze : null,
          icon: const Icon(Symbols.manage_search_rounded),
          label: const Text('Analisar'),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.controller,
    this.current = false,
  });

  final RestoreItem item;
  final RestoreController controller;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final progress = c.progress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Center(child: StepStatusIcon(item.status)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.choice.label, style: text.titleSmall),
                if (item.target != null)
                  Text(
                    'para ${_tilde(item.target!, c.home)}',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFamily: kMono,
                    ),
                  ),
                if (current &&
                    c.phase == RestorePhase.analyzing &&
                    item.choice.kind == RestoreKind.secrets)
                  Text(
                    'Digite a senha do pacote na janela do sistema.',
                    style: text.bodyMedium?.copyWith(color: scheme.primary),
                  ),
                if (current &&
                    c.phase == RestorePhase.running &&
                    progress != null)
                  CopyProgress(progress),
                if (item.message != null)
                  Text(
                    item.message!,
                    style: text.bodySmall?.copyWith(
                      color: item.status == BackupStepStatus.failed
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                if (item.warnings.isNotEmpty)
                  WarningsList(warnings: item.warnings),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsView extends StatelessWidget {
  const _ItemsView({required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final finished = c.phase == RestorePhase.finished;
    return _Scroll(
      children: [
        if (finished) ...[
          OutcomeBanner(
            outcome: c.outcome,
            done: 'Restauração concluída.',
            failed: 'A restauração não terminou. Veja abaixo o que falhou.',
            cancelled: 'Restauração cancelada. O que já foi copiado ficou no computador.',
            warnings: 'Restauração concluída com avisos.',
          ),
          const SizedBox(height: 16),
        ],
        SectionCard(
          child: Column(
            children: [
              for (final (i, item) in c.items.indexed)
                _ItemRow(item: item, controller: c, current: i == c.current),
            ],
          ),
        ),
        if (finished && c.replacedSomething) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'As versões substituídas estão em '),
                      TextSpan(
                        text: c.replacedDir,
                        style: const TextStyle(fontFamily: kMono),
                      ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: c.openReplaced,
                icon: const Icon(Symbols.folder_open_rounded, size: 20),
                label: const Text('Abrir pasta'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = c.totals;
    final text = Theme.of(context).textTheme;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    final withConflicts = [
      for (final i in c.items)
        if (i.analysis?.conflicts.isNotEmpty ?? false) i,
    ];
    final others = [
      for (final i in c.items)
        if (!withConflicts.contains(i)) i,
    ];
    return _Scroll(
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.conflicts == 0
                    ? 'Nenhum conflito.'
                    : '${t.conflicts} ${_plural(t.conflicts, 'arquivo já existe', 'arquivos já existem')} '
                          'no computador com conteúdo diferente.',
                style: text.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${t.created} ${_plural(t.created, 'arquivo novo', 'arquivos novos')} '
                '(${formatBytes(t.createdBytes)}) · '
                '${t.replace} a substituir · ${t.duplicate} em cópia · '
                '${t.keep} ${_plural(t.keep, 'fica', 'ficam')} como está',
                style: text.bodyMedium?.copyWith(fontFeatures: kTabular),
              ),
              if (t.conflicts > 0) ...[
                const SizedBox(height: 16),
                Text('Para os conflitos', style: text.labelLarge),
                const SizedBox(height: 8),
                ConflictRuleBar(
                  options: _ruleOptions,
                  value: c.rule,
                  onChanged: c.setRule,
                ),
                const SizedBox(height: 4),
                Text(switch (c.rule) {
                  ConflictAction.newerWins =>
                    'Fica a versão alterada por último em cada arquivo.',
                  ConflictAction.keepLocal =>
                    'Os arquivos atuais ficam como estão.',
                  ConflictAction.useBackup => 'O backup substitui os atuais, que ficam guardados à parte.',
                  ConflictAction.keepBoth =>
                    'A versão do backup vem com "(${c.duplicateLabel})" no nome.',
                }, style: text.bodySmall),
              ],
            ],
          ),
        ),
        for (final item in withConflicts) ...[
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardTitle(
                  item.choice.label,
                  '${item.analysis!.conflicts.length} '
                  '${_plural(item.analysis!.conflicts.length, 'conflito', 'conflitos')} · '
                  '${item.analysis!.created.length} '
                  '${_plural(item.analysis!.created.length, 'novo', 'novos')}',
                ),
                ConflictReview<ConflictAction>(
                  conflicts: item.analysis!.conflicts,
                  options: _fileOptions,
                  actionOf: (x) =>
                      effectiveAction(x, item.overrides[x.path] ?? c.rule),
                  isOverridden: (x) => item.overrides.containsKey(x.path),
                  onChanged: (x, a) => c.setOverride(item, x.path, a),
                ),
              ],
            ),
          ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              children: [
                for (final item in others) _ItemRow(item: item, controller: c),
              ],
            ),
          ),
        ],
        if (t.replace > 0) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Symbols.info_rounded, size: 20, color: sev.warning),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Os arquivos substituídos vão para uma pasta à parte, '
                  'dentro de ~/.local/share/disk-cleanup/substituidos.',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ReviewBar extends StatelessWidget {
  const _ReviewBar({required this.controller});

  final RestoreController controller;

  Future<void> _confirm(BuildContext context) async {
    final t = controller.totals;
    final files = t.created + t.replace + t.duplicate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Symbols.settings_backup_restore_rounded),
        title: Text(
          'Restaurar $files ${_plural(files, 'arquivo', 'arquivos')}?',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (t.created > 0)
                Text(
                  '${t.created} ${_plural(t.created, 'arquivo volta', 'arquivos voltam')} '
                  '(${formatBytes(t.createdBytes)}).',
                ),
              if (t.replace > 0)
                Text(
                  '${t.replace} ${_plural(t.replace, 'arquivo atual é substituído', 'arquivos atuais são substituídos')}. '
                  'A versão atual fica guardada à parte.',
                ),
              if (t.duplicate > 0)
                Text(
                  '${t.duplicate} ${_plural(t.duplicate, 'cópia chega', 'cópias chegam')} '
                  'com "(${controller.duplicateLabel})" no nome.',
                ),
              if (t.keep > 0)
                Text(
                  '${t.keep} ${_plural(t.keep, 'arquivo fica', 'arquivos ficam')} como está.',
                ),
              const SizedBox(height: 8),
              const Text('Nada é apagado do computador nem do backup.'),
            ],
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
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return BottomBar(
      children: [
        TextButton(onPressed: c.back, child: const Text('Voltar')),
        FilledButton.icon(
          onPressed: c.canRun ? () => _confirm(context) : null,
          icon: const Icon(Symbols.settings_backup_restore_rounded),
          label: const Text('Restaurar'),
        ),
      ],
    );
  }
}

class _BackupBrowser extends StatefulWidget {
  const _BackupBrowser({
    required this.root,
    required this.title,
    required this.initial,
  });

  final String root;
  final String title;
  final List<String> initial;

  @override
  State<_BackupBrowser> createState() => _BackupBrowserState();
}

class _BackupBrowserState extends State<_BackupBrowser> {
  late final Set<String> _picked = {...widget.initial};
  String _rel = '';

  List<FileSystemEntity> _entries() {
    try {
      final list = Directory(p.join(widget.root, _rel))
          .listSync(followLinks: false);
      list.sort((a, b) {
        final da = a is Directory ? 0 : 1;
        final db = b is Directory ? 0 : 1;
        if (da != db) return da - db;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      return list;
    } on FileSystemException {
      return const [];
    }
  }

  bool _coveredByParent(String rel) =>
      _picked.any((x) => x != rel && p.isWithin(x, rel));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final entries = _entries();
    return AlertDialog(
      title: Text('Escolher em ${widget.title}'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Pasta acima',
                  onPressed: _rel.isEmpty
                      ? null
                      : () => setState(() {
                          final up = p.dirname(_rel);
                          _rel = up == '.' ? '' : up;
                        }),
                  icon: const Icon(Symbols.arrow_upward_rounded),
                ),
                Expanded(
                  child: Text(
                    _rel.isEmpty ? widget.title : '${widget.title}/$_rel',
                    style: text.bodyMedium?.copyWith(fontFamily: kMono),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('Pasta vazia.'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final name = p.basename(e.path);
                        final rel = _rel.isEmpty ? name : p.join(_rel, name);
                        final isDir = e is Directory;
                        final covered = _coveredByParent(rel);
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: covered || _picked.contains(rel),
                          onChanged: covered
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    _picked
                                      ..removeWhere((x) => p.isWithin(rel, x))
                                      ..add(rel);
                                  } else {
                                    _picked.remove(rel);
                                  }
                                }),
                          title: Text(name, overflow: TextOverflow.ellipsis),
                          secondary: isDir
                              ? IconButton(
                                  tooltip: 'Abrir $name',
                                  onPressed: () => setState(() => _rel = rel),
                                  icon: const Icon(
                                    Symbols.chevron_right_rounded,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, _picked.toList()),
          child: Text(
            'Escolher ${_picked.length} '
            '${_plural(_picked.length, 'item', 'itens')}',
          ),
        ),
      ],
    );
  }
}
