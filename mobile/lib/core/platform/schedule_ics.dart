import 'dart:convert';
import 'schedule_gateway.dart';

/// RFC 5545 export. Taipei has fixed UTC+08:00 throughout supported semesters.
/// UTC event times avoid relying on a receiving calendar's timezone database.
String exportScheduleIcs(ScheduleSnapshot snapshot, {DateTime? generatedAt}) {
  DateTime civil(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw ArgumentError('Expected ISO civil date');
    }
    final date = DateTime.parse('${value}T00:00:00Z');
    if (date.toIso8601String().substring(0, 10) != value) {
      throw ArgumentError('Invalid civil date');
    }
    return date;
  }

  final start = civil(snapshot.semesterStart);
  final end = civil(snapshot.semesterEnd);
  if (end.isBefore(start) || end.difference(start).inDays > 366) {
    throw ArgumentError('Invalid semester range');
  }
  String stamp(DateTime d) {
    final value = d
        .toUtc()
        .toIso8601String()
        .split('.')
        .first
        .replaceAll('-', '')
        .replaceAll(':', '');
    return '${value}Z';
  }

  String text(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', r'\n')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,');
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//NIU-Life//Class Schedule//ZH-TW',
    'CALSCALE:GREGORIAN',
  ];
  final ids = <String>{};
  for (final b in snapshot.blocks) {
    if (b.id.isEmpty ||
        !ids.add(b.id) ||
        b.title.trim().isEmpty ||
        b.weekday < 1 ||
        b.weekday > 7 ||
        b.startMinute < 0 ||
        b.endMinute > 1440 ||
        b.endMinute <= b.startMinute) {
      throw ArgumentError('Invalid schedule block');
    }
    final first = start.add(
      Duration(days: (b.weekday - start.weekday + 7) % 7),
    );
    if (first.isAfter(end)) continue;
    final uid = base64Url.encode(
      utf8.encode('${snapshot.semesterStart}/${snapshot.semesterEnd}/${b.id}'),
    );
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:$uid@niulife',
      'DTSTAMP:${stamp(generatedAt ?? DateTime.now())}',
      'DTSTART:${stamp(first.add(Duration(minutes: b.startMinute - 480)))}',
      'DTEND:${stamp(first.add(Duration(minutes: b.endMinute - 480)))}',
      'RRULE:FREQ=WEEKLY;UNTIL=${stamp(end.add(const Duration(hours: 15, minutes: 59, seconds: 59)))}',
      'SUMMARY:${text(b.title)}',
      'LOCATION:${text(b.room)}',
      'DESCRIPTION:${text(b.teacher)}',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  // Fold at 75 UTF-8 octets, never inside a Unicode scalar.
  String fold(String line) {
    final out = StringBuffer();
    var bytes = 0;
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      final length = utf8.encode(char).length;
      if (bytes + length > 75) {
        out.write('\r\n ');
        bytes = 1;
      }
      out.write(char);
      bytes += length;
    }
    return out.toString();
  }

  return '${lines.map(fold).join('\r\n')}\r\n';
}
