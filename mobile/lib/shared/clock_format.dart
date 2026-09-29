/// Stable 24-hour campus-local time, independent of device clock preferences.
String formatTaipeiClock(DateTime instant) {
  final date = instant.toUtc().add(const Duration(hours: 8));
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
