import 'package:disk_cleanup/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';

Widget testApp(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: buildTheme(brightness),
    home: Scaffold(body: child),
  );
}
