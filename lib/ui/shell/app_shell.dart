import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../disk/alert.dart';
import '../theme/severity_colors.dart';
import 'responsive.dart';

enum AppDestination {
  overview('Visão geral', Symbols.space_dashboard_rounded),
  directories('Diretórios', Symbols.folder_special_rounded),
  largeFiles('Arquivos grandes', Symbols.description_rounded),
  cleanup('Limpeza', Symbols.cleaning_services_rounded),
  docker('Docker', Symbols.deployed_code_rounded),
  backup('Backup', Symbols.backup_rounded),
  settings('Configurações', Symbols.settings_rounded);

  const AppDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.current,
    required this.onSelect,
    required this.alert,
    required this.body,
    this.backupRunning = false,
    this.backupPending = 0,
  });

  final AppDestination current;
  final ValueChanged<AppDestination> onSelect;
  final AlertLevel alert;
  final Widget body;
  final bool backupRunning;
  final int backupPending;

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final extended = widthClassOf(width).index >= WidthClass.expanded.index;

    final bindings = <ShortcutActivator, VoidCallback>{
      for (final d in AppDestination.values)
        if (d.index < _digits.length)
          SingleActivator(_digits[d.index], control: true): () => onSelect(d),
      const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
          onSelect(AppDestination.settings),
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Row(
          children: [
            NavigationRail(
              extended: extended,
              minWidth: 80,
              minExtendedWidth: 220,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              selectedIndex: current.index,
              onDestinationSelected: (i) => onSelect(AppDestination.values[i]),
              destinations: [
                for (final d in AppDestination.values)
                  NavigationRailDestination(
                    icon: _icon(context, d, selected: false),
                    selectedIcon: _icon(context, d, selected: true),
                    label: Text(d.label),
                  ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _icon(
    BuildContext context,
    AppDestination d, {
    required bool selected,
  }) {
    final icon = Icon(d.icon, fill: selected ? 1 : 0);
    if (d == AppDestination.backup) return _backupIcon(context, icon);
    if (d != AppDestination.overview || alert == AlertLevel.ok) return icon;

    final scheme = Theme.of(context).colorScheme;
    final severity = Theme.of(context).extension<SeverityColors>()!;
    final critical = alert == AlertLevel.critical;
    return Semantics(
      container: true,
      label: critical ? 'Espaço em disco: crítico' : 'Espaço em disco: atenção',
      child: Badge(
        backgroundColor: critical ? scheme.error : severity.warning,
        textColor: critical ? scheme.onError : severity.onWarning,
        child: icon,
      ),
    );
  }

  Widget _backupIcon(BuildContext context, Widget icon) {
    if (backupPending > 0) {
      return Semantics(
        container: true,
        label: 'Backup: $backupPending pendentes',
        child: Badge.count(count: backupPending, child: icon),
      );
    }
    if (!backupRunning) return icon;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Backup em andamento',
      child: Badge(backgroundColor: scheme.primary, child: icon),
    );
  }
}
