import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/academic_portal/academic_portal_screen.dart';
import 'package:niu_mobile/features/schedule/schedule_export.dart';
import 'package:niu_mobile/features/grades/grades_models.dart';
import 'package:niu_mobile/features/grades/grades_screen.dart';
import 'package:niu_mobile/features/graduation/graduation_screen.dart';
import 'package:niu_mobile/features/schedule/schedule_models.dart';

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

  test('term labels come from the results rows', () {
    expect(GradeCourse.semesterLabel('115', '1'), '115 學年度 上學期');
    expect(GradeCourse.semesterLabel(' 114 ', '2'), '114 學年度 下學期');
    expect(GradeCourse.semesterLabel('1151', 'B3E0101A'), '');
    expect(GradeCourse.semesterLabel('115', '4'), '');
  });

  test('term grades are read from the results page, once it has loaded', () {
    // acade shows a query page (_01, also a #DataGrid) next to the results
    // page (_02); only the one with a 成績 column holds the grades.
    final result = Process.runSync('node', [
      '-e',
      '''
const assert = require('node:assert/strict');
const script = ${jsonEncode(gradeExtractScript(GradeMode.midterm))};
const cell = t => ({innerText: t, textContent: t});
function page(path, header, rows, readyState = 'complete') {
  // The header row is <th> cells, so it has no <td>.
  const trs = [[], ...rows].map(r => ({querySelectorAll: () => r.map(cell)}));
  return {
    URL: 'https://acade.niu.edu.tw/NIU/Application/GRD/GRD51/' + path,
    readyState,
    body: {innerText: ''},
    querySelector: () => null,
    querySelectorAll: s => s === '#DataGrid tr:first-child > *' ? header.map(cell) : s === '#DataGrid tr' ? trs : [],
  };
}
const query = page('GRD5131_01.aspx', ['', '學年期', '系所名稱', '學號', '中文姓名'], [['詳', '1151', '資工系', 'B1', '王']]);
const results = page('GRD5131_02.aspx', ['序號', '學年度', '學期', '選別', '中文課名', '成績'], [['1', '115', '1', '必修', '資料結構', '未上傳']], 'loading');
global.window = {document: query, frames: [{document: results, frames: []}]};
assert.equal(eval(script), null);
results.readyState = 'complete';
const value = JSON.parse(eval(script));
assert.deepEqual(value.rows, [['1', '115', '1', '必修', '資料結構', '未上傳']]);
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

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
