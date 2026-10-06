import 'package:flutter/material.dart';
import '../../core/demo/demo_data.dart';
import '../../core/session/campus_session.dart';
import '../academic_portal/academic_portal_screen.dart';
import 'grade_statistics.dart';
import 'grades_models.dart';
import 'grades_widgets.dart';
import '../../shared/shared.dart';

String gradeExtractScript(GradeMode mode) =>
    '''
(() => {
  $portalDocumentCollector
  ${mode == GradeMode.history ? r'''
  const doc = docs.find(d => d.querySelector('#accordion修課紀錄'));
  if (!doc) return null;
  const rows = Array.from(doc.querySelectorAll('#accordion修課紀錄 table.table.table-striped tr'), r => Array.from(r.querySelectorAll('td'), c => clean(c.textContent))).filter(r => r.length >= 5);
  const summary = Array.from(doc.querySelectorAll('div.row table.table tr'), r => Array.from(r.querySelectorAll('td'), c => clean(c.textContent))).filter(r => r.length >= 4 && /^\d{3,4}$/.test(r[0]));
  return JSON.stringify({rows, summary});
  ''' : '''
  // The query page (_01) has a DataGrid too; the results page is the one
  // with a 成績 column. Wait for it to finish rather than read it half-built.
  const doc = docs.find(d => d.URL.includes('${mode == GradeMode.midterm ? 'GRD5131' : 'GRD5130'}') && d.readyState === 'complete' && Array.from(d.querySelectorAll('#DataGrid tr:first-child > *'), c => clean(c.innerText)).includes('成績'));
  if (!doc) return null;
  const rows = Array.from(doc.querySelectorAll('#DataGrid tr'), r => Array.from(r.querySelectorAll('td'), c => clean(c.innerText))).filter(r => r.length >= 6 && r[4]);
  const rank = clean(doc.querySelector('#QTable2 > tbody > tr:nth-child(2) > td:nth-child(2) > table > tbody > tr:nth-child(2) > td:nth-child(4)')?.innerText);
  return JSON.stringify({rows, rank, average: clean(doc.querySelector('#Q_CRS_AVG_MARK')?.innerText), title: clean(doc.body.innerText).match(/\\d{2,3}\\s*學年度\\s*第?\\s*[上下暑123]\\s*學期/)?.[0] || ''});
  '''}
})()
''';

class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key, this.session});
  final CampusSession? session;
  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  GradeMode mode = GradeMode.finalTerm;

  /// 歷年 term shown on its own, by key (`1142`); null for every term.
  String? semesterFilter;

  /// Expanded 歷年 terms; null until the user toggles one, meaning the
  /// newest term only.
  Set<String>? expanded;
  static const labels = {
    GradeMode.midterm: '期中',
    GradeMode.finalTerm: '學期',
    GradeMode.history: '歷年',
  };
  static const menus = {
    GradeMode.midterm: '學生查詢期中成績',
    GradeMode.finalTerm: '學生查詢當學期成績',
    GradeMode.history: '學生歷年學期成績及排名查詢',
  };

  static List<List<String>> _rows(dynamic value) => [
    for (final r in (value as List? ?? const []))
      if (r is List) [for (final v in r) v.toString()],
  ];

  List<Widget> history(BuildContext context, Map value) {
    final summary = value['summary'] is List
        ? (value['summary'] as List).whereType<List>()
        : const <List>[];
    final semesters = GradeSemester.group(
      GradeCourse.parseHistoryRows(_rows(value['rows'])),
      summary,
    );
    if (semesters.isEmpty) {
      return const [
        NiuEmpty(
          icon: NiuIcons.grades,
          title: '還沒有成績',
          message: '學校公布成績後會出現在這裡。',
        ),
      ];
    }
    final filter = semesters.any((s) => s.key == semesterFilter)
        ? semesterFilter
        : null;
    final shown = [
      for (final s in semesters)
        if (filter == null || s.key == filter) s,
    ];
    final open = expanded ?? {semesters.first.key};
    void toggle(String key) =>
        setState(() => expanded = {...open}..toggle(key));
    final years = {for (final s in shown) s.year};
    return [
      if (semesters.length > 1) ...[
        NiuFilterBar<String?>(
          options: [
            (null, '全部'),
            for (final s in semesters) (s.key, s.shortLabel),
          ],
          value: filter,
          onChanged: (key) => setState(() => semesterFilter = key),
        ),
        const SizedBox(height: NiuSpacing.md),
      ],
      GradeSummaryCard(
        stats: GradeStatistics(shown.expand((s) => s.courses)),
        title: filter == null ? '累計 GPA（估算）' : '學期 GPA（估算）',
        trend: filter == null ? semesters.reversed.toList() : const [],
      ),
      for (final year in years)
        NiuSection(
          title: '$year 學年度',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, s) in shown.where((s) => s.year == year).indexed)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : NiuSpacing.md),
                  child: GradeSemesterCard(
                    semester: s,
                    expanded: open.contains(s.key),
                    onToggle: () => toggle(s.key),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> term(BuildContext context, Map value) {
    final courses = [
      for (final r in _rows(value['rows']))
        GradeCourse(
          // The results page has no term heading; its rows do.
          semester: '${value['title'] ?? ''}'.isNotEmpty
              ? '${value['title']}'
              : GradeCourse.semesterLabel(r[1], r[2]),
          name: r[4],
          type: r[3],
          score: r[5].isEmpty ? '尚未公布' : r[5],
        ),
    ];
    if (courses.isEmpty) {
      return const [
        NiuEmpty(
          icon: NiuIcons.grades,
          title: '還沒有成績',
          message: '學校公布成績後會出現在這裡。',
        ),
      ];
    }
    final semesters = courses.map((c) => c.semester).toSet();
    // Before they are out the page shows 「尚未計算」 or a bare 「第 名」.
    final average = '${value['average'] ?? ''}'.trim();
    final rank = formatRank('${value['rank'] ?? ''}');
    return [
      NiuCard(
        padding: const EdgeInsets.all(NiuSpacing.xl),
        child: Row(
          children: [
            Expanded(
              child: NiuStat(
                label: mode == GradeMode.midterm ? '期中平均' : '學期平均',
                value: double.tryParse(average) == null ? '—' : average,
              ),
            ),
            Expanded(
              child: NiuStat(label: '班級排名', value: rank.isEmpty ? '—' : rank),
            ),
            Expanded(
              child: NiuStat(label: '課程數', value: '${courses.length}'),
            ),
          ],
        ),
      ),
      for (final semester in semesters)
        NiuSection(
          title: semester.isEmpty ? '本學期' : semester,
          child: NiuGroup(
            insetDividers: NiuSpacing.lg,
            children: [
              for (final c in courses)
                if (c.semester == semester)
                  GradeCourseRow(
                    course: c,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NiuSpacing.lg,
                      vertical: NiuSpacing.md,
                    ),
                  ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => AcademicPortalScreen(
    key: ValueKey(mode),
    session: widget.session,
    title: '成績',
    header: NiuSegmented<GradeMode>(
      segments: [for (final e in labels.entries) (e.key, e.value)],
      value: mode,
      onChanged: (value) => setState(() {
        mode = value;
        semesterFilter = null;
        expanded = null;
      }),
    ),
    menuLabel: menus[mode],
    cacheKey: 'grades.${mode.name}',
    extractScript: gradeExtractScript(mode),
    demoSnapshot: () => DemoData.grades(mode.name),
    snapshotBuilder: (context, value) => ListView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.xs,
        NiuSpacing.gutter,
        NiuSpacing.huge,
      ),
      children: [
        ...(mode == GradeMode.history ? history : term)(context, value as Map),
        const SizedBox(height: NiuSpacing.xl),
        Text(
          '成績以學校系統公告為準',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    ),
  );
}

extension on Set<String> {
  /// Adds [key] if absent, removes it otherwise.
  void toggle(String key) => remove(key) || add(key);
}
