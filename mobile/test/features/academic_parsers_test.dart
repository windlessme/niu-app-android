import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/web/academic_portal_screen.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';
import 'package:niu_mobile/features/schedule/schedule_export.dart';
import 'package:niu_mobile/features/grades/grades_screen.dart';
import 'package:niu_mobile/features/graduation/graduation_screen.dart';

void main() {
  test(
    'school combined period fixture preserves omitted Monday and weekend',
    () {
      final result = ClassSchedule.fromRows([
        ['節次時間', '星期二', '星期六'],
        ['第1節\n08:10~09:00', '陳老師\n程式設計\n資101', ''],
        ['第2節\n09:10~10:00', '陳老師\n程式設計\n資101', '專題'],
        ['第3節\n10:10~11:00', '', ''],
        ['第4節\n11:10~12:00', '陳老師\n程式設計\n資101', ''],
      ]);
      expect(result.days, ['星期二', '星期六']);
      final blocks = scheduleBlocks(result);
      expect(blocks.length, 3);
      expect(blocks.first.weekday, 2);
      expect(blocks.first.startMinute, 490);
      expect(blocks.first.endMinute, 600);
      expect(blocks.first.title, '程式設計');
      expect(blocks.first.teacher, '陳老師');
      expect(blocks.first.room, '資101');
      expect(blocks.last.weekday, 6);
      expect(blocks.map((b) => b.id).toSet().length, 3);
    },
  );

  test('separate period fixture and different rooms never merge', () {
    final result = ClassSchedule.fromRows([
      ['節次', '時間', '星期一'],
      ['1', '08:10-09:00', '王老師\n微積分\nA101'],
      ['2', '09:10-10:00', '王老師\n微積分\nB101'],
    ]);
    expect(result.periods.first.time, '08:10-09:00');
    expect(scheduleBlocks(result).length, 2);
    expect(
      () => ClassSchedule.fromRows([
        ['登入帳號', '密碼'],
      ]),
      throwsFormatException,
    );
  });

  test(
    'history fixture excludes summary/header rows and keeps textual grades',
    () {
      final records = GradeCourse.parseHistoryRows([
        ['學期', '類別', '學分', '科目', '成績'],
        ['1141', '必修', '3.0', '微積分', '59'],
        ['1142', '選修', '2', '服務學習', '通過'],
        ['1133', '選修', '1.5', '專題', '88'],
        ['1144', '選修', '2', '不合法學期', '90'],
        ['1142', '選修', '2', '尚未公布', ''],
      ]);
      expect(records.length, 3);
      expect(records.first.failed, true);
      expect(records[1].score, '通過');
      expect(records[1].failed, false);
      expect(records.last.semester, '113 學年度 暑學期');
      expect(records.last.credits, 1.5);
    },
  );

  test('four-value graduation fixture expands non-counted requirements', () {
    expect(GraduationData.normalizeHours(['1', '2', '3', '4']), [
      '1',
      '不計入',
      '2',
      '不計入',
      '3',
      '不計入',
      '4',
      '不計入',
    ]);
    final hours = ['18', '18', '20', '30', '10', '10', '2', '5'];
    expect(GraduationData.normalizeHours(hours), hours);
    final data = GraduationData.fromJson({
      'diverseHours': ['10', '20', '30', '40'],
      'englishAbility': '通過',
      'physicalFitness': '通過',
      'creditRequired': ['128', '90'],
      'creditCourse': '資訊學程',
    });
    expect(data.english, '通過');
    expect(data.credits, ['128', '90']);
    expect(data.hours.length, 8);
  });

  test('GUID redirect is not mistaken for session expiry', () {
    expect(
      isAcademicSessionExpired(
        Uri.parse('https://acade.niu.edu.tw/NIU/Login.aspx?GUID=abc'),
      ),
      false,
    );
    expect(
      isAcademicSessionExpired(
        Uri.parse('https://acade.niu.edu.tw/NIU/Login.aspx?GUID='),
      ),
      true,
    );
    expect(
      isAcademicSessionExpired(
        Uri.parse('https://acade.niu.edu.tw/NIU/TimeoutPage.aspx'),
      ),
      true,
    );
    expect(
      isAcademicSessionExpired(
        Uri.parse('https://ccsys1.niu.edu.tw/SSO/login'),
      ),
      true,
    );
    expect(
      isAcademicSessionExpired(
        Uri.parse('https://evil.example/NIU/Login.aspx'),
      ),
      false,
    );
  });
}
