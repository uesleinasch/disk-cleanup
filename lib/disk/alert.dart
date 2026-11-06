import '../settings/settings.dart';
import 'disk_info.dart';

enum AlertLevel { ok, warning, critical }

AlertLevel evaluateAlert(VolumeUsage v, Settings s) {
  if (v.size <= 0) return AlertLevel.ok;
  final freePercent = v.freeFraction * 100;
  if (freePercent < s.critPercent || v.available < s.critBytes) {
    return AlertLevel.critical;
  }
  if (freePercent < s.warnPercent || v.available < s.warnBytes) {
    return AlertLevel.warning;
  }
  return AlertLevel.ok;
}
