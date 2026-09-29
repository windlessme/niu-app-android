import 'package:flutter/services.dart';

/// A weekly, already-grouped course block. ISO weekday: Monday=1, Sunday=7.
class ScheduleBlock {
  const ScheduleBlock({
    required this.id,
    required this.title,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    this.room = '',
    this.teacher = '',
  });
  final String id, title, room, teacher;
  final int weekday, startMinute, endMinute;
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'weekday': weekday,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'room': room,
    'teacher': teacher,
  };
}

class ScheduleSnapshot {
  const ScheduleSnapshot({
    required this.semesterStart,
    required this.semesterEnd,
    required this.blocks,
  });

  /// Inclusive ISO civil dates, e.g. 2026-09-14. Never inferred from today's date.
  final String semesterStart, semesterEnd;
  final List<ScheduleBlock> blocks;
  Map<String, Object> toJson() => {
    'version': 1,
    'timeZone': 'Asia/Taipei',
    'semesterStart': semesterStart,
    'semesterEnd': semesterEnd,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };
}

class ScheduleGateway {
  const ScheduleGateway();
  static const channel = MethodChannel('niulife/schedule');
  Future<void> saveSnapshot(ScheduleSnapshot snapshot) =>
      channel.invokeMethod<void>('saveSnapshot', snapshot.toJson());

  /// Call on logout/account switch, including failed or expired sessions.
  Future<void> clear() => channel.invokeMethod<void>('clear');
  Future<bool> requestNotificationPermission() async =>
      await channel.invokeMethod<bool>('requestNotificationPermission') ??
      false;
  Future<bool> setReminders({
    required bool enabled,
    int minutesBefore = 10,
  }) async =>
      await channel.invokeMethod<bool>('setReminders', {
        'enabled': enabled,
        'minutesBefore': minutesBefore,
      }) ??
      false;
  Future<void> shareCalendar(String ics) =>
      channel.invokeMethod<void>('shareCalendar', {'ics': ics});
}
