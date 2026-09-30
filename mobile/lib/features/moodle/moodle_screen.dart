import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/shared.dart';
import 'course_presentation.dart';
import 'course_widgets.dart';
import 'course_resource_tile.dart';
import 'course_detail_presentation.dart';
import 'course_detail_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/school_clients.dart';
import '../../core/session/campus_session.dart';
import '../authentication/login_screen.dart';
import '../attendance/attendance_screen.dart';
import '../attendance/attendance_result_screen.dart';
import '../attendance/attendance_repository.dart' show attendanceQr;
import 'moodle_repository.dart';
import 'moodle_web_screen.dart';
import 'moodle_session_store.dart';
import 'moodle_login_service.dart';
import 'moodle_attachment_screen.dart';

void pushMoodle(BuildContext context, Widget screen) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => screen));

class MoodleScreen extends StatefulWidget {
  const MoodleScreen({
    super.key,
    this.account,
    this.password,
    this.repository,
    this.onAuthenticated,
  });
  final String? account, password;
  final MoodleRepository? repository;
  final ValueChanged<MoodleRepository>? onAuthenticated;
  @override
  State<MoodleScreen> createState() => _MoodleScreenState();
}

class _MoodleScreenState extends State<MoodleScreen> {
  late final account = TextEditingController(text: widget.account);
  late final password = TextEditingController(text: widget.password);
  MoodleRepository? repository;
  String? error;
  bool busy = false;
  int loginGeneration = 0;
  late final sessionStore = MoodleSessionStore(CampusSession.instance);
  @override
  void initState() {
    super.initState();
    repository = widget.repository;
    if (CampusSession.instance.hasLocalAccount) {
      repository?.bindSession(CampusSession.instance);
    }
    CampusSession.instance.registerCleanup(clearSession);
    if (repository == null &&
        widget.account != null &&
        widget.password != null) {
      restoreOrLogin();
    } else if (repository == null) {
      restoreOrLogin();
    }
  }

  Future<void> restoreOrLogin() async {
    final generation = ++loginGeneration;
    setState(() => busy = true);
    try {
      final restored = await sessionStore.restore(
        MoodleApiClient(schoolClient('https://euni.niu.edu.tw')),
      );
      if (!mounted || generation != loginGeneration) return;
      if (restored != null) {
        setState(() => repository = restored);
        widget.onAuthenticated?.call(restored);
      }
    } catch (_) {
      if (mounted && generation == loginGeneration) {
        setState(() => error = '目前無法恢復 M 園區登入。檢查網路後再試一次，或重新登入。');
      }
    }
    if (!mounted || generation != loginGeneration) return;
    setState(() => busy = false);
    if (repository == null && password.text.isNotEmpty) await login();
  }

  Future<void> login() async {
    if (busy) return;
    final generation = ++loginGeneration;
    final epoch = CampusSession.instance.coordinator.epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await MoodleLoginService(CampusSession.instance).establish(
        account: account.text.trim(),
        password: password.text,
        epoch: epoch,
      );
      if (!mounted || generation != loginGeneration) return;
      CampusSession.instance.coordinator.requireCurrent(epoch);
      if (!mounted || generation != loginGeneration) return;
      password.clear();
      setState(() => repository = result);
      widget.onAuthenticated?.call(result);
    } catch (_) {
      if (mounted && generation == loginGeneration) {
        setState(() => error = 'M 園區登入失敗，請確認帳號密碼與網路連線。');
      }
    } finally {
      if (mounted && generation == loginGeneration) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant MoodleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account ||
        oldWidget.repository != widget.repository) {
      loginGeneration++;
      busy = false;
      repository = widget.repository;
      account.text = widget.account ?? '';
      password.text = widget.password ?? '';
      error = null;
      if (repository == null && !busy) {
        restoreOrLogin();
      }
    }
  }

  @override
  void dispose() {
    sessionStore.dispose();
    CampusSession.instance.unregisterCleanup(clearSession);
    account.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> clearSession() async {
    loginGeneration++;
    await repository?.invalidate();
    if (!mounted) return;
    setState(() {
      repository = null;
      busy = false;
      password.clear();
      account.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = repository;
    if (repo != null) {
      return MoodleCoursesScreen(key: ValueKey(repo.session), repository: repo);
    }
    return NiuScrollPage(
      title: 'M 園區',
      large: true,
      showBack: false,
      children: [
        if (busy)
          const NiuLoading(message: '正在連接 M 園區')
        else
          NiuEmpty(
            icon: NiuIcons.moodle,
            tone: NiuTone.accent,
            title: '連接 M 園區',
            message: error ?? '用學校帳號登入一次，就能在這裡看課程、公告、作業和成績。',
            action: FilledButton(
              onPressed: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
                if (mounted) await restoreOrLogin();
              },
              child: const Text('登入'),
            ),
            secondaryAction: TextButton(
              onPressed: restoreOrLogin,
              child: const Text('重新連線'),
            ),
          ),
      ],
    );
  }
}

class MoodleList extends StatefulWidget {
  const MoodleList({
    super.key,
    required this.load,
    required this.item,
    this.header,
  });
  final Future<List<Json>> Function() load;
  final Widget Function(Json item) item;
  final Widget? header;
  @override
  State<MoodleList> createState() => _MoodleListState();
}

class _MoodleListState extends State<MoodleList> {
  late Future<List<Json>> future = Future.sync(widget.load);
  List<Json>? retained;
  bool refreshing = false;
  Future<void> reload() async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      future = Future.sync(widget.load);
    });
    try {
      await future;
      if (mounted) HapticFeedback.lightImpact();
    } catch (_) {
      // FutureBuilder presents the error while retaining the last result.
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Json>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData) {
        retained = snapshot.data;
      }
      const padding = EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.lg,
        NiuSpacing.gutter,
        NiuSpacing.huge,
      );
      if (snapshot.hasError && retained == null) {
        return ListView(
          padding: padding,
          children: [
            ?widget.header,
            NiuError(message: '檢查網路連線，或重新登入 M 園區。', onRetry: reload),
          ],
        );
      }
      if (retained == null) {
        return ListView(
          padding: padding,
          children: [
            ?widget.header,
            const NiuLoading(message: '正在讀取'),
          ],
        );
      }
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          itemCount: retained!.length + 1,
          itemBuilder: (context, index) => index == 0
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?widget.header,
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.only(bottom: NiuSpacing.md),
                        child: NiuSyncStatus(updatedAt: null, refreshing: true),
                      ),
                    if (snapshot.hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                        child: NiuBanner(
                          tone: NiuTone.warning,
                          message: '更新失敗，先顯示上次的資料。',
                          actionLabel: '再試一次',
                          onAction: refreshing ? null : reload,
                        ),
                      ),
                    if (retained!.isEmpty)
                      const NiuEmpty(
                        icon: NiuIcons.notifications,
                        title: '沒有新消息',
                        message: '有新的通知時會出現在這裡。',
                      ),
                  ],
                )
              : widget.item(retained![index - 1]),
        ),
      );
    },
  );
}

class MoodleCoursesScreen extends StatefulWidget {
  const MoodleCoursesScreen({super.key, required this.repository});
  final MoodleRepository repository;
  @override
  State<MoodleCoursesScreen> createState() => _MoodleCoursesScreenState();
}

class _MoodleCoursesScreenState extends State<MoodleCoursesScreen> {
  String query = '';
  String? semester;
  final search = TextEditingController();
  List<Json>? retained;
  List<CoursePresentation> presented = [];
  late Future<List<Json>> future = Future.sync(widget.repository.courses);
  bool refreshing = false;
  Future<void> reload() async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      future = Future.sync(widget.repository.courses);
    });
    try {
      await future;
      if (mounted) HapticFeedback.lightImpact();
    } catch (_) {
      // FutureBuilder presents the error while retaining the last result.
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void openNotifications() => pushMoodle(
    context,
    Scaffold(
      appBar: const NiuAppBar(title: '通知'),
      body: MoodleList(
        load: widget.repository.notifications,
        item: (n) => CourseDetailItem(
          title: plain(n['subject']),
          metadata: campusTime(n['timecreated']) == '未設定'
              ? null
              : campusTime(n['timecreated']),
          excerpt: plain(
            n['fullmessagehtml'] ?? n['fullmessage'] ?? n['smallmessage'],
          ),
          onTap: n['contexturl'] is String
              ? () => openMoodleUrl(
                  context,
                  widget.repository,
                  '${n['contexturl']}',
                  '通知',
                )
              : null,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Json>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData &&
          !identical(retained, snapshot.data)) {
        retained = snapshot.data;
        presented = retained!.map(CoursePresentation.new).toList();
        if (semester != null && !presented.any((c) => c.semester == semester)) {
          semester = null;
        }
      }
      final actions = [
        NiuIconButton(
          tooltip: '點名掃描',
          icon: NiuIcons.attendance,
          onPressed: () => pushMoodle(
            context,
            AttendanceScannerScreen(repository: widget.repository),
          ),
        ),
        NiuIconButton(
          tooltip: '通知',
          icon: NiuIcons.notifications,
          onPressed: openNotifications,
        ),
      ];
      if (retained == null) {
        return NiuScrollPage(
          title: 'M 園區',
          large: true,
          showBack: false,
          actions: actions,
          children: [
            if (snapshot.hasError)
              NiuError(
                title: '無法讀取課程',
                message: '檢查網路連線後再試一次。',
                onRetry: reload,
              )
            else
              const NiuLoading(message: '正在讀取我的課程'),
          ],
        );
      }
      final terms =
          presented
              .map((c) => c.semester)
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
      final normalizedQuery = query.trim().toLowerCase();
      final courses = presented
          .where(
            (c) =>
                (semester == null || c.semester == semester) &&
                c.searchText.contains(normalizedQuery),
          )
          .toList();
      return NiuScrollPage(
        title: 'M 園區',
        large: true,
        showBack: false,
        actions: actions,
        onRefresh: reload,
        children: [
          NiuSearchField(
            controller: search,
            hint: '搜尋課程、老師或代碼',
            onChanged: (v) => setState(() => query = v),
          ),
          if (terms.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.md),
            NiuFilterBar<String?>(
              options: [
                (null, '全部學期'),
                for (final t in terms)
                  (t, t.length == 4 ? '${t.substring(0, 3)}-${t[3]}' : t),
              ],
              value: semester,
              onChanged: (t) => setState(() => semester = t),
            ),
          ],
          const SizedBox(height: NiuSpacing.lg),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(
              padding: EdgeInsets.only(bottom: NiuSpacing.md),
              child: NiuSyncStatus(updatedAt: null, refreshing: true),
            ),
          if (snapshot.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: NiuSpacing.md),
              child: NiuBanner(
                tone: NiuTone.warning,
                message: '更新失敗，先顯示上次的課程。',
                actionLabel: '再試一次',
                onAction: refreshing ? null : reload,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(
              left: NiuSpacing.xs,
              bottom: NiuSpacing.md,
            ),
            child: Text(
              semester == null
                  ? '${courses.length} 門課程'
                  : '${semesterLabel(semester!)} · ${courses.length} 門課程',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (courses.isEmpty)
            NiuEmpty(
              icon: NiuIcons.search,
              title: presented.isEmpty ? '還沒有課程' : '找不到符合的課程',
              message: presented.isEmpty ? '選課完成後，課程會自動出現在這裡。' : '換個關鍵字或學期試試。',
            ),
          for (final course in courses)
            MoodleCourseCard(
              course: course,
              onTap: () => pushMoodle(
                context,
                MoodleCourseScreen(
                  repository: widget.repository,
                  course: course.source,
                ),
              ),
            ),
        ],
      );
    },
  );
}

Future<void> openMoodleUrl(
  BuildContext context,
  MoodleRepository repository,
  String raw,
  String title, {
  bool file = false,
}) async {
  try {
    final uri = Uri.parse(raw);
    if (file || uri.path.contains('/pluginfile.php/')) {
      pushMoodle(
        context,
        MoodleAttachmentScreen(repository: repository, url: raw, name: title),
      );
    } else if (uri.host == 'euni.niu.edu.tw') {
      if (attendanceQr(raw) != null) {
        final confirmed = await confirmNiuAction(
          context,
          title: '要開啟點名嗎？',
          message: '開啟這個頁面可能會直接記錄出席。',
          confirmLabel: '開啟並點名',
        );
        if (!confirmed || !context.mounted) return;
        pushMoodle(
          context,
          AttendanceResultScreen(
            repository: repository,
            target: attendanceQr(raw)!,
          ),
        );
        return;
      }
      pushMoodle(
        context,
        MoodleWebScreen(repository: repository, target: uri, title: title),
      );
    } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.userInfo.isEmpty) {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException();
      }
    } else {
      throw const FormatException();
    }
  } catch (_) {
    if (context.mounted) {
      showNiuMessage(context, '無法開啟這個連結');
    }
  }
}

class MoodleCourseScreen extends StatelessWidget {
  const MoodleCourseScreen({
    super.key,
    required this.repository,
    required this.course,
  });
  final MoodleRepository repository;
  final Json course;
  int get id => number(course['id']);
  Future<List<Json>> loadAssignments() async {
    final assignments = sortCourseAssignments(await repository.assignments(id));
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
          // A missing status must not hide the assignment or imply non-submission.
          return assignment;
        }
      }),
    );
  }

  Widget discussion(BuildContext context, Json d) => CourseDetailItem(
    title: plain(d['subject'] ?? d['name']),
    metadata:
        '${plain(d['userfullname']).isEmpty ? '作者未提供' : plain(d['userfullname'])} · ${campusTime(d['timemodified'] ?? d['timecreated'])}',
    excerpt: plain(d['message']),
    children: [
      for (final file in objects(d['attachments'] ?? []))
        _AttachmentButton(
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

  Widget assignment(BuildContext context, Json a) {
    final status =
        a['submissionstatus'] ??
        (a['submission'] is Map ? a['submission']['status'] : null);
    return CourseDetailItem(
      badge: Wrap(
        spacing: NiuSpacing.sm,
        runSpacing: NiuSpacing.xs,
        children: [
          NiuBadge(
            label: submissionLabel(status),
            tone: submissionTone(status),
          ),
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

  Widget grade(BuildContext context, Json g) {
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
                    plain(g['itemname']).isEmpty
                        ? '課程總成績'
                        : plain(g['itemname']),
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const NiuAppBar(title: '課程'),
    body: CourseDetailTabs(
      builders: [
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.announcement,
          emptyTitle: '還沒有公告',
          emptyMessage: '老師發布的消息會出現在這裡。',
          header: MoodleCourseInformation(course: CoursePresentation(course)),
          load: () => repository.announcements(id),
          item: (d) => discussion(context, d),
        ),
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.folder,
          emptyTitle: '還沒有教材',
          emptyMessage: '老師上傳的講義和資源會依週次排在這裡。',
          load: () async => (await repository.contents(id))
              .where(
                (s) =>
                    objects(s['modules']).isNotEmpty ||
                    plain(s['summary']).isNotEmpty,
              )
              .toList(),
          item: (s) => Padding(
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
                      courseDateRange(plain(s['name'])),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                if (plain(s['summary']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
                    child: NiuWell(
                      padding: const EdgeInsets.all(NiuSpacing.lg),
                      child: SelectableText(plain(s['summary'])),
                    ),
                  ),
                if (objects(s['modules']).isNotEmpty)
                  NiuGroup(
                    children: [
                      for (final m in objects(s['modules']))
                        CourseResourceTile(
                          module: m,
                          onTap: () => pushMoodle(
                            context,
                            MoodleModuleScreen(
                              repository: repository,
                              module: m,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.assignment,
          emptyTitle: '沒有作業',
          emptyMessage: '老師指派的作業會依截止時間排在這裡。',
          load: loadAssignments,
          item: (a) => assignment(context, a),
        ),
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.forum,
          emptyTitle: '沒有討論區',
          emptyMessage: '課程開放的討論區會出現在這裡。',
          load: () => repository.forums(id),
          item: (f) => CourseDetailItem(
            title: plain(f['name']),
            excerpt: plain(f['intro']),
            onTap: () => pushMoodle(
              context,
              MoodleForumScreen(repository: repository, forum: f),
            ),
          ),
        ),
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.grades,
          emptyTitle: '還沒有成績',
          emptyMessage: '老師公布的評分項目會出現在這裡。',
          load: () => repository.grades(id),
          item: (g) => grade(context, g),
        ),
        (context) => AttendanceRecords(repository: repository, courseId: id),
      ],
    ),
  );
}

NiuTone submissionTone(Object? status) => switch (status) {
  'submitted' => NiuTone.success,
  'draft' => NiuTone.warning,
  'new' || 'reopened' => NiuTone.accent,
  _ => NiuTone.neutral,
};

String gradeValue(Object? value) {
  final text = plain(value).trim();
  return text.isEmpty || text == '-' || text == '—' ? '未提供' : text;
}

class _AttachmentButton extends StatelessWidget {
  const _AttachmentButton({required this.name, this.onPressed});
  final String name;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: NiuSpacing.sm),
    child: Material(
      color: NiuColors.of(context).fill,
      borderRadius: BorderRadius.circular(NiuRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(NiuRadius.md),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NiuSpacing.md,
              vertical: NiuSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  NiuIcons.attach,
                  size: 18,
                  color: NiuColors.of(context).accent,
                ),
                const SizedBox(width: NiuSpacing.sm),
                Expanded(
                  child: Text(
                    name.isEmpty ? '附件' : name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: NiuColors.of(context).accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class MoodleModuleScreen extends StatelessWidget {
  const MoodleModuleScreen({
    super.key,
    required this.repository,
    required this.module,
  });
  final MoodleRepository repository;
  final Json module;
  @override
  Widget build(BuildContext context) {
    final contents = objects(module['contents'] ?? []);
    final description = plain(module['description']);
    return NiuScrollPage(
      title: plain(module['name']),
      bottomBar: module['url'] is String
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(NiuSize.buttonHeight),
              ),
              icon: const Icon(NiuIcons.external, size: 18),
              onPressed: () => openMoodleUrl(
                context,
                repository,
                '${module['url']}',
                plain(module['name']),
              ),
              label: const Text('在 M 園區開啟'),
            )
          : null,
      children: [
        if (description.isNotEmpty) ...[
          NiuCard(child: SelectableText(description)),
          const SizedBox(height: NiuSpacing.lg),
        ],
        if (contents.isNotEmpty)
          NiuGroup(
            children: [
              for (final content in contents)
                NiuRow(
                  icon: content['type'] == 'url'
                      ? NiuIcons.link
                      : NiuIcons.file,
                  hue: content['type'] == 'url' ? NiuHue.cyan : NiuHue.blue,
                  title: plain(content['filename'] ?? '開啟資源'),
                  subtitle: content['filesize'] == null
                      ? null
                      : _fileSize(content['filesize']),
                  onTap: content['fileurl'] is String
                      ? () => openMoodleUrl(
                          context,
                          repository,
                          '${content['fileurl']}',
                          plain(module['name']),
                          file: content['type'] == 'file',
                        )
                      : null,
                ),
            ],
          ),
        if (contents.isEmpty && description.isEmpty)
          const NiuEmpty(
            icon: NiuIcons.file,
            title: '這裡沒有可預覽的內容',
            message: '點下方按鈕在 M 園區查看完整內容。',
          ),
      ],
    );
  }
}

String _fileSize(Object? raw) {
  final size = num.tryParse('$raw');
  if (size == null || size <= 0) return '';
  return size >= 1048576
      ? '${(size / 1048576).toStringAsFixed(1)} MB'
      : '${(size / 1024).ceil()} KB';
}

class MoodleForumScreen extends StatefulWidget {
  const MoodleForumScreen({
    super.key,
    required this.repository,
    required this.forum,
  });
  final MoodleRepository repository;
  final Json forum;
  @override
  State<MoodleForumScreen> createState() => _MoodleForumScreenState();
}

class _MoodleForumScreenState extends State<MoodleForumScreen> {
  int page = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: NiuAppBar(title: plain(widget.forum['name'])),
    body: CourseDetailList(
      emptyIcon: NiuIcons.forum,
      emptyTitle: '沒有討論主題',
      emptyMessage: '這個討論區還沒有主題，或這一頁已經沒有更多討論。',
      key: ValueKey(page),
      load: () =>
          widget.repository.discussions(number(widget.forum['id']), page: page),
      header: Padding(
        padding: const EdgeInsets.only(bottom: NiuSpacing.md),
        child: Row(
          children: [
            NiuIconButton(
              tooltip: '上一頁',
              icon: Icons.chevron_left_rounded,
              tonal: true,
              onPressed: page > 0 ? () => setState(() => page--) : null,
            ),
            Expanded(
              child: Text(
                '第 ${page + 1} 頁',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            NiuIconButton(
              tooltip: '下一頁',
              icon: Icons.chevron_right_rounded,
              tonal: true,
              onPressed: () => setState(() => page++),
            ),
          ],
        ),
      ),
      item: (d) => CourseDetailItem(
        title: plain(d['subject'] ?? d['name']),
        metadata:
            '${plain(d['userfullname']).isEmpty ? '作者未提供' : plain(d['userfullname'])} · ${campusTime(d['timemodified'])} · ${d['numreplies'] == null ? '回覆數未提供' : '${d['numreplies']} 則回覆'}',
        excerpt: plain(d['message']),
        onTap: () => pushMoodle(
          context,
          MoodleDiscussionScreen(repository: widget.repository, discussion: d),
        ),
      ),
    ),
  );
}

class MoodleDiscussionScreen extends StatelessWidget {
  const MoodleDiscussionScreen({
    super.key,
    required this.repository,
    required this.discussion,
  });
  final MoodleRepository repository;
  final Json discussion;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: NiuAppBar(
      title: plain(discussion['subject'] ?? discussion['name']),
    ),
    body: CourseDetailList(
      emptyIcon: NiuIcons.forum,
      emptyTitle: '沒有貼文',
      emptyMessage: '這個主題目前沒有可以顯示的內容。',
      load: () => repository.posts(
        number(discussion['discussion'] ?? discussion['id']),
      ),
      item: (p) {
        final theme = Theme.of(context);
        final author = plain(p['author'] is Map ? p['author']['fullname'] : '');
        return Padding(
          padding: const EdgeInsets.only(bottom: NiuSpacing.md),
          child: NiuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: NiuColors.of(context).accentSoft,
                      child: Text(
                        author.characters.firstOrNull ?? '?',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: NiuColors.of(context).accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            author.isEmpty ? '作者未提供' : author,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            campusTime(p['timecreated']),
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NiuSpacing.md),
                if (plain(p['subject']).isNotEmpty) ...[
                  Text(plain(p['subject']), style: theme.textTheme.titleMedium),
                  const SizedBox(height: NiuSpacing.xs),
                ],
                SelectableText(plain(p['message'])),
                for (final f in objects(p['attachments'] ?? []))
                  _AttachmentButton(
                    name: plain(f['filename']),
                    onPressed: () => openMoodleUrl(
                      context,
                      repository,
                      '${f['fileurl']}',
                      plain(f['filename']),
                      file: true,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class MoodleAssignmentScreen extends StatefulWidget {
  const MoodleAssignmentScreen({
    super.key,
    required this.repository,
    required this.assignment,
  });
  final MoodleRepository repository;
  final Json assignment;
  @override
  State<MoodleAssignmentScreen> createState() => _MoodleAssignmentScreenState();
}

class _MoodleAssignmentScreenState extends State<MoodleAssignmentScreen> {
  int get id => number(widget.assignment['id']);
  late Future<Json> future = widget.repository.submission(id);
  bool busy = false;
  bool accept = false;
  String? message;
  bool messageFailed = false;
  Future<void> mutate(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() {
          message = '完成，已重新讀取最新狀態。';
          messageFailed = false;
          future = widget.repository.submission(id);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          message = 'M 園區沒有確認這次操作，App 不會自動重送。請先重新整理狀態再決定下一步。';
          messageFailed = true;
          future = widget.repository.submission(id);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String text, String action) =>
      confirmNiuAction(
        context,
        title: title,
        message: text,
        confirmLabel: action,
      );
  Future<void> upload() async {
    final result = await openFiles();
    if (!mounted || result.isEmpty) return;
    final files = <({String name, List<int> bytes})>[];
    try {
      for (final file in result) {
        files.add((name: file.name, bytes: await file.readAsBytes()));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          message = '讀不到選取的檔案，請重新選擇。';
          messageFailed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    if (files.any((f) => f.bytes.isEmpty)) {
      setState(() {
        message = '讀不到選取的檔案，請重新選擇。';
        messageFailed = true;
      });
      return;
    }
    if (!await confirm('更新作業檔案？', '這 ${files.length} 個檔案會取代目前儲存的作業檔案。', '上傳')) {
      return;
    }
    await mutate(() => widget.repository.uploadFiles(id, files));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intro = plain(widget.assignment['intro']);
    return Scaffold(
      appBar: NiuAppBar(
        title: '作業',
        actions: [
          NiuIconButton(
            tooltip: '重新整理',
            icon: NiuIcons.refresh,
            onPressed: busy
                ? null
                : () =>
                      setState(() => future = widget.repository.submission(id)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          NiuSpacing.gutter,
          NiuSpacing.md,
          NiuSpacing.gutter,
          NiuSpacing.huge,
        ),
        children: [
          Text(
            plain(widget.assignment['name']),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: NiuSpacing.sm),
          Row(
            children: [
              Icon(
                NiuIcons.time,
                size: 16,
                color: NiuColors.of(context).inkSecondary,
              ),
              const SizedBox(width: NiuSpacing.xs),
              Text(
                '截止 ${campusTime(widget.assignment['duedate'])}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (intro.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.lg),
            NiuCard(child: SelectableText(intro)),
          ],
          if (message != null) ...[
            const SizedBox(height: NiuSpacing.lg),
            NiuBanner(
              tone: messageFailed ? NiuTone.warning : NiuTone.success,
              message: message!,
            ),
          ],
          if (busy) ...[
            const SizedBox(height: NiuSpacing.lg),
            const LinearProgressIndicator(),
          ],
          FutureBuilder<Json>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.only(top: NiuSpacing.lg),
                  child: NiuBanner(
                    tone: NiuTone.warning,
                    message: '讀不到繳交狀態。重新整理，或在 M 園區網頁查看。',
                  ),
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const NiuLoading(message: '正在讀取繳交狀態', compact: true);
              }
              final attempt = snapshot.data!['lastattempt'] is Map
                  ? object(snapshot.data!['lastattempt'])
                  : <String, dynamic>{};
              final submission = attempt['submission'] is Map
                  ? object(attempt['submission'])
                  : <String, dynamic>{};
              final status = '${submission['status'] ?? ''}';
              final canEdit =
                  attempt['canedit'] != false && status != 'submitted';
              final feedback = snapshot.data!['feedback'];
              final files = [
                for (final plugin in objects(submission['plugins'] ?? []))
                  for (final area in objects(plugin['fileareas'] ?? []))
                    ...objects(area['files'] ?? []),
              ];
              final texts = [
                for (final plugin in objects(submission['plugins'] ?? []))
                  for (final field in objects(plugin['editorfields'] ?? []))
                    plain(field['text']),
              ].where((t) => t.trim().isNotEmpty).toList();
              return NiuSection(
                title: '繳交狀態',
                action: NiuBadge(
                  label: submissionLabel(status.isEmpty ? null : status),
                  tone: submissionTone(status.isEmpty ? null : status),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NiuCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NiuKeyValue(
                            label: '繳交狀態',
                            value: submissionLabel(
                              status.isEmpty ? null : status,
                            ),
                          ),
                          NiuKeyValue(
                            label: '最後修改',
                            value: campusTime(submission['timemodified']),
                          ),
                          NiuKeyValue(
                            label: '評分',
                            value: switch (attempt['graded']) {
                              true => '已評分',
                              false => '尚未評分',
                              _ => '未提供',
                            },
                          ),
                          if (feedback is Map &&
                              feedback['gradefordisplay'] != null)
                            NiuKeyValue(
                              label: '成績',
                              value: plain(feedback['gradefordisplay']),
                              emphasis: true,
                            ),
                          for (final file in files)
                            _AttachmentButton(
                              name: plain(file['filename']),
                              onPressed: file['fileurl'] is String
                                  ? () => openMoodleUrl(
                                      context,
                                      widget.repository,
                                      '${file['fileurl']}',
                                      plain(file['filename']),
                                      file: true,
                                    )
                                  : null,
                            ),
                          for (final text in texts) ...[
                            const SizedBox(height: NiuSpacing.sm),
                            NiuWell(child: SelectableText(text)),
                          ],
                        ],
                      ),
                    ),
                    if (canEdit) ...[
                      const SizedBox(height: NiuSpacing.lg),
                      FilledButton.icon(
                        onPressed: busy ? null : upload,
                        icon: const Icon(NiuIcons.upload),
                        label: const Text('選擇檔案並存成草稿'),
                      ),
                      const SizedBox(height: NiuSpacing.xs),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: NiuColors.of(context).error,
                        ),
                        onPressed: busy
                            ? null
                            : () async {
                                if (await confirm(
                                  '清除作業檔案？',
                                  '目前儲存的作業檔案會被移除。',
                                  '清除',
                                )) {
                                  await mutate(
                                    () => widget.repository.clear(id),
                                  );
                                }
                              },
                        child: const Text('清除已儲存的檔案'),
                      ),
                      if (status == 'draft') ...[
                        const SizedBox(height: NiuSpacing.lg),
                        NiuCard(
                          padding: EdgeInsets.zero,
                          child: CheckboxListTile(
                            value: accept,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: busy
                                ? null
                                : (v) => setState(() => accept = v ?? false),
                            title: Text(
                              '這是我自己完成的作業，我同意學校的繳交聲明。',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        const SizedBox(height: NiuSpacing.md),
                        FilledButton(
                          onPressed: busy || !accept
                              ? null
                              : () async {
                                  if (await confirm(
                                    '正式繳交？',
                                    '送出後可能無法再修改，作業會交給老師評分。',
                                    '繳交',
                                  )) {
                                    await mutate(
                                      () => widget.repository.submit(
                                        id,
                                        acceptStatement: accept,
                                      ),
                                    );
                                  }
                                },
                          child: const Text('正式繳交'),
                        ),
                      ],
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: NiuSpacing.xl),
          OutlinedButton.icon(
            icon: const Icon(NiuIcons.external, size: 18),
            onPressed: () => openMoodleUrl(
              context,
              widget.repository,
              'https://euni.niu.edu.tw/mod/assign/view.php?id=${widget.assignment['cmid']}',
              '作業',
            ),
            label: const Text('在 M 園區網頁開啟'),
          ),
          const SizedBox(height: NiuSpacing.sm),
          Text(
            '線上文字、繳交聲明與完整回饋，請在網頁查看。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
