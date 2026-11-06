import 'package:flutter/material.dart';

@immutable
class SeverityColors extends ThemeExtension<SeverityColors> {
  const SeverityColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  final Color success, onSuccess, successContainer, onSuccessContainer;
  final Color warning, onWarning, warningContainer, onWarningContainer;

  static const light = SeverityColors(
    success: Color(0xFF006D43),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFF92F7BC),
    onSuccessContainer: Color(0xFF005231),
    warning: Color(0xFF775A00),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFDF99),
    onWarningContainer: Color(0xFF5A4300),
  );

  static const dark = SeverityColors(
    success: Color(0xFF76DAA1),
    onSuccess: Color(0xFF003920),
    successContainer: Color(0xFF005231),
    onSuccessContainer: Color(0xFF92F7BC),
    warning: Color(0xFFF4BF2A),
    onWarning: Color(0xFF3F2E00),
    warningContainer: Color(0xFF5A4300),
    onWarningContainer: Color(0xFFFFDF99),
  );

  @override
  SeverityColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) =>
      SeverityColors(
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        successContainer: successContainer ?? this.successContainer,
        onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
        warningContainer: warningContainer ?? this.warningContainer,
        onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      );

  @override
  SeverityColors lerp(SeverityColors? other, double t) {
    if (other == null) return this;
    return SeverityColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
    );
  }
}
