import 'package:flutter/material.dart';
import '../../core/web/academic_portal_screen.dart';
import 'grade_statistics.dart';
import '../../shared/shared.dart';

enum GradeMode { midterm, finalTerm, history }

class GradeSummaryCard extends StatelessWidget {
  const GradeSummaryCard({
    super.key,
    required this.courses,
    required this.title,
  });
  final Iterable<GradeCourse> courses;
  final String title;
  @override
  Widget build(BuildContext context) {
    final stats = GradeStatistics(courses);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NiuRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NiuSpacing.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${stats.gpa?.toStringAsFixed(2) ?? '—'} / 4.30',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            LinearProgressIndicator(value: (stats.gpa ?? 0) / 4.3),
            const SizedBox(height: 8),
            Text(
              '數字成績學分 ${stats.credits}・及格 ${stats.passedCredits}・加權平均 ${stats.average?.toStringAsFixed(2) ?? '—'}',
            ),
            const Text('依數字成績換算；通過、抵免等文字成績不列入 GPA。正式結果以校方為準。'),
          ],
        ),
      ),
    );
  }
}

class GradeCourse {
  const GradeCourse({
    required this.semester,
    required this.name,
    required this.type,
    required this.score,
    this.credits = 0,
  });
  final String semester, name, type, score;
  final double credits;
  bool get failed => double.tryParse(score) != null && double.parse(score) < 60;

  static List<GradeCourse> parseHistoryRows(List<List<String>> rows) {
    final result = <GradeCourse>[];
    for (final row in rows) {
      if (row.length < 5) continue;
      final sem = RegExp(r'^(\d{2,3})([123])$').firstMatch(row[0].trim());
      if (sem == null || row[3].trim().isEmpty || row[4].trim().isEmpty) {
        continue;
      }
      final term = {'1': '上', '2': '下', '3': '暑'}[sem[2]]!;
      result.add(
        GradeCourse(
          semester: '${sem[1]} 學年度 $term學期',
          type: row[1].trim(),
          credits: double.tryParse(row[2]) ?? 0,
          name: row[3].trim(),
          score: row[4].trim(),
        ),
      );
    }
    return result;
  }
}

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
  const doc = docs.find(d => d.querySelector('#DataGrid') && d.URL.includes('${mode == GradeMode.midterm ? 'GRD5131' : 'GRD5130'}'));
  if (!doc) return null;
  const rows = Array.from(doc.querySelectorAll('#DataGrid tr'), r => Array.from(r.querySelectorAll('td'), c => clean(c.innerText))).filter(r => r.length >= 6 && r[4]);
  const rank = clean(doc.querySelector('#QTable2 > tbody > tr:nth-child(2) > td:nth-child(2) > table > tbody > tr:nth-child(2) > td:nth-child(4)')?.innerText);
  return JSON.stringify({rows, rank, average: clean(doc.querySelector('#Q_CRS_AVG_MARK')?.innerText), title: clean(doc.body.innerText).match(/\\d{2,3}\\s*學年度\\s*第?\\s*[上下暑123]\\s*學期/)?.[0] || ''});
  '''}
})()
''';

class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key});
  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  GradeMode mode = GradeMode.finalTerm;
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
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(NiuSpacing.page),
            child: SegmentedButton<GradeMode>(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(48, 48)),
              ),
              segments: labels.entries
                  .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
                  .toList(),
              selected: {mode},
              onSelectionChanged: (value) => setState(() => mode = value.first),
            ),
          ),
        ),
        Expanded(
          child: AcademicPortalScreen(
            key: ValueKey(mode),
            title: '成績查詢',
            menuLabel: menus[mode],
            extractScript: gradeExtractScript(mode),
            snapshotBuilder: (context, value) {
              final rows = (value['rows'] as List)
                  .map((r) => (r as List).map((v) => v.toString()).toList())
                  .toList();
              final courses = mode == GradeMode.history
                  ? GradeCourse.parseHistoryRows(rows)
                  : rows
                        .map(
                          (r) => GradeCourse(
                            semester: value['title']?.toString() ?? '',
                            name: r[4],
                            type: r[3],
                            score: r[5].isEmpty ? '尚未公布' : r[5],
                          ),
                        )
                        .toList();
              final semesters = courses.map((c) => c.semester).toSet();
              return ListView(
                padding: const EdgeInsets.all(NiuSpacing.page),
                children: [
                  if (mode == GradeMode.history)
                    GradeSummaryCard(courses: courses, title: '累計 GPA（估算）'),
                  if (value['average'] != null && value['average'] != '')
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(NiuRadius.card),
                      ),
                      child: ListTile(
                        title: const Text('學期平均'),
                        trailing: Text(value['average'].toString()),
                      ),
                    ),
                  if (value['summary'] is List)
                    ...((value['summary'] as List).map(
                      (s) => Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(NiuRadius.card),
                        ),
                        child: ListTile(
                          title: Text('${s[0]} 學期'),
                          subtitle: Text('班級排名 ${s[2]}'),
                          trailing: Text('平均 ${s[3]}'),
                        ),
                      ),
                    )),
                  if (value['rank'] != null && value['rank'] != '')
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(NiuRadius.card),
                      ),
                      child: ListTile(
                        title: const Text('班級排名'),
                        trailing: Text(value['rank'].toString()),
                      ),
                    ),
                  if (courses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(NiuSpacing.section),
                      child: Text('校方尚未公布成績。'),
                    ),
                  for (final semester in semesters) ...[
                    if (mode == GradeMode.history)
                      GradeSummaryCard(
                        courses: courses.where((c) => c.semester == semester),
                        title: '$semester GPA',
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: NiuSpacing.compact,
                      ),
                      child: Text(
                        semester,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ...courses
                        .where((c) => c.semester == semester)
                        .map(
                          (c) => Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                NiuRadius.card,
                              ),
                            ),
                            child: ListTile(
                              title: Text(c.name),
                              subtitle: Text(
                                '${c.type}${mode == GradeMode.history ? ' · ${c.credits} 學分' : ''}',
                              ),
                              trailing: Text(
                                c.score,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: c.failed
                                          ? Theme.of(context).colorScheme.error
                                          : null,
                                    ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
