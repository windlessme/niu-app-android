import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import 'custom_course_editor.dart';
import 'custom_courses.dart';
import 'schedule_export.dart';
import 'schedule_models.dart';
import 'schedule_wallpaper.dart';

/// Opens the editor for a new course (on [weekday]) or an existing one.
Future<void> editCustomCourse(
  BuildContext context, {
  required ClassSchedule schedule,
  required String account,
  CustomCourse? course,
  int? weekday,
}) => Navigator.of(context).push(
  MaterialPageRoute<bool>(
    builder: (_) => CustomCourseEditorScreen(
      schedule: schedule,
      account: account,
      course: course,
      weekday: weekday,
    ),
  ),
);

/// 課表設定, as on iOS: custom courses, the wallpaper and calendar export.
class ScheduleSettingsScreen extends StatelessWidget {
  const ScheduleSettingsScreen({
    super.key,
    required this.schedule,
    required this.account,
    this.store,
  });

  /// The school timetable, without custom courses.
  final ClassSchedule schedule;
  final String account;
  final CustomCourseStore? store;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? CustomCourseStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final today = taipeiToday();
        final courses = [...store.coursesFor(account)]
          ..sort((a, b) {
            final expired = a.activeOn(today) == b.activeOn(today)
                ? 0
                : a.activeOn(today)
                ? -1
                : 1;
            if (expired != 0) return expired;
            final day = (a.weekdays.firstOrNull ?? 7).compareTo(
              b.weekdays.firstOrNull ?? 7,
            );
            if (day != 0) return day;
            return (a.rows(schedule.periods)?.$1 ?? 99).compareTo(
              b.rows(schedule.periods)?.$1 ?? 99,
            );
          });
        return NiuScrollPage(
          title: '課表設定',
          children: [
            NiuSection(
              first: true,
              title: '自訂課程',
              subtitle: '只存在這支手機，不會傳送到學校系統。過了到期日就不會再顯示在課表上。',
              child: NiuGroup(
                children: [
                  for (final course in courses)
                    NiuRow(
                      icon: Icons.edit_calendar_outlined,
                      hue: course.activeOn(today) ? NiuHue.blue : NiuHue.gray,
                      title: course.name,
                      subtitle:
                          '${course.summary(schedule.periods)}\n${status(course, today)}',
                      onTap: () => editCustomCourse(
                        context,
                        schedule: schedule,
                        account: account,
                        course: course,
                      ),
                    ),
                  NiuRow(
                    icon: NiuIcons.add,
                    hue: NiuHue.green,
                    title: '新增課程',
                    onTap: () => editCustomCourse(
                      context,
                      schedule: schedule,
                      account: account,
                    ),
                  ),
                ],
              ),
            ),
            NiuSection(
              title: '桌布',
              subtitle: '選一張照片，把整週課表放在鎖定畫面時間下方。',
              child: NiuGroup(
                children: [
                  NiuRow(
                    icon: Icons.wallpaper_rounded,
                    hue: NiuHue.purple,
                    title: '製作課表桌布',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ScheduleWallpaperScreen(
                          schedule: schedule,
                          withCustom: schedule.withCustomCourses(
                            store.coursesFor(account),
                            today,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            NiuSection(
              title: '行事曆',
              subtitle: '設定學期日期後，可以匯出到行事曆，並更新桌面小工具與上課提醒。匯出不包含自訂課程。',
              child: ScheduleExportBar(schedule: schedule),
            ),
          ],
        );
      },
    );
  }

  String status(CustomCourse course, DateTime today) {
    if (!course.activeOn(today)) return '已於 ${course.lastDayLabel} 到期';
    if (course.rows(schedule.periods) == null) return '課表已沒有所選節次，請重新設定';
    if (schedule.conflict(course, const [], today) != null) {
      return '與學校課程時段衝突，暫不顯示';
    }
    return '顯示至 ${course.lastDayLabel}';
  }
}
