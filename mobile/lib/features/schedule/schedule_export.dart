import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import '../../core/platform/schedule_gateway.dart';
import '../../core/platform/schedule_ics.dart';
import '../../core/session/campus_session.dart';
import 'schedule_screen.dart';

List<ScheduleBlock> scheduleBlocks(ClassSchedule schedule) {
  const days = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  final result = <ScheduleBlock>[];
  for (var day = 0; day < days.length; day++) {
    ScheduleBlock? pending;
    String? identity;
    void flush() {
      if (pending != null) result.add(pending!);
      pending = null;
      identity = null;
    }

    for (final period in schedule.periods) {
      final raw = period.courses[days[day]];
      if (raw == null) {
        flush();
        continue;
      }
      final times = RegExp(
        r'(\d{1,2}):(\d{2})',
      ).allMatches(period.time).toList();
      if (times.length != 2) {
        throw FormatException('無法解析 ${period.label} 的上課時間');
      }
      int minute(RegExpMatch match) {
        final h = int.parse(match[1]!);
        final m = int.parse(match[2]!);
        if (h > 24 || m > 59 || (h == 24 && m != 0)) {
          throw const FormatException('課表時間格式錯誤');
        }
        return h * 60 + m;
      }

      final start = minute(times.first);
      final end = minute(times.last);
      if (end <= start || start >= 1440) {
        throw const FormatException('課表時間範圍錯誤');
      }
      final lines = raw
          .split('\n')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList();
      final title = lines.length > 1 ? lines[1] : lines.first;
      final teacher = lines.length > 1 ? lines.first : '';
      final room = lines.skip(2).join(' ');
      if (pending != null && raw == identity && start >= pending!.endMinute) {
        pending = ScheduleBlock(
          id: pending!.id,
          title: title,
          weekday: day + 1,
          startMinute: pending!.startMinute,
          endMinute: end,
          teacher: teacher,
          room: room,
        );
      } else {
        flush();
        identity = raw;
        pending = ScheduleBlock(
          id: '${day + 1}-$start-$title-$teacher-$room',
          title: title,
          weekday: day + 1,
          startMinute: start,
          endMinute: end,
          teacher: teacher,
          room: room,
        );
      }
    }
    flush();
  }
  return result;
}

class ScheduleExportBar extends StatefulWidget {
  const ScheduleExportBar({super.key, required this.schedule});
  final ClassSchedule schedule;
  @override
  State<ScheduleExportBar> createState() => _ScheduleExportBarState();
}

class _ScheduleExportBarState extends State<ScheduleExportBar> {
  final session = CampusSession.instance;
  final gateway = const ScheduleGateway();
  late final epoch = session.coordinator.epoch;
  late final owner = session.account;
  ScheduleSnapshot? snapshot;
  bool reminders = false;
  bool busy = false;

  void current() {
    session.coordinator.requireCurrent(epoch);
    if (owner == null || session.account != owner) {
      throw StateError('請重新登入並更新課表');
    }
  }

  Future<void> configure() async {
    final dates = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '選擇實際學期起訖日期',
      saveText: '確認學期日期',
    );
    if (dates == null || !mounted) return;
    if (dates.end.difference(dates.start).inDays > 366) {
      throw const FormatException('學期範圍不可超過 366 天');
    }
    final next = ScheduleSnapshot(
      semesterStart: dates.start.toIso8601String().substring(0, 10),
      semesterEnd: dates.end.toIso8601String().substring(0, 10),
      blocks: scheduleBlocks(widget.schedule),
    );
    current();
    await session.saveSchedule(next, epoch: epoch, owner: owner!);
    current();
    if (mounted) setState(() => snapshot = next);
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      current();
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作未完成，請確認登入、學期日期與通知權限後重試。')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: NiuSpacing.md, vertical: 6),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: busy ? null : () => run(configure),
                icon: const Icon(Icons.date_range),
                label: Text(
                  snapshot == null
                      ? '設定學期・桌面課表'
                      : '${snapshot!.semesterStart} — ${snapshot!.semesterEnd}',
                ),
              ),
            ),
            IconButton(
              tooltip: '匯出行事曆',
              icon: const Icon(Icons.ios_share),
              onPressed: busy
                  ? null
                  : () => run(() async {
                      if (snapshot == null) await configure();
                      if (snapshot == null) return;
                      current();
                      await gateway.shareCalendar(exportScheduleIcs(snapshot!));
                    }),
            ),
          ],
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('上課前 10 分鐘提醒'),
          subtitle: Text(
            '依每週課表提醒；假日與停課需自行調整。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: reminders,
          onChanged: busy
              ? null
              : (enabled) => run(() async {
                  if (enabled && snapshot == null) await configure();
                  if (enabled && snapshot == null) return;
                  current();
                  if (enabled &&
                      !await gateway.requestNotificationPermission()) {
                    throw StateError('通知權限未開啟');
                  }
                  current();
                  final accepted = await gateway.setReminders(enabled: enabled);
                  current();
                  if (enabled && !accepted) throw StateError('通知不可用');
                  if (mounted) setState(() => reminders = enabled);
                }),
        ),
      ],
    ),
  );
}
