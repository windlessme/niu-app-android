import 'package:flutter/material.dart';
import '../../core/analytics/app_analytics.dart';
import '../../shared/shared.dart';
import '../../core/platform/schedule_gateway.dart';
import '../../core/platform/schedule_ics.dart';
import '../../core/session/campus_session.dart';
import 'schedule_models.dart';

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
      // A device-added course is identified by its id, not its text.
      final custom = period.custom[days[day]];
      final raw = custom == null
          ? period.courses[days[day]]
          : 'custom:${custom.id}';
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
      final lines = custom != null
          ? const <String>[]
          : raw
                .split('\n')
                .map((v) => v.trim())
                .where((v) => v.isNotEmpty)
                .toList();
      final title = custom?.name ?? (lines.length > 1 ? lines[1] : lines.first);
      final teacher = custom?.note ?? (lines.length > 1 ? lines.first : '');
      final room = custom?.classroom ?? lines.skip(2).join(' ');
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
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _restoreDates();
  }

  /// Shows the semester dates already saved on this device.
  Future<void> _restoreDates() async {
    try {
      final status = await gateway.reminderStatus();
      final start = status.semesterStart, end = status.semesterEnd;
      if (start == null || end == null || !mounted || snapshot != null) return;
      setState(
        () => snapshot = ScheduleSnapshot(
          semesterStart: start,
          semesterEnd: end,
          blocks: scheduleBlocks(widget.schedule),
        ),
      );
    } catch (_) {
      /* The dates can still be chosen by hand. */
    }
  }

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
      helpText: '選擇學期的第一天與最後一天',
      saveText: '完成',
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
        showNiuMessage(context, '沒有完成，請確認登入狀態與學期日期');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() => run(() async {
    if (snapshot == null) await configure();
    if (snapshot == null) return;
    current();
    await gateway.shareCalendar(exportScheduleIcs(snapshot!));
    AppAnalytics.instance.event('schedule_export');
  });

  @override
  Widget build(BuildContext context) => NiuGroup(
    children: [
      NiuRow(
        icon: Icons.date_range_rounded,
        title: '學期日期',
        subtitle: snapshot == null
            ? '設定後會同步到桌面小工具'
            : '${snapshot!.semesterStart} – ${snapshot!.semesterEnd}',
        onTap: busy ? null : () => run(configure),
      ),
      Tooltip(
        message: '匯出行事曆',
        child: NiuRow(
          icon: NiuIcons.share,
          hue: NiuHue.red,
          title: '匯出到行事曆',
          subtitle: '產生 .ics 檔，分享到 Google 日曆等 App',
          onTap: busy ? null : export,
        ),
      ),
    ],
  );
}
