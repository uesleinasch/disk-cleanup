String formatBytes(int bytes) {
  final sign = bytes < 0 ? '-' : '';
  final magnitude = bytes.abs();
  if (magnitude < 1000) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = magnitude / 1000;
  var i = 0;
  while (i < units.length - 1 &&
      double.parse(value.toStringAsFixed(1)) >= 1000) {
    value /= 1000;
    i++;
  }
  return '$sign${value.toStringAsFixed(1).replaceFirst('.', ',')} ${units[i]}';
}

String formatBytesExact(int bytes) {
  final digits = bytes.abs().toString();
  final buf = StringBuffer(bytes < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '$buf bytes';
}

String formatAgo(DateTime then, DateTime now) {
  final diff = now.difference(then);
  if (diff.inSeconds < 60) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours} h';
  final calendarDays = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(then.year, then.month, then.day)).inDays;
  if (calendarDays == 1) return 'ontem';
  final days = diff.inDays;
  if (days < 30) return 'há ${calendarDays < 2 ? 2 : calendarDays} dias';
  if (days < 365) {
    final months = days ~/ 30;
    return months == 1 ? 'há 1 mês' : 'há $months meses';
  }
  final years = days ~/ 365;
  return years == 1 ? 'há 1 ano' : 'há $years anos';
}
