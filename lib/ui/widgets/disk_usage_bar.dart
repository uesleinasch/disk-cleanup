import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/format.dart';

class DiskUsageBar extends StatelessWidget {
  const DiskUsageBar({
    super.key,
    required this.used,
    required this.recoverable,
    required this.reserved,
    required this.free,
    required this.capacity,
  });

  final int used;
  final int recoverable;
  final int reserved;
  final int free;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rec = min(recoverable, used);
    final inUse = used - rec;
    final segments = [
      (inUse, scheme.primary, false),
      (rec, scheme.tertiary, true),
      (max(reserved, 0), scheme.outline, false),
      (max(free, 0), scheme.surfaceContainerHighest, false),
    ];
    final label =
        'Uso do disco: ${formatBytes(inUse)} em uso, ${formatBytes(rec)} '
        'recuperáveis, ${formatBytes(max(reserved, 0))} reservados, '
        '${formatBytes(free)} livres de ${formatBytes(capacity)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: label,
          excludeSemantics: true,
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outline),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                for (final (bytes, color, striped) in segments)
                  if (bytes > 0)
                    Expanded(
                      flex: max(1, (bytes * 1000 / max(capacity, 1)).round()),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: striped
                            ? CustomPaint(
                                painter: _StripePainter(
                                  color,
                                  scheme.tertiaryContainer,
                                ),
                              )
                            : ColoredBox(color: color),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _Legend(color: scheme.primary, label: 'Em uso', bytes: inUse),
            _Legend(
              color: scheme.tertiary,
              label: 'Recuperável',
              bytes: rec,
              striped: true,
            ),
            _Legend(
              color: scheme.outline,
              label: 'Reservado pelo sistema',
              bytes: max(reserved, 0),
            ),
            _Legend(
              color: scheme.surfaceContainerHighest,
              label: 'Livre',
              bytes: free,
              bordered: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.bytes,
    this.striped = false,
    this.bordered = false,
  });

  final Color color;
  final String label;
  final int bytes;
  final bool striped;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.bodyMedium;
    return Tooltip(
      message: formatBytesExact(bytes),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: striped ? null : color,
              border: bordered ? Border.all(color: scheme.outline) : null,
              borderRadius: BorderRadius.circular(3),
            ),
            clipBehavior: Clip.antiAlias,
            child: striped
                ? CustomPaint(
                    painter: _StripePainter(color, scheme.tertiaryContainer),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, style: text, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          Text(
            formatBytes(bytes),
            style: text?.copyWith(
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  _StripePainter(this.stripe, this.background);

  final Color stripe;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..color = stripe
      ..strokeWidth = 4;
    for (double x = -size.height; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) =>
      old.stripe != stripe || old.background != background;
}
