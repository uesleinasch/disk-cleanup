import 'dart:io';

import 'package:disk_cleanup/backup/backup_controller.dart';
import 'package:disk_cleanup/backup/restore_controller.dart';
import 'package:disk_cleanup/backup/restore_planner.dart';
import 'package:disk_cleanup/ui/pages/backup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../backup/backup_fakes.dart';
import '../../support/test_app.dart';

void main() {
  late BackupFixture f;
  late BackupController c;
  late RestoreController r;

  setUp(() {
    f = BackupFixture();
    c = BackupController(f.services, f.settings);
    r = RestoreController(f.services, f.settings, c);
  });

  tearDown(() {
    r.dispose();
    c.dispose();
    f.dispose();
  });

  Future<void> waitFor(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
    }
    expect(done(), isTrue, reason: 'a operação não terminou');
    await t.pumpAndSettle();
  }

  Future<void> settle(WidgetTester t) =>
      waitFor(t, () => !c.loading && c.disks.isNotEmpty);

  Future<void> pump(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(BackupPage(controller: c, restore: r)));
    await settle(t);
  }

  for (final size in const [Size(720, 560), Size(1920, 1080)]) {
    testWidgets('configuração sem overflow em $size', (t) async {
      f.openChrome();
      await pump(t, size);

      expect(find.text('Nenhum backup feito ainda'), findsOneWidget);
      expect(find.text('Escolha onde salvar o backup.'), findsOneWidget);
      expect(find.text('Disco externo'), findsOneWidget);
      expect(find.text('Google Chrome'), findsOneWidget);
      expect(find.text('Aberto'), findsOneWidget);
      expect(find.text('~/.ssh'), findsOneWidget);
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('escolher disco e pasta habilita o backup', (t) async {
    await pump(t, const Size(1280, 900));
    await t.tap(find.text('Disco externo'));
    await waitFor(t, () => c.destination == f.hd);
    String? error = 'pendente';
    c.addSource(p.join(f.home, 'projetos')).then((e) => error = e);
    await waitFor(t, () => error != 'pendente');
    expect(error, isNull);

    expect(find.text('Escolha onde salvar o backup.'), findsNothing);
    expect(find.text('projetos'), findsOneWidget);
    expect(find.textContaining(p.join(f.hd, 'backup')), findsOneWidget);
    expect(
      t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  for (final size in const [Size(720, 560), Size(1920, 1080)]) {
    testWidgets('acordeão mostra o que fica fora e inclui em $size', (t) async {
      f.file('projetos/web/node_modules/b/i.js');
      await pump(t, size);
      final src = p.join(f.home, 'projetos');
      String? error = 'pendente';
      c.addSource(src).then((e) => error = e);
      await waitFor(t, () => error != 'pendente');
      await t.runAsync(() => c.loadExclusions(src));

      final header = find.text('O que fica fora do backup');
      await t.ensureVisible(header);
      await t.pumpAndSettle();
      await t.tap(header);
      await t.pumpAndSettle();

      expect(find.textContaining(RegExp(r'^2 pastas, \d')), findsNWidgets(2));
      expect(find.text('node_modules'), findsOneWidget);
      final group = find.byKey(Key('tipo-$src-node_modules'));
      final box = find.descendant(of: group, matching: find.byType(Checkbox));
      await t.ensureVisible(box.first);
      await t.pumpAndSettle();
      await t.tap(box.first);
      final nothingOut = find.text('Nada fica fora desta pasta');
      await waitFor(t, () => nothingOut.evaluate().isNotEmpty);

      expect(c.inclusionsOf(src).kinds, {'node_modules'});
      expect(find.textContaining('todas entram no backup'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  for (final size in const [Size(720, 560), Size(1920, 1080)]) {
    testWidgets('resumo com navegador pulado sem overflow em $size', (t) async {
      f.openChrome();
      await pump(t, size);
      await t.runAsync(() async {
        await c.chooseDestination(f.hd);
        await c.addSource(p.join(f.home, 'projetos'));
        await c.start();
      });
      await t.pumpAndSettle();

      expect(find.text('Backup concluído com avisos.'), findsOneWidget);
      expect(
        find.text('Feche o Google Chrome e tente de novo.'),
        findsOneWidget,
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.text('Concluir'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.tap(find.text('Concluir'));
      await t.pump();
      await settle(t);
      expect(find.widgetWithText(FilledButton, 'Fazer backup'), findsOneWidget);
      expect(find.textContaining('Último backup'), findsOneWidget);
    });
  }

  Future<void> backupThenChange(WidgetTester t) async {
    await t.runAsync(() async {
      await c.chooseDestination(f.hd);
      await c.addSource(p.join(f.home, 'projetos'));
      await c.start();
      await c.dismiss();
      File(p.join(f.home, 'projetos/app/main.dart'))
        ..writeAsStringSync('editado')
        ..setLastModifiedSync(DateTime(2020));
    });
    await t.pumpAndSettle();
  }

  Future<void> openRestore(WidgetTester t) async {
    await t.runAsync(r.load);
    await t.tap(find.text('Restaurar'));
    await t.pumpAndSettle();
  }

  Future<void> analyzeProjects(WidgetTester t) async {
    await t.ensureVisible(find.text('projetos'));
    await t.pumpAndSettle();
    await t.tap(find.text('projetos'));
    await t.pump();
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Analisar'))
          .onPressed,
      isNotNull,
    );
    await t.runAsync(r.analyze);
    await t.pumpAndSettle();
  }

  for (final size in const [Size(720, 560), Size(1920, 1080)]) {
    testWidgets(
      'restaurar: escolha, revisão e resultado sem overflow em $size',
      (t) async {
        await pump(t, size);
        await backupThenChange(t);
        await openRestore(t);

        expect(find.text('Chaves e configurações'), findsOneWidget);
        expect(find.text('projetos'), findsOneWidget);
        expect(find.text('No lugar original'), findsOneWidget);
        expect(t.takeException(), isNull);

        await analyzeProjects(t);
        expect(r.phase, RestorePhase.reviewing);
        expect(find.textContaining('1 arquivo já existe'), findsOneWidget);
        expect(find.text('app/main.dart'), findsOneWidget);
        expect(find.text('Mais recente'), findsOneWidget);
        expect(t.takeException(), isNull);

        await t.tap(find.widgetWithText(FilledButton, 'Restaurar'));
        await t.pumpAndSettle();
        expect(find.text('Restaurar 1 arquivo?'), findsOneWidget);
        expect(
          find.textContaining('A versão atual fica guardada'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await t.tap(find.text('Cancelar'));
        await t.pumpAndSettle();
        expect(r.phase, RestorePhase.reviewing);

        await t.runAsync(r.start);
        await t.pumpAndSettle();
        expect(find.text('Restauração concluída.'), findsOneWidget);
        expect(find.text('Abrir pasta'), findsOneWidget);
        expect(
          File(p.join(f.home, 'projetos/app/main.dart')).readAsStringSync(),
          'void main() {}',
        );
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('decisão por arquivo vence a regra geral', (t) async {
    await pump(t, const Size(1280, 900));
    await backupThenChange(t);
    await openRestore(t);
    await analyzeProjects(t);
    expect(r.totals.replace, 1);

    await t.tap(find.byType(DropdownButton<ConflictAction>));
    await t.pumpAndSettle();
    await t.tap(find.text('Manter os dois').last);
    await t.pumpAndSettle();
    expect(r.totals.duplicate, 1);
    expect(find.byTooltip('Voltar para a regra geral'), findsOneWidget);

    await t.tap(find.byTooltip('Voltar para a regra geral'));
    await t.pump();
    expect(r.totals.duplicate, 0);
    expect(r.totals.replace, 1);

    await t.tap(find.text('Manter o atual'));
    await t.pump();
    expect(r.rule, ConflictAction.keepLocal);
    expect(r.totals.keep, 1);
  });

  Future<void> makePending(WidgetTester t) async {
    await t.runAsync(() async {
      await c.chooseDestination(f.hd);
      await c.addSource(p.join(f.home, 'projetos'));
      await c.setMirror(true);
      await c.start();
      await c.dismiss();
      final hd = p.join(f.hd, 'backup', 'projetos', 'app', 'main.dart');
      File(hd)
        ..writeAsStringSync('editado no disco')
        ..setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
      File(p.join(f.home, 'projetos/app/node_modules/dep/index.js'))
          .deleteSync();
      f.file('projetos/app/apagar-depois.txt');
      await c.start();
      await c.dismiss();
      File(p.join(f.home, 'projetos/app/apagar-depois.txt')).deleteSync();
      await c.start();
      await c.dismiss();
    });
    await t.pumpAndSettle();
  }

  for (final size in const [Size(720, 560), Size(1920, 1080)]) {
    testWidgets('pendentes: seções, decisão em lote e confirmação em $size', (
      t,
    ) async {
      await pump(t, size);
      await makePending(t);
      expect(c.pending.length, 2);
      expect(find.text('Pendentes (2)'), findsOneWidget);

      await t.tap(find.text('Pendentes (2)'));
      await t.pumpAndSettle();
      expect(find.text('Mais novos no disco (1)'), findsOneWidget);
      expect(find.text('projetos/app/main.dart'), findsOneWidget);
      expect(t.takeException(), isNull);

      final apply = find.widgetWithText(FilledButton, 'Aplicar');
      expect(t.widget<FilledButton>(apply).onPressed, isNull);

      await t.tap(find.text('Trazer o do disco').first);
      await t.pumpAndSettle();
      expect(find.text('Aplicar 1 decisão'), findsOneWidget);

      await t.ensureVisible(find.text('Seriam apagados do disco (1)'));
      await t.pumpAndSettle();
      expect(find.text('projetos/app/apagar-depois.txt'), findsOneWidget);
      expect(find.textContaining('não existe mais'), findsOneWidget);

      await t.tap(find.text('Aplicar 1 decisão'));
      await t.pumpAndSettle();
      expect(find.text('Aplicar 1 decisão?'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(c.pending.length, 2);
    });
  }
}
