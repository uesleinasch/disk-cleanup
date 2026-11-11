import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backup/auto_sync.dart';
import 'backup/backup_controller.dart';
import 'backup/mount_watcher.dart';
import 'backup/restore_controller.dart';
import 'cleanup/cleanup_controller.dart';
import 'scan/scan_controller.dart';
import 'services.dart';
import 'settings/settings_controller.dart';
import 'ui/cleanup_flow.dart';
import 'ui/pages/backup_page.dart';
import 'ui/pages/cleanup_page.dart';
import 'ui/pages/directories_page.dart';
import 'ui/pages/docker_page.dart';
import 'ui/pages/large_files_page.dart';
import 'ui/pages/overview_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/shell/app_shell.dart';
import 'ui/theme/app_theme.dart';

class DiskCleanupApp extends StatefulWidget {
  const DiskCleanupApp({
    super.key,
    required this.services,
    required this.settings,
    this.scanOnStart = true,
    this.autoSync = true,
  });

  final Services services;
  final SettingsController settings;
  final bool scanOnStart;
  final bool autoSync;

  @override
  State<DiskCleanupApp> createState() => _DiskCleanupAppState();
}

class _DiskCleanupAppState extends State<DiskCleanupApp> {
  AppDestination _current = AppDestination.overview;
  late final ScanController _scan = ScanController(widget.services);
  late final CleanupFlow _flow = CleanupFlow(
    scan: _scan,
    cleanup: CleanupController(widget.services),
  );
  late final BackupController _backup = BackupController(
    widget.services,
    widget.settings,
  );
  late final RestoreController _restore = RestoreController(
    widget.services,
    widget.settings,
    _backup,
  );
  late final AutoSyncScheduler _autoSync = AutoSyncScheduler(
    backup: _backup,
    watcher: widget.autoSync ? MountWatcher(widget.services.runner) : null,
  );
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  AutoSyncRun? _announced;

  @override
  void initState() {
    super.initState();
    _start();
    _autoSync.addListener(_onAutoSync);
    if (widget.autoSync) _autoSync.start();
  }

  void _onAutoSync() {
    final run = _autoSync.last;
    if (run == null || identical(run, _announced)) return;
    _announced = run;
    final disk = run.disk ?? 'o disco';
    final (message, failed) = switch (run.outcome) {
      null => ('Fazendo o backup automático em $disk…', false),
      BackupStepStatus.done => ('Backup automático concluído.', false),
      BackupStepStatus.failed => ('O backup automático falhou.', true),
      BackupStepStatus.cancelled => ('Backup automático cancelado.', false),
      _ => ('Backup automático concluído com avisos.', false),
    };
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: run.outcome == null || _current == AppDestination.backup
              ? null
              : SnackBarAction(
                  label: failed ? 'Ver o que houve' : 'Ver',
                  onPressed: () =>
                      setState(() => _current = AppDestination.backup),
                ),
        ),
      );
  }

  Future<void> _start() async {
    await _scan.loadLast();
    if (widget.scanOnStart) await _scan.scan();
  }

  @override
  void dispose() {
    _scan.cancel();
    _scan.dispose();
    _autoSync
      ..removeListener(_onAutoSync)
      ..dispose();
    _restore.dispose();
    _backup.dispose();
    super.dispose();
  }

  Widget _page() => switch (_current) {
    AppDestination.overview => OverviewPage(
      scan: _scan,
      flow: _flow,
      settings: widget.settings,
      onNavigate: (d) => setState(() => _current = d),
    ),
    AppDestination.directories => DirectoriesPage(
      scan: _scan,
      settings: widget.settings,
    ),
    AppDestination.largeFiles => LargeFilesPage(scan: _scan, flow: _flow),
    AppDestination.cleanup => CleanupPage(scan: _scan, flow: _flow),
    AppDestination.docker => DockerPage(scan: _scan, flow: _flow),
    AppDestination.backup => BackupPage(
      controller: _backup,
      restore: _restore,
      autoSync: _autoSync,
    ),
    AppDestination.settings => SettingsPage(settings: widget.settings),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.settings, _scan, _backup]),
      builder: (context, _) => MaterialApp(
        title: 'Disk Cleanup',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: widget.settings.value.themeMode,
        scaffoldMessengerKey: _messenger,
        home: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f5): _rescan,
            const SingleActivator(LogicalKeyboardKey.keyR, control: true):
                _rescan,
            const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () =>
                SystemNavigator.pop(),
          },
          child: Scaffold(
            body: AppShell(
              current: _current,
              onSelect: (d) => setState(() => _current = d),
              alert: _scan.state.alert,
              backupRunning: _backup.phase == BackupPhase.running,
              body: KeyedSubtree(key: ValueKey(_current), child: _page()),
            ),
          ),
        ),
      ),
    );
  }

  void _rescan() {
    if (!_scan.running) _scan.scan();
  }
}
