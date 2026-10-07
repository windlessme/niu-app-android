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
    this.lastDay = '',
  });
  final String id, title, room, teacher;
  final int weekday, startMinute, endMinute;

  /// A custom course's last day (`2026-12-31`), after which the device stops
  /// showing it without the app being opened; empty for school courses.
  final String lastDay;
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'weekday': weekday,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'room': room,
    'teacher': teacher,
    if (lastDay.isNotEmpty) 'lastDay': lastDay,
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

  /// The ongoing notification while a class is under way.
  Future<bool> setClassNow({required bool enabled}) async =>
      await channel.invokeMethod<bool>('setClassNow', {'enabled': enabled}) ??
      false;

  /// Class reminder switch and the semester dates saved on this device.
  Future<ReminderStatus> reminderStatus() async {
    final data =
        await channel.invokeMapMethod<String, Object?>('reminderStatus') ??
        const {};
    return ReminderStatus(
      enabled: data['enabled'] == true,
      classNow: data['classNow'] == true,
      permitted: data['permitted'] == true,
      semesterStart: data['semesterStart'] as String?,
      semesterEnd: data['semesterEnd'] as String?,
    );
  }

  /// Replaces every pending notification of [kind] ('assignments', 'calendar').
  Future<void> setNotifications(String kind, List<CampusNotice> items) =>
      channel.invokeMethod<void>('setNotifications', {
        'kind': kind,
        'items': items.map((item) => item.toJson()).toList(),
      });
  Future<void> shareCalendar(String ics) =>
      channel.invokeMethod<void>('shareCalendar', {'ics': ics});
}

class ReminderStatus {
  const ReminderStatus({
    required this.enabled,
    required this.permitted,
    this.classNow = false,
    this.semesterStart,
    this.semesterEnd,
  });
  final bool enabled, permitted, classNow;
  final String? semesterStart, semesterEnd;
}

/// A one-shot local notification. [link] is a niulife:// app destination.
class CampusNotice {
  const CampusNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    required this.link,
  });
  final String id, title, body, link;
  final DateTime at;
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'at': at.millisecondsSinceEpoch,
    'link': link,
  };
}
