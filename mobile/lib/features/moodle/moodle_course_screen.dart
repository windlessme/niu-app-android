import 'dart:async';

import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import '../attendance/attendance_repository.dart';
import '../attendance/attendance_screen.dart';
import 'course_detail_presentation.dart';
import 'course_detail_widgets.dart';
import 'course_presentation.dart';
import 'course_resource_tile.dart';
import 'course_widgets.dart';
import 'moodle_assignment_screen.dart';
import 'moodle_forum_screen.dart';
import 'moodle_links.dart';
import 'moodle_module_open.dart';
import 'moodle_question_screen.dart';
import 'moodle_questions.dart';
import 'moodle_repository.dart';
import 'moodle_upcoming.dart';

/// The parts of a course, in the order iOS lists them.
enum CourseDestination {
  assignments('作業', NiuIcons.assignment, NiuHue.blue),
  announcements('公告', NiuIcons.announcement, NiuHue.orange),
  resources('資源', NiuIcons.folder, NiuHue.teal),
  questions('問答', Icons.quiz_outlined, NiuHue.pink),
  attendance('出缺席', Icons.how_to_reg_outlined, NiuHue.green),
  grades('成績', NiuIcons.grades, NiuHue.purple);

  const CourseDestination(this.title, this.icon, this.hue);
  final String title;
  final IconData icon;
  final NiuHue hue;
}

/// One part's load: the last good data stays while a refresh runs or fails.
class CoursePart<T> {
  T? data;
  Object? error;
  bool loading = false;
  bool get loaded => data != null;
}

/// A search hit: what it is and where it sits.
typedef CourseSearchResult = ({String title, String subtitle});

/// Everything a course page shows, loaded in parallel, each part on its own
/// so one failure never hides the rest.
class CourseOverview extends ChangeNotifier {
  CourseOverview(this.repository, this.courseId);
  final MoodleRepository repository;
  final int courseId;
  final assignments = CoursePart<List<Json>>();
  final announcements = CoursePart<List<Json>>();
  final contents = CoursePart<List<Json>>();
  final grades = CoursePart<List<Json>>();
  final attendance = CoursePart<List<AttendanceSection>>();
  bool _disposed = false;

  CoursePart<Object?> part(CourseDestination d) => switch (d) {
    CourseDestination.assignments => assignments,
    CourseDestination.announcements => announcements,
    CourseDestination.resources || CourseDestination.questions => contents,
    CourseDestination.attendance => attendance,
    CourseDestination.grades => grades,
  };

  Future<void> _run<T>(CoursePart<T> part, Future<T> Function() load) async {
    part.loading = true;
    _notify();
    try {
      part.data = await load();
      part.error = null;
    } catch (error) {
      part.error = error;
    } finally {
      part.loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() => Future.wait([
    for (final d in [
      CourseDestination.assignments,
      CourseDestination.announcements,
      CourseDestination.resources,
      CourseDestination.grades,
      CourseDestination.attendance,
    ])
      retry(d),
  ]);

  Future<void> retry(CourseDestination d) => switch (d) {
    CourseDestination.assignments => _run(
      assignments,
      () => loadCourseAssignments(repository, courseId),
    ),
    CourseDestination.announcements => _run(
      announcements,
      () => repository.announcements(courseId),
    ),
    CourseDestination.resources || CourseDestination.questions => _run(
      contents,
      () => repository.contents(courseId),
    ),
    CourseDestination.attendance => _run(
      attendance,
      () => AttendanceRepository(
        repository,
      ).course(courseId).timeout(const Duration(seconds: 45)),
    ),
    CourseDestination.grades => _run(grades, () => repository.grades(courseId)),
  };

  static Object? status(Json a) =>
      a['submissionstatus'] ??
      (a['submission'] is Map ? a['submission']['status'] : null);

  /// Assignments known not to be submitted, due soonest first; those with no
  /// deadline last.
  List<Json> get pending =>
      [
        for (final a in assignments.data ?? const <Json>[])
          if (status(a) != null && status(a) != 'submitted') a,
      ]..sort((a, b) {
        final x = number(a['duedate']), y = number(b['duedate']);
        if (x <= 0 || y <= 0) return x <= 0 ? (y <= 0 ? 0 : 1) : -1;
        return x.compareTo(y);
      });

  /// Assignments whose submission state could not be read.
  int get unknown => (assignments.data ?? const <Json>[])
      .where((a) => status(a) == null)
      .length;

  List<Json> get latestAnnouncements => [...?announcements.data]
    ..sort(
      (a, b) => number(
        b['timemodified'] ?? b['timecreated'],
      ).compareTo(number(a['timemodified'] ?? a['timecreated'])),
    );

  /// Course sections with their materials and forums; question activities
  /// are listed under 問答 instead.
  List<Json> get resourceSections => [
    for (final s in contents.data ?? const <Json>[])
      if ([
            for (final m in objects(s['modules'] ?? []))
              if (MoodleQuestionKind.of(m) == null) m,
          ]
          case final modules
          when modules.isNotEmpty || plain(s['summary']).isNotEmpty)
        {...s, 'modules': modules},
  ];

  List<({String name, List<Json> modules})> get questionSections =>
      moodleQuestionSections(contents.data ?? const []);

  /// Present out of the sessions already marked, like iOS.
  int? get attendancePercent {
    final sections = attendance.data;
    if (sections == null) return null;
    final present = sections.fold(0, (n, s) => n + s.present);
    final marked = sections.fold(0, (n, s) => n + s.present + s.absent);
    return marked == 0 ? null : (present * 100 / marked).round();
  }

  String? get currentGrade {
    final course = (grades.data ?? const <Json>[])
        .where((g) => g['itemtype'] == 'course')
        .firstOrNull;
    if (course == null) return null;
    final value = gradeValue(course['gradeformatted']);
    return value == '未提供' ? null : value;
  }

  String nextDeadline(DateTime now) {
    if (assignments.error != null && !assignments.loaded) return '暫時無法更新';
    if (!assignments.loaded) return '載入中…';
    final next = pending.firstOrNull;
    if (next == null) return unknown > 0 ? '狀態未知' : '無待繳';
    final due = number(next['duedate']);
    if (due <= 0) return '未設定截止日';
    return UpcomingRules.deadline(
      DateTime.fromMillisecondsSinceEpoch(due * 1000),
      now,
    );
  }

  /// The short note beside each part in 課程內容, once it has loaded.
  String? detail(CourseDestination d) {
    if (!part(d).loaded) return null;
    return switch (d) {
      CourseDestination.assignments =>
        unknown > 0
            ? (pending.isEmpty
                  ? '$unknown 份狀態未知'
                  : '${pending.length} 份待繳、$unknown 份狀態未知')
            : '${pending.length} 份待繳',
      CourseDestination.announcements => '${announcements.data!.length} 則公告',
      CourseDestination.resources =>
        '${resourceSections.fold(0, (n, s) => n + objects(s['modules']).length)} 個項目',
      CourseDestination.questions =>
        '${questionSections.fold(0, (n, s) => n + s.modules.length)} 個活動',
      CourseDestination.attendance =>
        attendancePercent == null ? null : '出席 $attendancePercent%',
      CourseDestination.grades =>
        currentGrade == null ? null : '目前成績 $currentGrade',
    };
  }

  /// What each part holds, as searchable title, subtitle and other text.
  List<(CourseSearchResult, String)> _entries(
    CourseDestination d,
  ) => switch (d) {
    CourseDestination.assignments => [
      for (final a in assignments.data ?? const <Json>[])
        (
          (
            title: plain(a['name']),
            subtitle: number(a['duedate']) > 0
                ? '截止 ${campusTime(a['duedate'])}'
                : '未設定截止日',
          ),
          '',
        ),
    ],
    CourseDestination.announcements => [
      for (final a in latestAnnouncements)
        (
          (
            title: plain(a['subject'] ?? a['name']),
            subtitle:
                '${plain(a['userfullname'])}・${campusTime(a['timemodified'] ?? a['timecreated'])}',
          ),
          plain(a['message']),
        ),
    ],
    CourseDestination.resources => [
      for (final s in resourceSections)
        for (final m in objects(s['modules']))
          (
            (
              title: plain(m['name']),
              subtitle: courseDateRange(plain(s['name'])),
            ),
            '',
          ),
    ],
    CourseDestination.questions => [
      for (final s in questionSections)
        for (final m in s.modules)
          ((title: plain(m['name']), subtitle: courseDateRange(s.name)), ''),
    ],
    CourseDestination.attendance => [
      for (final s in attendance.data ?? const <AttendanceSection>[])
        for (final r in s.records)
          (
            (
              title: r.description.isEmpty ? '課堂點名' : r.description,
              subtitle: '${r.date}・${r.label}',
            ),
            r.remarks,
          ),
    ],
    CourseDestination.grades => [
      for (final g in grades.data ?? const <Json>[])
        (
          (
            title: plain(g['itemname']).isEmpty
                ? '課程總成績'
                : plain(g['itemname']),
            subtitle: gradeValue(g['gradeformatted']) == '未提供'
                ? '尚未公布'
                : gradeValue(g['gradeformatted']),
          ),
          '',
        ),
    ],
  };

  List<CourseSearchResult> search(CourseDestination d, String query) {
    final q = query.trim().toLowerCase();
    return [
      for (final (result, other) in _entries(d))
        if ([
          result.title,
          result.subtitle,
          other,
        ].any((t) => t.toLowerCase().contains(q)))
          result,
    ];
  }
}

/// Assignments with their submission state, read per assignment; a missing
/// state never hides one or implies it was not submitted.
Future<List<Json>> loadCourseAssignments(
  MoodleRepository repository,
  int course,
) async {
  final assignments = sortCourseAssignments(
    await repository.assignments(course),
  );
  return Future.wait(
    assignments.map((assignment) async {
      try {
        final detail = await repository.submission(number(assignment['id']));
        final attempt = detail['lastattempt'];
        final submission = attempt is Map ? attempt['submission'] : null;
        return <String, dynamic>{
          ...assignment,
          if (submission is Map) 'submissionstatus': submission['status'],
          if (attempt is Map && attempt['graded'] is bool)
            'graded': attempt['graded'],
        };
      } catch (_) {
        return assignment;
      }
    }),
  );
}

/// A course, as on iOS: who teaches it, what is due next, the latest news
/// and every part of the course one tap away, with search across all of it.
class MoodleCourseScreen extends StatefulWidget {
  const MoodleCourseScreen({
    super.key,
    required this.repository,
    required this.course,
  });
  final MoodleRepository repository;
  final Json course;
  @override
  State<MoodleCourseScreen> createState() => _MoodleCourseScreenState();
}

class _MoodleCourseScreenState extends State<MoodleCourseScreen> {
  late final presentation = CoursePresentation(widget.course);
  late final overview = CourseOverview(
    widget.repository,
    number(widget.course['id']),
  );
  final query = TextEditingController();
  Timer? clock;

  @override
  void initState() {
    super.initState();
    overview.load();
    // Deadlines read 「2 小時後」; keep them current.
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    overview.dispose();
    query.dispose();
    super.dispose();
  }

  void open(CourseDestination d, {String search = ''}) => pushMoodle(
    context,
    CourseDestinationScreen(
      overview: overview,
      destination: d,
      repository: widget.repository,
      course: widget.course,
      initialQuery: search,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: overview,
    builder: (context, _) {
      final searching = query.text.trim().isNotEmpty;
      return NiuScrollPage(
        title: '課程',
        onRefresh: overview.load,
        children: [
          if (!searching) ...[
            _header(context),
            const SizedBox(height: NiuSpacing.md),
          ],
          NiuSearchField(
            controller: query,
            hint: '搜尋整門課',
            onChanged: (_) => setState(() {}),
          ),
          if (searching) ..._search(context) else ..._sections(context),
        ],
      );
    },
  );

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final summary = [
      ('下一份待繳', overview.nextDeadline(DateTime.now())),
      if (overview.attendancePercent case final p?) ('出席率', '$p%'),
      if (overview.currentGrade case final g?) ('目前成績', g),
    ];
    return NiuCard(
      padding: const EdgeInsets.all(NiuSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(presentation.title, style: theme.textTheme.headlineSmall),
          if (presentation.teacher.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.xs),
            Text(presentation.teacher, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: NiuSpacing.lg),
          Wrap(
            spacing: NiuSpacing.xxl,
            runSpacing: NiuSpacing.md,
            children: [
              for (final (label, value) in summary)
                Semantics(
                  label: '$label $value',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.labelMedium),
                      const SizedBox(height: 2),
                      Text(value, style: theme.textTheme.titleSmall),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Loading or a failure of one part, without hiding what it already has.
  Widget _status(CourseDestination d) {
    final part = overview.part(d);
    if (part.loading && !part.loaded) {
      return Padding(
        padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
        child: NiuLoading(message: '正在載入${d.title}'),
      );
    }
    if (part.error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
        child: NiuBanner(
          tone: NiuTone.warning,
          message: part.loaded ? '${d.title}更新失敗，保留上次資料' : '${d.title}更新失敗',
          actionLabel: '重試',
          onAction: () => overview.retry(d),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _sections(BuildContext context) {
    final now = DateTime.now();
    final pending = overview.pending;
    final latest = overview.latestAnnouncements.take(3).toList();
    return [
      NiuSection(
        title: '待繳作業',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _status(CourseDestination.assignments),
            if (overview.assignments.loaded)
              NiuGroup(
                children: [
                  if (pending.isEmpty)
                    NiuRow(
                      title: overview.unknown > 0
                          ? '${overview.unknown} 份作業狀態未知，請到作業頁確認'
                          : '沒有待繳作業',
                      chevron: false,
                    ),
                  for (final a in pending.take(3))
                    NiuRow(
                      icon: NiuIcons.assignment,
                      hue: NiuHue.blue,
                      title: plain(a['name']),
                      subtitle: number(a['duedate']) > 0
                          ? UpcomingRules.deadline(
                              DateTime.fromMillisecondsSinceEpoch(
                                number(a['duedate']) * 1000,
                              ),
                              now,
                            )
                          : '未設定截止日',
                      onTap: () => pushMoodle(
                        context,
                        MoodleAssignmentScreen(
                          repository: widget.repository,
                          assignment: a,
                        ),
                      ),
                    ),
                  if (pending.length > 3)
                    NiuRow(
                      title: '查看全部作業（${pending.length}）',
                      onTap: () => open(CourseDestination.assignments),
                    ),
                ],
              ),
          ],
        ),
      ),
      NiuSection(
        title: '最新公告',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _status(CourseDestination.announcements),
            if (overview.announcements.loaded)
              NiuGroup(
                children: [
                  if (latest.isEmpty)
                    const NiuRow(title: '目前沒有公告', chevron: false),
                  for (final d in latest)
                    NiuRow(
                      title: plain(d['subject'] ?? d['name']),
                      subtitle:
                          '${plain(d['userfullname'])}・${campusTime(d['timemodified'] ?? d['timecreated'])}',
                      onTap: () => pushMoodle(
                        context,
                        MoodleDiscussionScreen(
                          repository: widget.repository,
                          discussion: d,
                        ),
                      ),
                    ),
                  if (latest.isNotEmpty)
                    NiuRow(
                      title: '查看全部公告',
                      onTap: () => open(CourseDestination.announcements),
                    ),
                ],
              ),
          ],
        ),
      ),
      NiuSection(
        title: '課程內容',
        child: NiuGroup(
          children: [
            for (final d in CourseDestination.values)
              NiuRow(
                icon: d.icon,
                hue: d.hue,
                title: d.title,
                value: overview.detail(d),
                onTap: () => open(d),
              ),
            NiuRow(
              icon: NiuIcons.document,
              hue: NiuHue.gray,
              title: '課程說明',
              onTap: () => pushMoodle(
                context,
                Scaffold(
                  appBar: const NiuAppBar(title: '課程說明'),
                  body: ListView(
                    padding: const EdgeInsets.all(NiuSpacing.gutter),
                    children: [MoodleCourseInformation(course: presentation)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _search(BuildContext context) {
    final groups = [
      for (final d in CourseDestination.values)
        (d, overview.search(d, query.text)),
    ];
    final settled = CourseDestination.values.every(
      (d) => overview.part(d).loaded || overview.part(d).error != null,
    );
    if (settled && groups.every((g) => g.$2.isEmpty)) {
      return [
        const SizedBox(height: NiuSpacing.xl),
        NiuEmpty(
          icon: NiuIcons.search,
          title: '找不到符合的結果',
          message: '找不到符合「${query.text.trim()}」的項目，請試試其他關鍵字。',
        ),
      ];
    }
    return [
      for (final (d, results) in groups)
        if (results.isNotEmpty || !overview.part(d).loaded)
          NiuSection(
            title: overview.part(d).loaded
                ? '${d.title}（${results.length}）'
                : d.title,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _status(d),
                if (results.isNotEmpty)
                  NiuGroup(
                    children: [
                      for (final r in results.take(3))
                        NiuRow(
                          title: r.title,
                          subtitle: r.subtitle,
                          onTap: () => open(d, search: query.text),
                        ),
                      NiuRow(
                        title: '查看全部${d.title}（${results.length}）',
                        onTap: () => open(d, search: query.text),
                      ),
                    ],
                  ),
              ],
            ),
          ),
    ];
  }
}

/// One part of a course, with its own search.
class CourseDestinationScreen extends StatefulWidget {
  const CourseDestinationScreen({
    super.key,
    required this.overview,
    required this.destination,
    required this.repository,
    required this.course,
    this.initialQuery = '',
  });
  final CourseOverview overview;
  final CourseDestination destination;
  final MoodleRepository repository;
  final Json course;
  final String initialQuery;
  @override
  State<CourseDestinationScreen> createState() =>
      _CourseDestinationScreenState();
}

class _CourseDestinationScreenState extends State<CourseDestinationScreen> {
  late final query = TextEditingController(text: widget.initialQuery);
  CourseDestination get d => widget.destination;
  CourseOverview get overview => widget.overview;
  int get courseId => number(widget.course['id']);

  /// 公告 newest first; 作業 nearest deadline first. Either can be flipped.
  bool forward = true;

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  bool matches(Iterable<Object?> texts) {
    final q = query.text.trim().toLowerCase();
    return q.isEmpty || texts.any((t) => plain(t).toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: overview,
    builder: (context, _) {
      final part = overview.part(d);
      final sortable =
          d == CourseDestination.announcements ||
          d == CourseDestination.assignments;
      return NiuScrollPage(
        title: d.title,
        onRefresh: () => overview.retry(d),
        actions: [
          if (sortable)
            NiuIconButton(
              icon: Icons.swap_vert_rounded,
              tooltip: d == CourseDestination.assignments
                  ? (forward ? '截止日：近的在上' : '截止日：遠的在上')
                  : (forward ? '最新的在上' : '最舊的在上'),
              onPressed: () => setState(() => forward = !forward),
            ),
        ],
        children: [
          if (d != CourseDestination.attendance) ...[
            NiuSearchField(
              controller: query,
              hint: '搜尋${d.title}',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: NiuSpacing.lg),
          ],
          if (d == CourseDestination.attendance)
            AttendanceRecords(repository: widget.repository, courseId: courseId)
          else if (part.loading && !part.loaded)
            NiuLoading(message: '正在載入${d.title}')
          else if (part.error != null && !part.loaded)
            NiuError(title: '${d.title}載入失敗', onRetry: () => overview.retry(d))
          else
            ..._items(context),
        ],
      );
    },
  );

  List<Widget> _empty(String title, String message, IconData icon) => [
    NiuEmpty(
      icon: query.text.trim().isEmpty ? icon : NiuIcons.search,
      title: query.text.trim().isEmpty ? title : '找不到符合的結果',
      message: query.text.trim().isEmpty ? message : '換個關鍵字試試。',
    ),
  ];

  List<Widget> _items(BuildContext context) {
    final repository = widget.repository;
    switch (d) {
      case CourseDestination.assignments:
        final list = [
          for (final a in overview.assignments.data ?? const <Json>[])
            if (matches([a['name']])) a,
        ];
        if (list.isEmpty) {
          return _empty('沒有作業', '老師指派的作業會依截止時間排在這裡。', NiuIcons.assignment);
        }
        return [
          for (final a in forward ? list : list.reversed)
            courseAssignmentItem(context, repository, a),
        ];
      case CourseDestination.announcements:
        final list = [
          for (final a in overview.latestAnnouncements)
            if (matches([
              a['subject'],
              a['name'],
              a['message'],
              a['userfullname'],
            ]))
              a,
        ];
        if (list.isEmpty) {
          return _empty('還沒有公告', '老師發布的消息會出現在這裡。', NiuIcons.announcement);
        }
        return [
          for (final a in forward ? list : list.reversed)
            courseDiscussionItem(context, repository, a),
        ];
      case CourseDestination.resources:
        final searching = query.text.trim().isNotEmpty;
        final sections = [
          for (final s in overview.resourceSections)
            if ([
                  for (final m in objects(s['modules']))
                    if (matches([m['name'], s['name']])) m,
                ]
                case final modules
                when modules.isNotEmpty ||
                    (!searching && plain(s['summary']).isNotEmpty))
              {...s, 'modules': modules},
        ];
        if (sections.isEmpty) {
          return _empty('還沒有資源', '老師上傳的講義、討論區和其他資源會依週次排在這裡。', NiuIcons.folder);
        }
        return [
          for (final s in sections)
            _section(
              context,
              plain(s['name']),
              summary: searching ? '' : plain(s['summary']),
              rows: [
                for (final m in objects(s['modules']))
                  CourseResourceTile(
                    module: m,
                    onTap: () =>
                        openMoodleModule(context, repository, courseId, m),
                  ),
              ],
            ),
        ];
      case CourseDestination.questions:
        final sections = [
          for (final s in overview.questionSections)
            if ([
                  for (final m in s.modules)
                    if (matches([m['name'], s.name])) m,
                ]
                case final modules when modules.isNotEmpty)
              (name: s.name, modules: modules),
        ];
        if (sections.isEmpty) {
          return _empty(
            '目前沒有問答活動',
            '老師開放的測驗、即時問答、選擇與問卷會出現在這裡。',
            Icons.quiz_outlined,
          );
        }
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.lg),
            child: Text(
              '選擇活動後，可以在 App 內查看題目與作答。開放時間、提交與結果以 M 園區為準。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final s in sections)
            _section(
              context,
              s.name,
              rows: [
                for (final m in s.modules)
                  NiuRow(
                    icon: Icons.quiz_outlined,
                    hue: NiuHue.pink,
                    title: plain(m['name']),
                    subtitle: MoodleQuestionKind.entry(m) == null
                        ? '尚未開放或未符合存取條件'
                        : MoodleQuestionKind.of(m)!.title,
                    onTap: MoodleQuestionKind.entry(m) == null
                        ? null
                        : () => pushMoodle(
                            context,
                            MoodleQuestionScreen(
                              repository: repository,
                              module: m,
                            ),
                          ),
                  ),
              ],
            ),
        ];
      case CourseDestination.attendance:
        return const [];
      case CourseDestination.grades:
        final list = [
          for (final g in overview.grades.data ?? const <Json>[])
            if (matches([g['itemname'], g['gradeformatted']])) g,
        ];
        if (list.isEmpty) {
          return _empty('還沒有成績', '老師公布的評分項目會出現在這裡。', NiuIcons.grades);
        }
        return [for (final g in list) courseGradeItem(context, g)];
    }
  }

  Widget _section(
    BuildContext context,
    String name, {
    String summary = '',
    required List<Widget> rows,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: NiuSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: NiuSpacing.xs,
            bottom: NiuSpacing.sm,
          ),
          child: Semantics(
            header: true,
            child: Text(
              courseDateRange(name),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        if (summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
            child: NiuWell(
              padding: const EdgeInsets.all(NiuSpacing.lg),
              child: SelectableText(summary),
            ),
          ),
        if (rows.isNotEmpty) NiuGroup(children: rows),
      ],
    ),
  );
}

Widget courseDiscussionItem(
  BuildContext context,
  MoodleRepository repository,
  Json d,
) => CourseDetailItem(
  title: plain(d['subject'] ?? d['name']),
  metadata:
      '${plain(d['userfullname']).isEmpty ? '作者未提供' : plain(d['userfullname'])} · ${campusTime(d['timemodified'] ?? d['timecreated'])}',
  excerpt: plain(d['message']),
  children: [
    for (final file in objects(d['attachments'] ?? []))
      MoodleAttachmentButton(
        name: plain(file['filename']),
        onPressed: file['fileurl'] is String
            ? () => openMoodleUrl(
                context,
                repository,
                file['fileurl'],
                plain(file['filename']),
                file: true,
              )
            : null,
      ),
  ],
  onTap: () => pushMoodle(
    context,
    MoodleDiscussionScreen(repository: repository, discussion: d),
  ),
);

Widget courseAssignmentItem(
  BuildContext context,
  MoodleRepository repository,
  Json a,
) {
  final status = CourseOverview.status(a);
  return CourseDetailItem(
    badge: Wrap(
      spacing: NiuSpacing.sm,
      runSpacing: NiuSpacing.xs,
      children: [
        NiuBadge(label: submissionLabel(status), tone: submissionTone(status)),
        if (a['graded'] is bool)
          NiuBadge(
            label: a['graded'] == true ? '已評分' : '尚未評分',
            tone: a['graded'] == true ? NiuTone.success : NiuTone.neutral,
          ),
      ],
    ),
    title: plain(a['name']),
    metadata: '截止 ${campusTime(a['duedate'])}',
    onTap: () => pushMoodle(
      context,
      MoodleAssignmentScreen(repository: repository, assignment: a),
    ),
  );
}

Widget courseGradeItem(BuildContext context, Json g) {
  final theme = Theme.of(context);
  final value = gradeValue(g['gradeformatted']);
  final published = value != '未提供';
  return Padding(
    padding: const EdgeInsets.only(bottom: NiuSpacing.md),
    child: NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  plain(g['itemname']).isEmpty ? '課程總成績' : plain(g['itemname']),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: NiuSpacing.md),
              Text(
                published ? value : '尚未公布',
                style:
                    (published
                            ? theme.textTheme.headlineSmall
                            : theme.textTheme.titleSmall?.copyWith(
                                color: NiuColors.of(context).inkTertiary,
                              ))
                        ?.copyWith(fontFeatures: tabularFigures),
              ),
            ],
          ),
          const SizedBox(height: NiuSpacing.sm),
          NiuKeyValue(label: '範圍', value: gradeValue(g['rangeformatted'])),
          NiuKeyValue(
            label: '百分比',
            value: gradeValue(g['percentageformatted']),
          ),
          NiuKeyValue(label: '權重', value: gradeValue(g['weightformatted'])),
          if (plain(g['feedback']).isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.sm),
            NiuWell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('老師回饋', style: theme.textTheme.labelMedium),
                  const SizedBox(height: NiuSpacing.xs),
                  SelectableText(plain(g['feedback'])),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
