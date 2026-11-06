import 'package:disk_cleanup/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes usa unidades decimais com vírgula', () {
    expect(formatBytes(44000000000), '44,0 GB');
    expect(formatBytes(502500000000), '502,5 GB');
    expect(formatBytes(999), '999 B');
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1000), '1,0 KB');
    expect(formatBytes(1500000), '1,5 MB');
    expect(formatBytes(1250000000000), '1,3 TB');
  });

  test('formatBytesExact usa ponto como separador de milhar', () {
    expect(formatBytesExact(44000000000), '44.000.000.000 bytes');
    expect(formatBytesExact(12), '12 bytes');
    expect(formatBytesExact(1234), '1.234 bytes');
  });

  test('formatAgo cobre todas as faixas', () {
    final now = DateTime(2026, 11, 6, 12);
    String ago(Duration d) => formatAgo(now.subtract(d), now);
    expect(ago(const Duration(seconds: 20)), 'agora');
    expect(ago(const Duration(minutes: 3)), 'há 3 min');
    expect(ago(const Duration(hours: 5)), 'há 5 h');
    expect(ago(const Duration(days: 1)), 'ontem');
    expect(ago(const Duration(days: 5)), 'há 5 dias');
    expect(ago(const Duration(days: 30)), 'há 1 mês');
    expect(ago(const Duration(days: 95)), 'há 3 meses');
    expect(ago(const Duration(days: 400)), 'há 1 ano');
    expect(ago(const Duration(days: 800)), 'há 2 anos');
  });
}
