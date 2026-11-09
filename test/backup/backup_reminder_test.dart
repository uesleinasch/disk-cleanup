import 'package:disk_cleanup/backup/backup_reminder.dart';
import 'package:disk_cleanup/settings/backup_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 20, 9);

  BackupReminder at(DateTime? last, {int days = 7, bool sources = true}) =>
      backupReminder(
        BackupSettings(
          sources: sources ? const ['/home/user/projetos'] : const [],
          lastBackupAt: last,
          reminderDays: days,
        ),
        now,
      );

  test('sem origens e sem backup não aparece', () {
    expect(at(null, sources: false), BackupReminder.hidden);
  });

  test('com origens e sem backup pede o primeiro', () {
    expect(at(null), BackupReminder.due);
    expect(at(null, days: 0), BackupReminder.ok);
  });

  test('alerta só depois de passar do limite, em dias de calendário', () {
    expect(at(DateTime(2026, 11, 13, 23, 59)), BackupReminder.ok);
    expect(at(DateTime(2026, 11, 12, 23, 59)), BackupReminder.due);
    expect(at(DateTime(2026, 11, 20, 8)), BackupReminder.ok);
  });

  test('limite 0 desliga o alerta mas mantém a linha', () {
    expect(at(DateTime(2025, 1, 1), days: 0), BackupReminder.ok);
  });

  test('backup feito mesmo sem origens atuais continua visível', () {
    expect(at(DateTime(2026, 11, 1), sources: false), BackupReminder.due);
  });
}
