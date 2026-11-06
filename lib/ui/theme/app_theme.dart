import 'package:flutter/material.dart';

import 'color_schemes.dart';
import 'severity_colors.dart';

ThemeData buildTheme(Brightness brightness) {
  final scheme = brightness == Brightness.light ? lightScheme : darkScheme;
  final base = ThemeData(
    colorScheme: scheme,
    fontFamily: 'Roboto',
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  return base.copyWith(
    extensions: [
      brightness == Brightness.light
          ? SeverityColors.light
          : SeverityColors.dark,
    ],
    listTileTheme: const ListTileThemeData(
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsetsDirectional.symmetric(horizontal: 16),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 480,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      minExtendedWidth: 220,
    ),
    tooltipTheme:
        const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    // ignore: deprecated_member_use
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
  );
}
