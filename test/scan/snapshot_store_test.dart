import 'dart:convert';
import 'dart:io';

import 'package:disk_cleanup/scan/snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late SnapshotStore store;
  final now = DateTime.utc(2026, 11, 6, 12);

  Snapshot snap(int daysAgo) => Snapshot(
    takenAt: now.subtract(Duration(days: daysAgo)),
    state: {'daysAgo': daysAgo},
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('snapshots_test');
    store = SnapshotStore('${tmp.path}/nested/snapshots');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('closestTo devolve o snapshot de 7 dias entre 10, 7 e 1', () async {
    for (final d in [10, 7, 1]) {
      await store.save(snap(d));
    }
    final found = await store.closestTo(now.subtract(const Duration(days: 7)));
    expect(found?.state['daysAgo'], 7);
    expect(found?.takenAt, now.subtract(const Duration(days: 7)));
  });

  test('closestTo devolve null fora da tolerância', () async {
    await store.save(snap(1));
    expect(
      await store.closestTo(now.subtract(const Duration(days: 7))),
      isNull,
    );
  });

  test('closestTo em empate devolve o mais antigo', () async {
    await store.save(snap(8));
    await store.save(snap(6));
    final found = await store.closestTo(now.subtract(const Duration(days: 7)));
    expect(found?.state['daysAgo'], 8);
  });

  test('latest devolve o mais recente e null sem snapshots', () async {
    expect(await store.latest(), isNull);
    for (final d in [10, 1, 7]) {
      await store.save(snap(d));
    }
    expect((await store.latest())?.state['daysAgo'], 1);
  });

  test('save grava snapshot-<epochMs>.json com takenAt e state', () async {
    final s = snap(2);
    await store.save(s);
    final file = File(
      '${tmp.path}/nested/snapshots/snapshot-${s.takenAt.millisecondsSinceEpoch}.json',
    );
    expect(file.existsSync(), isTrue);
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(DateTime.parse(json['takenAt'] as String), s.takenAt);
    expect(json['state'], {'daysAgo': 2});
    final names = Directory('${tmp.path}/nested/snapshots')
        .listSync()
        .map((e) => e.path.split('/').last);
    expect(names.any((n) => n.endsWith('.tmp')), isFalse);
  });

  test('prune remove snapshots mais velhos que 90 dias', () async {
    for (final d in [100, 91, 89, 1]) {
      await store.save(snap(d));
    }
    await store.prune(now: now);
    final remaining = <int>[];
    for (final d in [100, 91, 89, 1]) {
      final s = await store.closestTo(
        now.subtract(Duration(days: d)),
        tolerance: Duration.zero,
      );
      if (s != null) remaining.add(d);
    }
    expect(remaining, [89, 1]);
  });

  test('arquivo corrompido ou fora do padrão é ignorado', () async {
    await store.save(snap(3));
    final dir = '${tmp.path}/nested/snapshots';
    File('$dir/snapshot-9999999999999.json').writeAsStringSync('{nao e json');
    File('$dir/snapshot-1.json').writeAsStringSync('{"x": 1}');
    File('$dir/outro.json').writeAsStringSync('{}');
    expect((await store.latest())?.state['daysAgo'], 3);
    expect(
      await store.closestTo(now.subtract(const Duration(days: 3))),
      isNotNull,
    );
    await store.prune(now: now);
  });

  test('diretório inexistente não lança', () async {
    final empty = SnapshotStore('${tmp.path}/nao-existe');
    expect(await empty.latest(), isNull);
    expect(await empty.closestTo(now), isNull);
    await empty.prune();
  });

  test('weeklyDelta', () {
    expect(weeklyDelta(61200, 59100), 2100);
    expect(weeklyDelta(1, null), isNull);
    expect(weeklyDelta(10, 30), -20);
  });
}
