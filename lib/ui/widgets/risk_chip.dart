import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/models.dart';
import '../theme/severity_colors.dart';

class RiskStyle {
  const RiskStyle(this.label, this.icon, this.background, this.foreground);

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  static RiskStyle of(BuildContext context, RiskLevel level) {
    final scheme = Theme.of(context).colorScheme;
    final sev = Theme.of(context).extension<SeverityColors>()!;
    return switch (level) {
      RiskLevel.safe => RiskStyle(
        'Seguro',
        Symbols.check_circle_rounded,
        sev.successContainer,
        sev.onSuccessContainer,
      ),
      RiskLevel.attention => RiskStyle(
        'Atenção',
        Symbols.warning_rounded,
        sev.warningContainer,
        sev.onWarningContainer,
      ),
      RiskLevel.danger => RiskStyle(
        'Perigoso',
        Symbols.dangerous_rounded,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };
  }
}

class RiskChip extends StatelessWidget {
  const RiskChip({super.key, required this.level});

  final RiskLevel level;

  static const _explanations = {
    RiskLevel.safe: 'Seguro: é recriado automaticamente quando necessário.',
    RiskLevel.attention: 'Atenção: dá para recuperar, mas com esforço.',
    RiskLevel.danger: 'Perigoso: pode ser perda definitiva de dados.',
  };

  @override
  Widget build(BuildContext context) {
    final style = RiskStyle.of(context, level);
    return Tooltip(
      message: _explanations[level],
      child: Semantics(
        label: 'Risco: ${style.label.toLowerCase()}',
        excludeSemantics: true,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: style.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 16, fill: 1, color: style.foreground),
              const SizedBox(width: 4),
              Text(
                style.label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: style.foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RootRequiredIndicator extends StatelessWidget {
  const RootRequiredIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: 'Requer senha de administrador',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.admin_panel_settings_rounded, size: 16, color: color),
          const SizedBox(width: 2),
          Text(
            'requer admin',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
