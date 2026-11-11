import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backup/backup_controller.dart';
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
  });

  final Services services;
  final SettingsController settings;
  final bool scanOnStart;

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

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _scan.loadLast();
    if (widget.scanOnStart) await _scan.scan();
  }

  @override
  void dispose() {
    _scan.cancel();
    _scan.dispose();
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
    AppDestination.backup => BackupPage(controller: _backup, restore: _restore),
    AppDestination.settings => SettingsPage(settings: widget.settings),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.settings, _scan]),
      builder: (context, _) => MaterialApp(
        title: 'Disk Cleanup',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: widget.settings.value.themeMode,
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
