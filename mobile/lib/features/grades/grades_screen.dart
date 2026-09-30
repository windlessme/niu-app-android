import 'package:flutter/material.dart';
import '../../core/web/academic_portal_screen.dart';
import 'grade_statistics.dart';
import '../../shared/shared.dart';

enum GradeMode { midterm, finalTerm, history }

/// GPA overview: headline value, progress to 4.3 and supporting totals.
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
    final theme = Theme.of(context);
    final stats = GradeStatistics(courses);
    String n(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return NiuCard(
      padding: const EdgeInsets.all(NiuSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NiuStat(
            label: title,
            value: stats.gpa?.toStringAsFixed(2) ?? '—',
            unit: '/ 4.30',
            large: true,
          ),
          const SizedBox(height: NiuSpacing.md),
          NiuProgressBar(value: (stats.gpa ?? 0) / 4.3, semanticLabel: title),
          const SizedBox(height: NiuSpacing.lg),
          Row(
            children: [
              Expanded(
                child: NiuStat(label: '計分學分', value: n(stats.credits)),
              ),
              Expanded(
                child: NiuStat(label: '及格學分', value: n(stats.passedCredits)),
              ),
              Expanded(
                child: NiuStat(
                  label: '加權平均',
                  value: stats.average?.toStringAsFixed(1) ?? '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: NiuSpacing.lg),
          Text(
            '依數字成績估算；通過、抵免等文字成績不計入。正式結果以學校為準。',
            style: theme.textTheme.labelMedium,
          ),
        ],
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
  Widget courseGroup(BuildContext context, List<GradeCourse> courses) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return NiuGroup(
      insetDividers: NiuSpacing.lg,
      children: [
        for (final c in courses)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NiuSpacing.lg,
              vertical: NiuSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (c.type.isNotEmpty) c.type,
                          if (mode == GradeMode.history)
                            '${c.credits.toStringAsFixed(c.credits == c.credits.roundToDouble() ? 0 : 1)} 學分',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NiuSpacing.md),
                Text(
                  c.score,
                  style:
                      (double.tryParse(c.score) == null
                              ? theme.textTheme.titleSmall?.copyWith(
                                  color: colors.inkSecondary,
                                )
                              : theme.textTheme.titleLarge)
                          ?.copyWith(
                            color: c.failed ? colors.error : null,
                            fontFeatures: tabularFigures,
                          ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AcademicPortalScreen(
    key: ValueKey(mode),
    title: '成績',
    header: NiuSegmented<GradeMode>(
      segments: [for (final e in labels.entries) (e.key, e.value)],
      value: mode,
      onChanged: (value) => setState(() => mode = value),
    ),
    menuLabel: menus[mode],
    extractScript: gradeExtractScript(mode),
    snapshotBuilder: (context, value) {
      final theme = Theme.of(context);
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
      final semesters = courses.map((c) => c.semester).toSet().toList();
      if (mode == GradeMode.history) semesters.sort((a, b) => b.compareTo(a));
      final average = '${value['average'] ?? ''}';
      final rank = '${value['rank'] ?? ''}';
      final summary = value['summary'] is List
          ? (value['summary'] as List).whereType<List>().toList()
          : const <List>[];
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          NiuSpacing.gutter,
          NiuSpacing.xs,
          NiuSpacing.gutter,
          NiuSpacing.huge,
        ),
        children: [
          if (mode == GradeMode.history)
            GradeSummaryCard(courses: courses, title: '累計 GPA（估算）'),
          if (average.isNotEmpty || rank.isNotEmpty)
            NiuCard(
              padding: const EdgeInsets.all(NiuSpacing.xl),
              child: Row(
                children: [
                  if (average.isNotEmpty)
                    Expanded(
                      child: NiuStat(label: '學期平均', value: average),
                    ),
                  if (rank.isNotEmpty)
                    Expanded(
                      child: NiuStat(label: '班級排名', value: rank),
                    ),
                ],
              ),
            ),
          if (summary.isNotEmpty)
            NiuSection(
              title: '各學期排名',
              child: NiuGroup(
                insetDividers: NiuSpacing.lg,
                children: [
                  for (final s in summary)
                    if (s.length >= 4)
                      NiuRow(
                        title: '${s[0]} 學期',
                        subtitle: '班級排名 ${s[2]}',
                        value: '平均 ${s[3]}',
                      ),
                ],
              ),
            ),
          if (courses.isEmpty)
            const NiuEmpty(
              icon: NiuIcons.grades,
              title: '還沒有成績',
              message: '學校公布成績後會出現在這裡。',
            ),
          for (final (i, semester) in semesters.indexed)
            NiuSection(
              first:
                  i == 0 &&
                  mode != GradeMode.history &&
                  average.isEmpty &&
                  rank.isEmpty,
              title: semester.isEmpty ? '本學期' : semester,
              action: mode == GradeMode.history
                  ? Builder(
                      builder: (context) {
                        final gpa = GradeStatistics(
                          courses.where((c) => c.semester == semester),
                        ).gpa;
                        return gpa == null
                            ? const SizedBox.shrink()
                            : NiuBadge(
                                label: 'GPA ${gpa.toStringAsFixed(2)}',
                                tone: NiuTone.accent,
                              );
                      },
                    )
                  : null,
              child: courseGroup(
                context,
                courses.where((c) => c.semester == semester).toList(),
              ),
            ),
          const SizedBox(height: NiuSpacing.xl),
          Text(
            '成績以學校系統公告為準',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium,
          ),
        ],
      );
    },
  );
}
