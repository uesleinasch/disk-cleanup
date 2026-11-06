import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../disk/alert.dart';
import '../../disk/disk_info.dart';
import '../../scan/scan_controller.dart';
import '../../settings/settings_controller.dart';
import '../cleanup_flow.dart';
import '../shell/app_shell.dart';
import '../theme/severity_colors.dart';
import '../widgets/common.dart';
import '../widgets/disk_usage_bar.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.scan,
    required this.flow,
    required this.settings,
    required this.onNavigate,
  });

  final ScanController scan;
  final CleanupFlow flow;
  final SettingsController settings;
  final ValueChanged<AppDestination> onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([scan, settings]),
      builder: (context, _) {
        final state = scan.state;
        final s = settings.value;
        final now = scan.services.now();
        final snoozed =
            s.bannerSnoozedUntil != null && s.bannerSnoozedUntil!.isAfter(now);
        final volume = state.systemVolume;
        final preselected = scan.preselected;
        final safeBytes = preselected.fold(0, (a, i) => a + i.bytes);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Visão geral',
              subtitle: state.updatedAt == null
                  ? 'Ainda não varrido'
                  : 'Atualizado ${formatAgo(state.updatedAt!, now)}',
              actions: [
                IconButton(
                  tooltip: 'Atualizar varredura (F5)',
                  onPressed: scan.running ? null : scan.scan,
                  icon: const Icon(Symbols.refresh_rounded),
                ),
              ],
            ),
            if (scan.running)
              ScanProgressView(progress: state.progress, onCancel: scan.cancel),
            if (state.alert != AlertLevel.ok && !snoozed && volume != null)
              AlertBanner(
                level: state.alert,
                volume: volume,
                safeBytes: safeBytes,
                warnPercent: s.warnPercent,
                onSnooze: () => settings.update(
                  (v) => v.copyWith(
                    bannerSnoozedUntil: now.add(const Duration(days: 1)),
                  ),
                ),
                onShowWhatToFree: () => flow.run(context, preselected),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TwoUp(
                        left: volume == null
                            ? null
                            : _DiskCard(
                                volume: volume,
                                alert: state.alert,
                                recoverable: state.recoverableBytes,
                              ),
                        right: preselected.isEmpty
                            ? const _NothingToFree()
                            : _SafeCard(
                                items: preselected,
                                onFree: () => flow.run(context, preselected),
                              ),
                      ),
                      const SizedBox(height: 16),
                      if (state.consumers.isNotEmpty)
                        SectionCard(
                          child: ConsumerBarList(
                            consumers: state.consumers,
                            onSeeAll: () =>
                                onNavigate(AppDestination.directories),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _OtherVolumes(volumes: state.volumes),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TwoUp extends StatelessWidget {
  const _TwoUp({required this.left, required this.right});

  final Widget? left;
  final Widget right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (left == null) return right;
      if (c.maxWidth < 860) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left!, const SizedBox(height: 16), right],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: left!),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: right),
        ],
      );
    },
  );
}

class _DiskCard extends StatelessWidget {
  const _DiskCard({
    required this.volume,
    required this.alert,
    required this.recoverable,
  });

  final VolumeUsage volume;
  final AlertLevel alert;
  final int recoverable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    final text = Theme.of(context).textTheme;
    final (bg, fg, icon, label) = switch (alert) {
      AlertLevel.ok => (
        sev.successContainer,
        sev.onSuccessContainer,
        Symbols.check_circle_rounded,
        'Saudável',
      ),
      AlertLevel.warning => (
        sev.warningContainer,
        sev.onWarningContainer,
        Symbols.warning_rounded,
        'Atenção',
      ),
      AlertLevel.critical => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Symbols.error_rounded,
        'Crítico',
      ),
    };
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.hard_drive_rounded, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Disco do sistema  ',
                    style: text.titleMedium,
                    children: [
                      TextSpan(
                        text: '/ · ${volume.device.split('/').last}',
                        style: text.bodySmall?.copyWith(
                          fontFamily: kMono,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, fill: 1, color: fg),
                    const SizedBox(width: 6),
                    Text(label, style: text.labelMedium?.copyWith(color: fg)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            children: [
              Text(
                '${formatBytes(volume.available)} livres',
                style: text.displaySmall?.copyWith(fontFeatures: kTabular),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'de ${formatBytes(volume.size)} '
                  '(${formatPercent(volume.freeFraction)})',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          DiskUsageBar(
            used: volume.used,
            recoverable: recoverable,
            reserved: volume.reserved,
            free: volume.available,
            capacity: volume.size,
          ),
        ],
      ),
    );
  }
}

class _SafeCard extends StatelessWidget {
  const _SafeCard({required this.items, required this.onFree});

  final List<CleanupItem> items;
  final VoidCallback onFree;

  static const _groups = {
    CleanupCategory.cache: 'Caches de pacotes e navegadores',
    CleanupCategory.docker: 'Build cache do Docker',
    CleanupCategory.build: 'Builds sem uso recente',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = items.fold(0, (a, i) => a + i.bytes);
    final byGroup = <CleanupCategory, int>{};
    for (final i in items) {
      byGroup[i.category] = (byGroup[i.category] ?? 0) + i.bytes;
    }
    final fg = scheme.onPrimaryContainer;
    return SectionCard(
      color: scheme.primaryContainer,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.cleaning_services_rounded, color: fg),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Pode liberar com segurança',
                    style: text.titleMedium?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              formatBytes(total),
              style: text.headlineLarge?.copyWith(
                color: fg,
                fontFeatures: kTabular,
              ),
            ),
            const SizedBox(height: 12),
            for (final e in byGroup.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(_groups[e.key] ?? e.key.name)),
                    Text(
                      formatBytes(e.value),
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontFeatures: kTabular,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Tudo é recriado automaticamente quando necessário.',
              style: text.bodySmall?.copyWith(color: fg),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onFree,
              icon: const Icon(Symbols.mop_rounded),
              label: Text('Liberar ${formatBytes(total)} com segurança'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingToFree extends StatelessWidget {
  const _NothingToFree();

  @override
  Widget build(BuildContext context) {
    final sev = Theme.of(context).extension<SeverityColors>()!;
    final text = Theme.of(context).textTheme;
    return SectionCard(
      color: sev.successContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Symbols.check_circle_rounded,
            fill: 1,
            size: 32,
            color: sev.onSuccessContainer,
          ),
          const SizedBox(height: 12),
          Text(
            'Nada seguro para limpar agora',
            style: text.titleMedium?.copyWith(color: sev.onSuccessContainer),
          ),
          Text(
            'Arquivos grandes e itens de Docker com risco continuam nas telas próprias.',
            style: text.bodyMedium?.copyWith(color: sev.onSuccessContainer),
          ),
        ],
      ),
    );
  }
}

class _OtherVolumes extends StatelessWidget {
  const _OtherVolumes({required this.volumes});

  final List<VolumeUsage> volumes;

  @override
  Widget build(BuildContext context) {
    final others = volumes.where((v) => v.mountPoint != '/').toList();
    if (others.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Outros volumes',
          style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final v in others)
              Container(
                width: 300,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.mountPoint,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(fontFamily: kMono),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: v.size == 0 ? 0 : v.used / v.size,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${formatBytes(v.available)} livres de ${formatBytes(v.size)}',
                      style: text.bodySmall?.copyWith(fontFeatures: kTabular),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
