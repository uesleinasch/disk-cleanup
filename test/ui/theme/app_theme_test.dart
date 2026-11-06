import 'package:disk_cleanup/ui/theme/app_theme.dart';
import 'package:disk_cleanup/ui/theme/severity_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tema claro usa os hex do tokens.css', () {
    final t = buildTheme(Brightness.light);
    expect(t.useMaterial3, isTrue);
    expect(t.colorScheme.primary, const Color(0xFF006A6A));
    expect(t.colorScheme.surface, const Color(0xFFF4FBFA));
    expect(t.extension<SeverityColors>()!.warning, const Color(0xFF775A00));
    expect(t.textTheme.bodyMedium!.fontFamily, 'Roboto');
  });

  test('tema escuro', () {
    final t = buildTheme(Brightness.dark);
    expect(t.colorScheme.primary, const Color(0xFF80D5D4));
    expect(t.extension<SeverityColors>()!.success, const Color(0xFF76DAA1));
  });
}
