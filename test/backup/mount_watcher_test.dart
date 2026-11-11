import 'package:disk_cleanup/backup/mount_watcher.dart';
import 'package:disk_cleanup/core/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_process_runner.dart';

void main() {
  test('lê a saída do findmnt --poll, com espaços escapados', () {
    final e = parseFindmntPoll(r'mount /run/media/ana/LOCAL\x20DRIVE')!;
    expect(e.action, MountAction.mount);
    expect(e.target, '/run/media/ana/LOCAL DRIVE');
    expect(parseFindmntPoll('umount /mnt/x')!.action, MountAction.umount);
    expect(parseFindmntPoll('move /mnt/y')!.action, MountAction.other);
    expect(parseFindmntPoll(''), isNull);
  });

  test('emite os eventos e para quando o findmnt não existe', () async {
    final runner = FakeProcessRunner()
      ..whenStreaming(
        'findmnt',
        const ['--poll', '-n', '-r', '-o', 'ACTION,TARGET'],
        lines: ['mount /media/disco', 'umount /media/disco'],
        result: const RunResult(127, [], ''),
      );
    final watcher = MountWatcher(runner);
    final events = <MountEvent>[];
    watcher.events.listen(events.add);
    watcher.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(
      [for (final e in events) (e.action, e.target)],
      [
        (MountAction.mount, '/media/disco'),
        (MountAction.umount, '/media/disco'),
      ],
    );
    expect(runner.calls.length, 1);
    await watcher.dispose();
  });

  test('reinicia o findmnt se ele terminar', () async {
    final runner = FakeProcessRunner()
      ..whenStreaming('findmnt', const [
        '--poll',
        '-n',
        '-r',
        '-o',
        'ACTION,TARGET',
      ]);
    final watcher = MountWatcher(
      runner,
      restartDelay: const Duration(milliseconds: 1),
      maxRestartDelay: const Duration(milliseconds: 2),
    );
    watcher.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await watcher.dispose();
    expect(runner.calls.length, greaterThan(1));
  });
}
