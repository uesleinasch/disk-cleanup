import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../backup/restore_planner.dart';
import '../../core/format.dart';
import 'common.dart';

class ConflictOption<T> {
  const ConflictOption(this.value, this.label);

  final T value;
  final String label;
}

class ConflictRuleBar<T> extends StatelessWidget {
  const ConflictRuleBar({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<ConflictOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final o in options)
          ButtonSegment(value: o.value, label: Text(o.label)),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.single),
    ),
  );
}

class ConflictReview<T> extends StatefulWidget {
  const ConflictReview({
    super.key,
    required this.conflicts,
    required this.options,
    required this.actionOf,
    required this.isOverridden,
    required this.onChanged,
    this.localLabel = 'No computador',
    this.backupLabel = 'No backup',
    this.now,
  });

  final List<RestoreConflict> conflicts;
  final List<ConflictOption<T>> options;
  final T Function(RestoreConflict) actionOf;
  final bool Function(RestoreConflict) isOverridden;
  final void Function(RestoreConflict, T?) onChanged;
  final String localLabel;
  final String backupLabel;
  final DateTime? now;

  @override
  State<ConflictReview<T>> createState() => _ConflictReviewState<T>();
}

class _ConflictReviewState<T> extends State<ConflictReview<T>> {
  static const _rowHeight = 76.0;
  static const _filterFrom = 8;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final query = _filter.trim().toLowerCase();
    final shown = query.isEmpty
        ? widget.conflicts
        : [
            for (final c in widget.conflicts)
              if (c.path.toLowerCase().contains(query)) c,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.conflicts.length >= _filterFrom)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Symbols.search_rounded),
                hintText: 'Filtrar por nome',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        SizedBox(
          height: min(shown.length, 6) * _rowHeight,
          child: ListView.builder(
            itemCount: shown.length,
            itemExtent: _rowHeight,
            itemBuilder: (context, i) =>
                _ConflictRow<T>(conflict: shown[i], review: widget),
          ),
        ),
        if (query.isNotEmpty && shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nenhum arquivo com "$_filter".',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

class _ConflictRow<T> extends StatelessWidget {
  const _ConflictRow({required this.conflict, required this.review});

  final RestoreConflict conflict;
  final ConflictReview<T> review;

  String _side(int? size, DateTime? date, DateTime now) => [
    size == null ? 'tamanho desconhecido' : formatBytes(size),
    if (date != null) 'alterado ${formatAgo(date, now)}',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final c = conflict;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final now = review.now ?? DateTime.now();
    final newer = c.backupIsNewer ? review.backupLabel : review.localLabel;
    final overridden = review.isOverridden(c);
    final secondary = text.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: kTabular,
    );
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: c.path,
                child: Text(
                  c.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontFamily: kMono),
                ),
              ),
              Text(
                '${review.localLabel}: '
                '${_side(c.localSize, c.localModified, now)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: secondary,
              ),
              Text(
                '${review.backupLabel}: '
                '${_side(c.backupSize, c.backupModified, now)}'
                '${newer == review.backupLabel ? ' · mais recente' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: secondary,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<T>(
          value: review.actionOf(c),
          underline: const SizedBox.shrink(),
          style: text.labelLarge?.copyWith(
            color: overridden ? scheme.primary : scheme.onSurface,
          ),
          items: [
            for (final o in review.options)
              DropdownMenuItem(value: o.value, child: Text(o.label)),
          ],
          onChanged: (v) => review.onChanged(c, v),
        ),
        SizedBox(
          width: 40,
          child: overridden
              ? IconButton(
                  tooltip: 'Voltar para a regra geral',
                  onPressed: () => review.onChanged(c, null),
                  icon: const Icon(Symbols.undo_rounded, size: 20),
                )
              : null,
        ),
      ],
    );
  }
}
