import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../backup/backup_controller.dart';
import '../../backup/rsync_runner.dart';
import '../../core/format.dart';
import '../theme/severity_colors.dart';
import 'common.dart';

class CardTitle extends StatelessWidget {
  const CardTitle(this.title, this.description, {super.key});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          Text(
            description,
            style: text.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: children,
    ),
  );
}

class StepStatusIcon extends StatelessWidget {
  const StepStatusIcon(this.status, {super.key});

  final BackupStepStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    return switch (status) {
      BackupStepStatus.running => const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      BackupStepStatus.pending => Icon(
        Symbols.radio_button_unchecked_rounded,
        color: scheme.outline,
      ),
      BackupStepStatus.done => Icon(
        Symbols.check_circle_rounded,
        fill: 1,
        color: sev.success,
      ),
      BackupStepStatus.warnings => Icon(
        Symbols.warning_rounded,
        fill: 1,
        color: sev.warning,
      ),
      BackupStepStatus.skipped => Icon(
        Symbols.do_not_disturb_on_rounded,
        color: sev.warning,
      ),
      BackupStepStatus.failed => Icon(
        Symbols.error_rounded,
        fill: 1,
        color: scheme.error,
      ),
      BackupStepStatus.cancelled => Icon(
        Symbols.cancel_rounded,
        color: scheme.outline,
      ),
    };
  }
}

class OutcomeBanner extends StatelessWidget {
  const OutcomeBanner({
    super.key,
    required this.outcome,
    required this.done,
    required this.failed,
    required this.cancelled,
    required this.warnings,
  });

  final BackupStepStatus outcome;
  final String done;
  final String failed;
  final String cancelled;
  final String warnings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    final (icon, bg, fg, title) = switch (outcome) {
      BackupStepStatus.done => (
        Symbols.check_circle_rounded,
        sev.successContainer,
        sev.onSuccessContainer,
        done,
      ),
      BackupStepStatus.failed => (
        Symbols.error_rounded,
        scheme.errorContainer,
        scheme.onErrorContainer,
        failed,
      ),
      BackupStepStatus.cancelled => (
        Symbols.cancel_rounded,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        cancelled,
      ),
      _ => (
        Symbols.warning_rounded,
        sev.warningContainer,
        sev.onWarningContainer,
        warnings,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, fill: 1, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatRemaining(Duration d) {
  if (d.inMinutes < 1) return 'menos de 1 min';
  if (d.inHours < 1) return '${d.inMinutes} min';
  return '${d.inHours} h ${d.inMinutes % 60} min';
}

class CopyProgress extends StatelessWidget {
  const CopyProgress(this.progress, {super.key});

  final RsyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        LinearProgressIndicator(value: progress.percent / 100),
        const SizedBox(height: 4),
        Text(
          '${progress.percent}% · ${formatBytes(progress.bytes)} copiados · '
          '${formatBytes(progress.bytesPerSecond)}/s · '
          'faltam ${formatRemaining(progress.remaining)}',
          style: text.bodySmall?.copyWith(fontFeatures: kTabular),
        ),
      ],
    );
  }
}

class WarningsList extends StatelessWidget {
  const WarningsList({super.key, required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text('Ver ${warnings.length} avisos', style: text.bodyMedium),
      children: [
        for (final w in warnings.take(50))
          Text(w, style: text.bodySmall?.copyWith(fontFamily: kMono)),
        if (warnings.length > 50)
          Text('e mais ${warnings.length - 50}', style: text.bodySmall),
      ],
    );
  }
}
