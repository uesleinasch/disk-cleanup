import 'package:disk_cleanup/cleanup/privileged_runner.dart';
import 'package:disk_cleanup/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

CleanupItem item(CleanupAction action) => CleanupItem(
  id: 'x',
  category: CleanupCategory.cache,
  title: 'Cache',
  path: '/tmp/x',
  note: 'nota',
  bytes: 123,
  risk: RiskLevel.attention,
  requiresRoot: false,
  preselected: true,
  lastModified: DateTime.utc(2026, 1, 2, 3),
  action: action,
);

void main() {
  test('RiskLevel segue a ordem de gravidade', () {
    expect(RiskLevel.values, [
      RiskLevel.safe,
      RiskLevel.attention,
      RiskLevel.danger,
    ]);
  });

  test('CleanupItem faz round-trip JSON para cada ação', () {
    final actions = <CleanupAction>[
      const DeletePathsAction(['/a', '/b']),
      const TrashPathsAction(['/c']),
      const EmptyTrashAction(),
      const DockerAction(DockerOp.removeImages, ['i1', 'i2']),
      RootAction([JournalVacuum(), SnapRemoveRevision('core20', '1')]),
    ];
    for (final a in actions) {
      final back = CleanupItem.fromJson(item(a).toJson());
      expect(back.toJson(), item(a).toJson());
      expect(back.action.runtimeType, a.runtimeType);
      expect(back.lastModified, DateTime.utc(2026, 1, 2, 3));
      expect(back.risk, RiskLevel.attention);
    }
    final root =
        CleanupItem.fromJson(
              item(
                RootAction([
                  JournalVacuum(),
                  SnapRemoveRevision('core20', '1'),
                ]),
              ).toJson(),
            ).action
            as RootAction;
    expect(root.commands.map((c) => c.toShell()), [
      '/usr/bin/journalctl --vacuum-size=500M',
      "/usr/bin/snap remove 'core20' --revision='1'",
    ]);
  });

  test('lastModified e path nulos sobrevivem ao round-trip', () {
    final i = CleanupItem(
      id: 'y',
      category: CleanupCategory.trash,
      title: 't',
      note: '',
      bytes: 0,
      risk: RiskLevel.safe,
      requiresRoot: false,
      preselected: false,
      action: const EmptyTrashAction(),
    );
    final back = CleanupItem.fromJson(i.toJson());
    expect(back.path, isNull);
    expect(back.lastModified, isNull);
  });
}
