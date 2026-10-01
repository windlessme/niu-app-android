/// A civil date, independent of the device timezone.
class CampusDate implements Comparable<CampusDate> {
  CampusDate(this.year, this.month, this.day) {
    final value = DateTime.utc(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      throw const FormatException('Invalid campus date');
    }
  }

  factory CampusDate.parse(String text) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      throw const FormatException('Invalid date format');
    }
    final parts = text.split('-').map(int.parse).toList();
    return CampusDate(parts[0], parts[1], parts[2]);
  }

  factory CampusDate.at(DateTime instant) {
    // Modern NIU calendar dates use UTC+8; Taiwan has no current DST.
    final taipei = instant.toUtc().add(const Duration(hours: 8));
    return CampusDate(taipei.year, taipei.month, taipei.day);
  }

  final int year;
  final int month;
  final int day;
  int get academicYear => year - 1911 - (month < 8 ? 1 : 0);

  @override
  int compareTo(CampusDate other) => DateTime.utc(
    year,
    month,
    day,
  ).compareTo(DateTime.utc(other.year, other.month, other.day));

  @override
  bool operator ==(Object other) =>
      other is CampusDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
