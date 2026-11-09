import '../settings/backup_settings.dart';

enum BackupReminder { hidden, ok, due }

BackupReminder backupReminder(BackupSettings backup, DateTime now) {
  final last = backup.lastBackupAt;
  if (last == null) {
    if (backup.sources.isEmpty) return BackupReminder.hidden;
    return backup.reminderDays > 0 ? BackupReminder.due : BackupReminder.ok;
  }
  if (backup.reminderDays <= 0) return BackupReminder.ok;
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(last.year, last.month, last.day)).inDays;
  return days > backup.reminderDays ? BackupReminder.due : BackupReminder.ok;
}
