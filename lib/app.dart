import 'package:flutter/material.dart';

import 'ui/theme/app_theme.dart';

class DiskCleanupApp extends StatelessWidget {
  const DiskCleanupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Disk Cleanup',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const Scaffold(),
    );
  }
}
