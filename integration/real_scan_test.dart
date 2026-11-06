import 'dart:io';

import 'package:disk_cleanup/core/format.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:disk_cleanup/scan/scan_controller.dart';
import 'package:disk_cleanup/scan/snapshot_store.dart';
import 'package:disk_cleanup/services.dart';
import 'package:disk_cleanup/settings/settings.dart';
import 'package:disk_cleanup/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'varredura real somente leitura',
    () async {
      final env = Platform.environment;
      final home = env['HOME']!;
      final mapped = env['DC_MAPPED'] ?? p.join(home, 'ueslei');
      final tmp = Directory.systemTemp.createTempSync('dc_real_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final store = SettingsStore(p.join(tmp.path, 'settings.json'));
      await store.save(Settings(mappedDirs: [mapped]));
      final services = Services(
        home: home,
        runner: SystemProcessRunner(),
        settingsStore: store,
        snapshots: SnapshotStore(p.join(tmp.path, 'snap')),
        trashDir: p.join(home, '.local', 'share', 'Trash'),
      );
      final scan = ScanController(services);
      final watch = Stopwatch()..start();
      await scan.scan();
      final s = scan.state;
      final v = s.systemVolume!;
      final out = StringBuffer()
        ..writeln('tempo: ${watch.elapsed.inSeconds}s')
        ..writeln(
          'disco /: ${formatBytes(v.available)} livres de ${formatBytes(v.size)} '
          '(alerta ${s.alert.name})',
        )
        ..writeln('mapeado $mapped: ${formatBytes(s.mappedDirs[mapped]!.total)}')
        ..writeln('consumidores: ${s.consumers.take(5).map((c) => '${c.label}=${formatBytes(c.bytes)}').join(', ')}')
        ..writeln('itens: ${s.items.length}, pré-selecionados: ${scan.preselected.length}, '
            'seguro: ${formatBytes(s.safeReclaimableBytes)}')
        ..writeln('por categoria: ${{for (final c in s.items.map((i) => i.category).toSet()) c.name: formatBytes(s.items.where((i) => i.category == c).fold(0, (a, i) => a + i.bytes))}}')
        ..writeln('docker: disponível=${s.docker?.available} root=${s.docker?.needsRoot} '
            'build cache recuperável=${formatBytes(s.docker?.buildCacheReclaimable ?? 0)}')
        ..writeln('arquivos grandes: ${s.largeFiles.length}');
      // ignore: avoid_print
      print(out);
      expect(v.size, greaterThan(0));
      expect(s.updatedAt, isNotNull);
      expect(s.consumers, isNotEmpty);
      expect((await services.snapshots.latest()), isNotNull);
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
