import 'package:disk_cleanup/core/models.dart';
import 'package:disk_cleanup/disk/alert.dart';
import 'package:disk_cleanup/disk/disk_info.dart';
import 'package:disk_cleanup/scan/du_scanner.dart';
import 'package:disk_cleanup/scan/preselect.dart';
import 'package:disk_cleanup/scan/scan_controller.dart';
import 'package:disk_cleanup/scan/scan_state.dart';
import 'package:disk_cleanup/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

CleanupItem item({
  CleanupCategory category = CleanupCategory.cache,
  RiskLevel risk = RiskLevel.safe,
  bool root = false,
  DateTime? modified,
}) => CleanupItem(
  id: 'x',
  category: category,
  title: 't',
  note: 'n',
  bytes: 10,
  risk: risk,
  requiresRoot: root,
  preselected: true,
  lastModified: modified,
  action: const DeletePathsAction(['/h/x']),
);

VolumeUsage vol(String mp, int size, int avail) => VolumeUsage(
  device: 'd',
  fsType: 'ext4',
  mountPoint: mp,
  size: size,
  used: size - avail,
  available: avail,
);

void main() {
  final s = Settings.defaults('/h');
  final now = DateTime(2026, 11, 6);

  test('shouldPreselect', () {
    expect(shouldPreselect(item(), s, now), isTrue);
    expect(shouldPreselect(item(root: true), s, now), isFalse);
    expect(shouldPreselect(item(risk: RiskLevel.attention), s, now), isFalse);
    expect(shouldPreselect(item(), s, now, appRunning: true), isFalse);
    final build = CleanupCategory.build;
    expect(
      shouldPreselect(
        item(category: build, modified: now.subtract(const Duration(days: 3))),
        s,
        now,
      ),
      isFalse,
    );
    expect(
      shouldPreselect(
        item(category: build, modified: now.subtract(const Duration(days: 30))),
        s,
        now,
      ),
      isTrue,
    );
  });

  test('composeConsumers ordena, deduplica e inclui Docker', () {
    final consumers = composeConsumers(
      home: '/h',
      mapped: {
        '/h': const DuResult(
          entries: [
            DirEntrySize('/h/ueslei', 61200000000),
            DirEntrySize('/h/trabalho', 46200000000),
            DirEntrySize('/h/.cache', 38700000000),
          ],
          total: 146100000000,
          errors: 0,
          permissionDenied: false,
        ),
        '/h/trabalho': const DuResult(
          entries: [],
          total: 46200000000,
          errors: 0,
          permissionDenied: false,
        ),
      },
      dockerBytes: 83800000000,
    );
    expect(consumers.map((c) => c.label), [
      'Docker',
      'ueslei',
      'trabalho',
      '.cache',
    ]);
    expect(consumers.first.path, '/var/lib/docker');
  });

  test('worstAlert considera volume de diretório mapeado', () {
    final volumes = [
      vol('/', 502500000000, 200000000000),
      vol('/media/u/Dados', 1000000000000, 20000000000),
    ];
    expect(worstAlert(volumes, ['/h'], s), AlertLevel.ok);
    expect(
      worstAlert(volumes, ['/h', '/media/u/Dados/fotos'], s),
      AlertLevel.critical,
    );
  });

  test('ScanState sobrevive a toJson/fromJson', () {
    final state = ScanState(
      updatedAt: now,
      volumes: [vol('/', 100, 10)],
      alert: AlertLevel.warning,
      items: [item()],
      lockedDirs: const {'/var/lib/docker'},
    );
    final back = ScanState.fromJson(state.toJson());
    expect(back.updatedAt, now);
    expect(back.systemVolume!.available, 10);
    expect(back.alert, AlertLevel.warning);
    expect(back.items.single.id, 'x');
    expect(back.lockedDirs, {'/var/lib/docker'});
  });

  test('parseRootDuBytes lê a saída do du via pkexec', () {
    expect(parseRootDuBytes('123\t/var/lib/docker\u0000'), 123);
    expect(parseRootDuBytes('lixo'), isNull);
  });
}
