import 'package:disk_cleanup/backup/backup_controller.dart';
import 'package:disk_cleanup/ui/pages/backup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../backup/backup_fakes.dart';
import '../../support/test_app.dart';

void main() {
  late BackupFixture f;
  late BackupController c;

  setUp(() {
    f = BackupFixture();
    c = BackupController(f.services, f.settings);
  });

  tearDown(() {
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
    await t.pumpWidget(testApp(BackupPage(controller: c)));
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
      expect(find.text('Fazer backup'), findsOneWidget);
      expect(find.textContaining('Último backup'), findsOneWidget);
    });
  }
}
