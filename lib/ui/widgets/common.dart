import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/format.dart';
import '../../disk/alert.dart';
import '../../disk/disk_info.dart';
import '../../scan/preselect.dart';
import '../../scan/scan_state.dart';
import '../theme/severity_colors.dart';

const kMono = 'RobotoMono';
const kTabular = [FontFeature.tabularFigures()];

String formatPercent(double fraction) =>
    '${(fraction * 100).toStringAsFixed(1).replaceAll('.', ',')}%';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class AlertBanner extends StatelessWidget {
  const AlertBanner({
    super.key,
    required this.level,
    required this.volume,
    required this.safeSize,
    required this.warnPercent,
    required this.onSnooze,
    required this.onShowWhatToFree,
  });

  final AlertLevel level;
  final VolumeUsage volume;
  final String? safeSize;
  final int warnPercent;
  final VoidCallback onSnooze;
  final VoidCallback? onShowWhatToFree;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    final critical = level == AlertLevel.critical;
    final bg = critical ? scheme.errorContainer : sev.warningContainer;
    final fg = critical ? scheme.onErrorContainer : sev.onWarningContainer;
    final free = formatBytes(volume.available);
    final pct = formatPercent(volume.freeFraction);
    final title = critical
        ? 'Disco quase cheio: restam $free ($pct)'
        : 'Espaço em disco baixo: restam $free ($pct)';
    final body = switch ((critical, safeSize)) {
      (true, null) =>
        'Programas podem falhar ao salvar arquivos. Libere espaço agora.',
      (true, final size?) =>
        'Programas podem falhar ao salvar arquivos. Libere espaço agora: '
            '$size podem sair com segurança.',
      (false, null) => 'O limite de atenção é $warnPercent% livre.',
      (false, final size?) =>
        'O limite de atenção é $warnPercent% livre. Dá para liberar '
            '$size com segurança sem tocar em arquivos pessoais.',
    };
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Icon(
              critical ? Symbols.error_rounded : Symbols.warning_rounded,
              fill: 1,
              color: fg,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium?.copyWith(color: fg)),
                  Text(body, style: text.bodyMedium?.copyWith(color: fg)),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: fg),
                  onPressed: onSnooze,
                  child: const Text('Adiar 1 dia'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: fg),
                  onPressed: onShowWhatToFree,
                  child: const Text('Ver o que liberar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

IconData consumerIcon(ConsumerKind kind) => switch (kind) {
  ConsumerKind.directory => Symbols.folder_rounded,
  ConsumerKind.file => Symbols.draft_rounded,
  ConsumerKind.docker => Symbols.deployed_code_rounded,
  ConsumerKind.system => Symbols.memory_rounded,
};

class SizeBarRow extends StatelessWidget {
  const SizeBarRow({
    super.key,
    required this.label,
    required this.bytes,
    required this.fraction,
    this.path,
    this.icon,
  });

  final String label;
  final String? path;
  final int bytes;
  final double fraction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, c) {
        final labelWidth = c.maxWidth < 500 ? c.maxWidth * 0.4 : 220.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
              ],
              SizedBox(
                width: labelWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: text.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (path != null)
                      Tooltip(
                        message: path!,
                        child: Text(
                          path!,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            fontFamily: kMono,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0, 1),
                    minHeight: 12,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 84,
                child: Tooltip(
                  message: formatBytesExact(bytes),
                  child: Text(
                    formatBytes(bytes),
                    textAlign: TextAlign.right,
                    style: text.labelLarge?.copyWith(fontFeatures: kTabular),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ConsumerBarList extends StatelessWidget {
  const ConsumerBarList({
    super.key,
    required this.consumers,
    this.limit = 7,
    this.onSeeAll,
  });

  final List<Consumer> consumers;
  final int limit;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final shown = consumers.take(limit).toList();
    final max = shown.isEmpty ? 1 : shown.first.bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'O que mais ocupa espaço',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (consumers.length > limit && onSeeAll != null)
              TextButton(onPressed: onSeeAll, child: const Text('Ver todos')),
          ],
        ),
        const SizedBox(height: 8),
        for (final c in shown)
          SizeBarRow(
            label: c.label,
            path: c.path,
            bytes: c.bytes,
            fraction: c.bytes / (max == 0 ? 1 : max),
            icon: consumerIcon(c.kind),
          ),
      ],
    );
  }
}

class ScanProgressView extends StatelessWidget {
  const ScanProgressView({super.key, required this.progress, this.onCancel});

  final ScanProgressInfo progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final total = progress.totalDirs == 0 ? 1 : progress.totalDirs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: progress.doneDirs / total),
                const SizedBox(height: 4),
                Text(
                  'Varrendo… ${progress.currentDir}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: onCancel, child: const Text('Cancelar')),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                fill: 1,
                color: iconColor ?? scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                body,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
    child: Padding(padding: const EdgeInsets.all(24), child: child),
  );
}

class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: child,
    ),
  );
}
