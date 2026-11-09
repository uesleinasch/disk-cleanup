import 'package:disk_cleanup/disk/alert.dart';
import 'package:disk_cleanup/ui/shell/app_shell.dart';
import 'package:disk_cleanup/ui/shell/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

Future<void> pumpShell(
  WidgetTester t,
  Size size, {
  AlertLevel alert = AlertLevel.ok,
  AppDestination current = AppDestination.overview,
  ValueChanged<AppDestination>? onSelect,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    testApp(
      AppShell(
        current: current,
        onSelect: onSelect ?? (_) {},
        alert: alert,
        body: const SizedBox(),
      ),
    ),
  );
}

void main() {
  test('widthClassOf respeita os limites', () {
    expect(widthClassOf(839), WidthClass.medium);
    expect(widthClassOf(840), WidthClass.expanded);
    expect(widthClassOf(1199), WidthClass.expanded);
    expect(widthClassOf(1200), WidthClass.large);
  });

  testWidgets('rail compacto abaixo de 840', (t) async {
    await pumpShell(t, const Size(800, 600));
    expect(
      t.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isFalse,
    );
  });

  testWidgets('rail estendido a partir de 840, com os sete destinos em pt-BR', (
    t,
  ) async {
    await pumpShell(t, const Size(1000, 700));
    expect(
      t.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isTrue,
    );
    for (final l in [
      'Visão geral',
      'Diretórios',
      'Arquivos grandes',
      'Limpeza',
      'Docker',
      'Backup',
      'Configurações',
    ]) {
      expect(find.text(l), findsOneWidget);
    }
  });

  testWidgets('badge de alerta no destino Visão geral', (t) async {
    final handle = t.ensureSemantics();
    await pumpShell(t, const Size(1000, 700), alert: AlertLevel.warning);
    expect(find.bySemanticsLabel('Espaço em disco: atenção'), findsOneWidget);
    expect(find.byType(Badge), findsOneWidget);

    await pumpShell(t, const Size(1000, 700), alert: AlertLevel.critical);
    expect(find.bySemanticsLabel('Espaço em disco: crítico'), findsOneWidget);

    await pumpShell(t, const Size(1000, 700));
    expect(find.byType(Badge), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Espaço em disco')), findsNothing);
    handle.dispose();
  });

  testWidgets('atalhos Ctrl+1..7 e Ctrl+, navegam', (t) async {
    final selected = <AppDestination>[];
    await pumpShell(t, const Size(1000, 700), onSelect: selected.add);
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
    ]) {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(key);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.comma);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selected, [...AppDestination.values, AppDestination.settings]);
  });
}
