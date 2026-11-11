import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../backup/backup_controller.dart';
import '../../backup/disk_targets.dart';
import '../../backup/restore_controller.dart';
import '../../core/format.dart';
import '../theme/severity_colors.dart';
import '../widgets/backup_widgets.dart';
import '../widgets/common.dart';
import 'restore_tab.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.controller,
    required this.restore,
  });

  final BackupController controller;
  final RestoreController restore;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  BackupController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (c.phase == BackupPhase.idle) c.refresh();
  }

  String _subtitle() {
    final last = c.config.lastBackupAt;
    if (last == null) return 'Nenhum backup feito ainda';
    return 'Último backup ${formatAgo(last, DateTime.now())}';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final running =
              c.phase == BackupPhase.running || c.phase == BackupPhase.finished;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Backup',
                subtitle: _subtitle(),
                actions: [
                  if (c.phase == BackupPhase.idle)
                    IconButton(
                      tooltip: 'Procurar discos e navegadores de novo',
                      onPressed: c.loading ? null : c.refresh,
                      icon: const Icon(Symbols.refresh_rounded),
                    ),
                ],
              ),
              const TabBar(
                tabAlignment: TabAlignment.start,
                isScrollable: true,
                tabs: [
                  Tab(text: 'Fazer backup'),
                  Tab(text: 'Restaurar'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: running
                              ? _RunView(controller: c)
                              : _ConfigView(controller: c),
                        ),
                        if (running)
                          _RunBar(controller: c)
                        else
                          _ActionBar(controller: c),
                      ],
                    ),
                    RestoreTab(controller: widget.restore),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _report(BuildContext context, Future<String?> action) async {
  final message = await action;
  if (message == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _ConfigView extends StatelessWidget {
  const _ConfigView({required this.controller});

  final BackupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final problems = c.problems;
    final notices = c.notices;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (c.loading) const LinearProgressIndicator(),
              if (problems.isNotEmpty || notices.isNotEmpty) ...[
                _Messages(problems: problems, notices: notices),
                const SizedBox(height: 16),
              ],
              _DestinationCard(controller: c),
              const SizedBox(height: 16),
              _SourcesCard(controller: c),
              const SizedBox(height: 16),
              _BrowsersCard(controller: c),
              const SizedBox(height: 16),
              _SecretsCard(controller: c),
            ],
          ),
        ),
      ],
    );
  }
}

class _Messages extends StatelessWidget {
  const _Messages({required this.problems, required this.notices});

  final List<String> problems;
  final List<String> notices;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    Widget row(IconData icon, Color color, String message) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in problems) row(Symbols.error_rounded, scheme.error, m),
        for (final m in notices) row(Symbols.warning_rounded, sev.warning, m),
      ],
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.controller});

  final BackupController controller;

  Future<void> _pickFolder(BuildContext context) async {
    final path = await getDirectoryPath(confirmButtonText: 'Escolher');
    if (path == null) return;
    if (!context.mounted) return;
    _report(context, controller.chooseDestination(path));
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final target = c.config.target;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'Destino',
            'Onde o backup fica. Use um disco externo, de preferência em ext4.',
          ),
          if (c.disks.isEmpty && !c.loading)
            Text(
              'Nenhum disco externo encontrado. Conecte um disco ou escolha uma pasta.',
              style: text.bodyMedium,
            ),
          for (final d in c.disks)
            _DiskTile(
              disk: d,
              selected: c.destinationMount?.target == d.mountPoint,
              onTap: () async =>
                  _report(context, c.chooseDestination(d.mountPoint)),
            ),
          if (target != null && c.destination == null && !c.loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Conecte o disco ${target.label} para fazer o backup.',
                style: text.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
          if (c.backupDir != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text.rich(
                TextSpan(
                  text: 'O backup vai para ',
                  children: [
                    TextSpan(
                      text: c.backupDir,
                      style: const TextStyle(fontFamily: kMono),
                    ),
                  ],
                ),
                style: text.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickFolder(context),
                icon: const Icon(Symbols.folder_open_rounded),
                label: const Text('Escolher outra pasta…'),
              ),
              SizedBox(width: 260, child: _FolderNameField(controller: c)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiskTile extends StatelessWidget {
  const _DiskTile({
    required this.disk,
    required this.selected,
    required this.onTap,
  });

  final DiskTarget disk;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final problem = disk.problem;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: problem == null,
      onTap: problem == null ? onTap : null,
      leading: Icon(
        selected
            ? Symbols.radio_button_checked_rounded
            : Symbols.radio_button_unchecked_rounded,
        color: selected ? scheme.primary : null,
      ),
      title: Row(
        children: [
          Icon(
            disk.hotplug ? Symbols.usb_rounded : Symbols.hard_drive_rounded,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(disk.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Text(
        problem ??
            '${disk.fsType ?? '?'} · ${formatBytes(disk.available)} livres · '
                '${disk.mountPoint}',
        style: problem == null ? null : TextStyle(color: scheme.error),
      ),
    );
  }
}

class _FolderNameField extends StatefulWidget {
  const _FolderNameField({required this.controller});

  final BackupController controller;

  @override
  State<_FolderNameField> createState() => _FolderNameFieldState();
}

class _FolderNameFieldState extends State<_FolderNameField> {
  late final _text = TextEditingController(
    text: widget.controller.config.folderName,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    decoration: InputDecoration(
      labelText: 'Nome da pasta do backup',
      isDense: true,
      border: const OutlineInputBorder(),
      errorText: validBackupFolderName(_text.text)
          ? null
          : 'Sem "/" e não vazio',
    ),
    onChanged: (v) {
      setState(() {});
      widget.controller.setFolderName(v);
    },
  );
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.controller});

  final BackupController controller;

  Future<void> _add(BuildContext context) async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Adicionar',
      initialDirectory: controller.home,
    );
    if (path == null || !context.mounted) return;
    _report(context, controller.addSource(path));
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
            'Pastas',
            'Copiadas sem dependências, caches e builds ignorados pelo git. '
                'Cada uma vira uma pasta com o mesmo nome no backup.',
          ),
          if (c.config.sources.isEmpty)
            Text('Nenhuma pasta escolhida ainda.', style: text.bodyMedium),
          for (final s in c.config.sources)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Symbols.folder_rounded),
              title: Text(s.split('/').last),
              subtitle: Text(
                s,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  fontFamily: kMono,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.estimate?.bySource[s] case final stats?)
                    Text(
                      formatBytes(stats.totalBytes),
                      style: text.labelLarge?.copyWith(fontFeatures: kTabular),
                    ),
                  IconButton(
                    tooltip: 'Remover da lista',
                    onPressed: () => c.removeSource(s),
                    icon: const Icon(Symbols.close_rounded),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Symbols.create_new_folder_rounded),
              label: const Text('Adicionar pasta…'),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: c.config.mirror,
            onChanged: c.setMirror,
            title: const Text('Espelhar'),
            subtitle: const Text(
              'Remove do backup o que você apagou nas pastas de origem. '
              'Desligado, o backup só acumula e nunca apaga nada.',
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowsersCard extends StatelessWidget {
  const _BrowsersCard({required this.controller});

  final BackupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final selected = c.selectedBrowserIds;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'Navegadores',
            'Perfis sem cache: favoritos, histórico, extensões e senhas salvas.',
          ),
          if (c.browsers.isEmpty)
            const Text('Nenhum Brave, Chrome ou Chromium encontrado.'),
          for (final b in c.browsers)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: selected.contains(b.spec.id),
              onChanged: (_) => c.toggleBrowser(b.spec.id),
              title: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(b.spec.label),
                  if (c.openBrowsers.contains(b.spec.id))
                    Chip(
                      label: const Text('Aberto'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: sev.warningContainer,
                      labelStyle: TextStyle(color: sev.onWarningContainer),
                      side: BorderSide.none,
                    ),
                ],
              ),
              subtitle: b.profiles.isEmpty
                  ? null
                  : Text(
                      [
                        for (final p in b.profiles)
                          p.account == null
                              ? '${p.name} (sem sincronização)'
                              : '${p.name} · ${p.account}',
                      ].join('  ·  '),
                    ),
            ),
        ],
      ),
    );
  }
}

class _SecretsCard extends StatelessWidget {
  const _SecretsCard({required this.controller});

  final BackupController controller;

  Future<void> _addFile(BuildContext context) async {
    final file = await openFile(
      confirmButtonText: 'Adicionar',
      initialDirectory: controller.home,
    );
    if (file == null || !context.mounted) return;
    _report(context, controller.addSecret(file.path));
  }

  Future<void> _addFolder(BuildContext context) async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Adicionar',
      initialDirectory: controller.home,
    );
    if (path == null || !context.mounted) return;
    _report(context, controller.addSecret(path));
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final enabled = c.config.secretsEnabled;
    final selected = c.selectedSecrets;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: c.setSecretsEnabled,
            title: Text(
              'Chaves e configurações',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: const Text(
              'Num arquivo criptografado. A senha é pedida numa janela do '
              'sistema e não fica guardada no app. Sem ela, o arquivo não '
              'pode ser aberto: guarde-a num gerenciador de senhas.',
            ),
          ),
          if (enabled) ...[
            for (final item in c.secretChoices)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.contains(item),
                onChanged: (_) => c.toggleSecret(item),
                title: Text(
                  '~/$item',
                  style: const TextStyle(fontFamily: kMono),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _addFile(context),
                  icon: const Icon(Symbols.key_rounded),
                  label: const Text('Adicionar arquivo…'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _addFolder(context),
                  icon: const Icon(Symbols.folder_open_rounded),
                  label: const Text('Adicionar pasta…'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});

  final BackupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final est = c.estimate;
    final estimating = c.phase == BackupPhase.estimating;
    final scheme = Theme.of(context).colorScheme;
    final summary = estimating
        ? 'Calculando o tamanho…'
        : c.estimateError ??
              (est == null
                  ? 'O tamanho é calculado no início do backup.'
                  : '${formatBytes(est.totalBytes)} no backup · '
                        '${formatBytes(est.transferBytes)} a copiar agora');
    return BottomBar(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            summary,
            style: TextStyle(
              color: c.estimateError == null ? null : scheme.error,
              fontFeatures: kTabular,
            ),
          ),
        ),
        if (estimating)
          OutlinedButton(onPressed: c.cancel, child: const Text('Cancelar'))
        else
          OutlinedButton(
            onPressed: c.canRun ? c.calculate : null,
            child: const Text('Calcular'),
          ),
        FilledButton.icon(
          onPressed: c.canRun ? c.start : null,
          icon: const Icon(Symbols.backup_rounded),
          label: const Text('Fazer backup'),
        ),
      ],
    );
  }
}

class _RunBar extends StatelessWidget {
  const _RunBar({required this.controller});

  final BackupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return BottomBar(
      children: [
        if (c.phase == BackupPhase.running)
          OutlinedButton(onPressed: c.cancel, child: const Text('Cancelar'))
        else
          FilledButton(onPressed: c.dismiss, child: const Text('Concluir')),
      ],
    );
  }
}

class _RunView extends StatelessWidget {
  const _RunView({required this.controller});

  final BackupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = Theme.of(context).textTheme;
    final finished = c.phase == BackupPhase.finished;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (finished) ...[
                OutcomeBanner(
                  outcome: c.outcome,
                  done: 'Backup concluído.',
                  failed: 'O backup não terminou. Veja abaixo o que falhou.',
                  cancelled: 'Backup cancelado. O que já foi copiado continua no destino.',
                  warnings: 'Backup concluído com avisos.',
                ),
                const SizedBox(height: 16),
              ],
              SectionCard(
                child: Column(
                  children: [
                    for (final (i, step) in c.steps.indexed)
                      _StepRow(
                        step: step,
                        controller: c,
                        current: i == c.currentStep,
                        onRetry: finished && step.retryable
                            ? () => c.retry(i)
                            : null,
                      ),
                  ],
                ),
              ),
              if (finished && c.runBackupDir != null) ...[
                const SizedBox(height: 16),
                SelectableText.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Backup em '),
                      TextSpan(
                        text: c.runBackupDir,
                        style: const TextStyle(fontFamily: kMono),
                      ),
                      if (c.readmePath != null) ...[
                        const TextSpan(text: '\nComo restaurar: '),
                        TextSpan(
                          text: c.readmePath,
                          style: const TextStyle(fontFamily: kMono),
                        ),
                      ],
                    ],
                  ),
                  style: text.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.controller,
    required this.current,
    this.onRetry,
  });

  final BackupStep step;
  final BackupController controller;
  final bool current;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final leading = StepStatusIcon(step.status);
    final progress = controller.progress;
    final copying =
        current &&
        progress != null &&
        (step.kind == BackupStepKind.folders ||
            step.kind == BackupStepKind.browser);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Center(child: leading)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label, style: text.titleSmall),
                if (current && step.kind == BackupStepKind.secrets)
                  Text(
                    'Digite a senha na janela do sistema.',
                    style: text.bodyMedium?.copyWith(color: scheme.primary),
                  ),
                if (copying) CopyProgress(progress),
                if (step.message != null)
                  Text(
                    step.message!,
                    style: text.bodySmall?.copyWith(
                      color: step.status == BackupStepStatus.failed
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                if (step.warnings.isNotEmpty)
                  WarningsList(warnings: step.warnings),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Tentar de novo'),
                  ),
              ],
            ),
          ),
          if (step.bytes != null)
            Text(
              formatBytes(step.bytes!),
              style: text.labelLarge?.copyWith(fontFeatures: kTabular),
            ),
        ],
      ),
    );
  }
}
