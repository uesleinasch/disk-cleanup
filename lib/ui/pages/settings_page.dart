import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../settings/settings.dart';
import '../../settings/settings_controller.dart';
import '../../version.dart';
import '../widgets/common.dart';
import '../widgets/risk_chip.dart';
import '../../core/models.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final s = settings.value;
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: text.titleSmall?.copyWith(color: scheme.primary),
              ),
              const SizedBox(height: 8),
              Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: children),
                ),
              ),
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(title: 'Configurações'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        section('Alertas de espaço', [
                          _ThresholdTile(
                            level: RiskLevel.attention,
                            label: 'Atenção',
                            value: s.warnPercent,
                            bytes: s.warnBytes,
                            min: 5,
                            max: 40,
                            onChanged: (v) => settings.update(
                              (x) => x.copyWith(
                                warnPercent: v,
                                critPercent: x.critPercent >= v
                                    ? v - 1
                                    : x.critPercent,
                              ),
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          _ThresholdTile(
                            level: RiskLevel.danger,
                            label: 'Crítico',
                            value: s.critPercent,
                            bytes: s.critBytes,
                            min: 1,
                            max: 15,
                            onChanged: (v) => settings.update(
                              (x) => x.copyWith(
                                critPercent: v >= x.warnPercent
                                    ? x.warnPercent - 1
                                    : v,
                              ),
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: Text(
                              'O alerta aparece ao abrir o disk-cleanup.',
                              style: text.bodySmall,
                            ),
                          ),
                        ]),
                        section('Limpeza', [
                          SwitchListTile(
                            title: const Text('Proteger projetos ativos'),
                            subtitle: Text(
                              'Não pré-selecionar builds de projetos modificados nos últimos ${s.activeProjectDays} dias',
                            ),
                            value: s.protectActiveProjects,
                            onChanged: (v) => settings.update(
                              (x) => x.copyWith(protectActiveProjects: v),
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          _BuildRules(settings: settings),
                        ]),
                        section('Backup', [
                          _ReminderTile(
                            days: s.backup.reminderDays,
                            onChanged: (v) => settings.update(
                              (x) => x.copyWith(
                                backup: x.backup.copyWith(reminderDays: v),
                              ),
                            ),
                          ),
                        ]),
                        section('Aparência', [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                const Text('Tema'),
                                SegmentedButton<ThemeMode>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                      value: ThemeMode.system,
                                      icon: Icon(Symbols.computer_rounded),
                                      label: Text('Sistema'),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.light,
                                      icon: Icon(Symbols.light_mode_rounded),
                                      label: Text('Claro'),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.dark,
                                      icon: Icon(Symbols.dark_mode_rounded),
                                      label: Text('Escuro'),
                                    ),
                                  ],
                                  selected: {s.themeMode},
                                  onSelectionChanged: (v) => settings.update(
                                    (x) => x.copyWith(themeMode: v.first),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]),
                        section('Sobre', [
                          ListTile(
                            leading: Icon(
                              Symbols.data_usage_rounded,
                              fill: 1,
                              color: scheme.primary,
                              size: 32,
                            ),
                            title: const Text('disk-cleanup $kAppVersion'),
                            subtitle: const Text(
                              'AppImage · Licença MIT\n'
                              'Tamanhos em GB decimais (1 GB = 1.000.000.000 bytes); o df -h mostra GiB.',
                            ),
                            isThreeLine: true,
                          ),
                        ]),
                      ],
                    ),
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

class _ThresholdTile extends StatelessWidget {
  const _ThresholdTile({
    required this.level,
    required this.label,
    required this.value,
    required this.bytes,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final RiskLevel level;
  final String label;
  final int value;
  final int bytes;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final gb = (bytes / 1000000000).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RiskChip(level: level),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Avisar quando o espaço livre ficar abaixo de'),
              ),
              Text(
                '$value% ou $gb GB',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value%',
            semanticFormatterCallback: (v) => '$label: ${v.round()}%',
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  static const _max = 30;

  @override
  Widget build(BuildContext context) {
    final label = days == 0 ? 'Desligado' : 'A cada $days dias';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Lembrar de fazer backup na Visão geral'),
              ),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          Slider(
            value: days.clamp(0, _max).toDouble(),
            max: _max.toDouble(),
            divisions: _max,
            label: label,
            semanticFormatterCallback: (_) => 'Lembrete de backup: $label',
            onChanged: (v) => onChanged(v.round()),
          ),
          Text(
            'Arraste até o início para desligar.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BuildRules extends StatelessWidget {
  const _BuildRules({required this.settings});

  final SettingsController settings;

  Future<void> _add(BuildContext context) async {
    final rule = await showDialog<BuildRule>(
      context: context,
      builder: (_) => const _RuleDialog(),
    );
    if (rule == null) return;
    await settings.update(
      (s) => s.copyWith(buildRules: [...s.buildRules, rule]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules = settings.value.buildRules;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pastas de build reconhecidas'),
          Text(
            'Só apagadas quando o arquivo marcador está ao lado',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in rules)
                InputChip(
                  label: Text(
                    '${r.dirName} ← ${r.marker}',
                    style: const TextStyle(fontFamily: kMono),
                  ),
                  deleteButtonTooltipMessage: 'Remover ${r.dirName}',
                  onDeleted: () => settings.update(
                    (s) => s.copyWith(buildRules: [...s.buildRules]..remove(r)),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Symbols.add_rounded),
                label: const Text('Adicionar'),
                onPressed: () => _add(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog();

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  final _name = TextEditingController();
  final _marker = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _marker.dispose();
    super.dispose();
  }

  bool get _valid {
    final n = _name.text.trim();
    return n.isNotEmpty &&
        !n.contains('/') &&
        n != '.' &&
        n != '..' &&
        _marker.text.trim().isNotEmpty &&
        !_marker.text.contains('/');
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nova pasta de build'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nome da pasta (ex.: out)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _marker,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText:
                  'Arquivo marcador ao lado (ex.: package.json, *.csproj)',
              border: OutlineInputBorder(),
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
        onPressed: _valid
            ? () => Navigator.pop(
                context,
                BuildRule(_name.text.trim(), _marker.text.trim()),
              )
            : null,
        child: const Text('Adicionar'),
      ),
    ],
  );
}
