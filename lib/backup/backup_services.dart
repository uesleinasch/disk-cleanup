import '../core/process_runner.dart';
import 'backup_lock.dart';
import 'backup_planner.dart';
import 'browser_profiles.dart';
import 'disk_targets.dart';
import 'restore_planner.dart';
import 'rsync_runner.dart';
import 'secrets_archiver.dart';

class BackupServices {
  BackupServices({
    required this.disks,
    required this.planner,
    required this.rsync,
    required this.browsers,
    required this.secrets,
    BackupLock? lock,
    RestoreEngine? restore,
  }) : lock = lock ?? BackupLock(),
       restore = restore ?? RestoreEngine(rsync.runner, rsync);

  factory BackupServices.system(String home, ProcessRunner runner) {
    final rsync = RsyncRunner(runner);
    return BackupServices(
      disks: DiskTargets(runner),
      planner: BackupPlanner(runner),
      rsync: rsync,
      browsers: BrowserProfiles(home: home, rsync: rsync),
      secrets: SecretsArchiver(home: home, runner: runner),
    );
  }

  final DiskTargets disks;
  final BackupPlanner planner;
  final RsyncRunner rsync;
  final BrowserProfiles browsers;
  final SecretsArchiver secrets;
  final BackupLock lock;
  final RestoreEngine restore;
}
