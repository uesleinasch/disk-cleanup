import 'package:flutter/material.dart';

import 'disk/alert.dart';
import 'ui/pages/placeholder_page.dart';
import 'ui/shell/app_shell.dart';
import 'ui/theme/app_theme.dart';

class DiskCleanupApp extends StatefulWidget {
  const DiskCleanupApp({super.key});

  @override
  State<DiskCleanupApp> createState() => _DiskCleanupAppState();
}

class _DiskCleanupAppState extends State<DiskCleanupApp> {
  AppDestination _current = AppDestination.overview;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Disk Cleanup',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: AppShell(
          current: _current,
          onSelect: (d) => setState(() => _current = d),
          alert: AlertLevel.ok,
          body: PlaceholderPage(_current.label),
        ),
      ),
    );
  }
}
