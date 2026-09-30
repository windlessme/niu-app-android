import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/shared.dart';
import '../../shared/app_fact.dart';
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
Widget moodleCard(Widget child) => Card(
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(NiuRadius.card),
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);

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
        setState(() => error = '目前無法恢復 M 園區登入，請檢查網路後重試，或開啟校方登入頁。');
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
    return Scaffold(
      appBar: AppBar(title: const Text('M 園區')),
      body: ListView(
        padding: const EdgeInsets.all(NiuSpacing.xxl),
        children: [
          const Icon(Icons.school_outlined, size: 64),
          const SizedBox(height: NiuSpacing.xxl),
          moodleCard(
            Padding(
              padding: const EdgeInsets.all(NiuSpacing.xl),
              child: Column(
                children: [
                  const Text('使用校方登入頁輸入一次帳號密碼，即可連接 M 園區。校方要求的驗證仍需在頁面完成。'),
                  const SizedBox(height: NiuSpacing.xl),
                  if (error != null) Text(error!),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                            if (mounted) await restoreOrLogin();
                          },
                    child: Text(busy ? '恢復登入中…' : '開啟校方登入頁'),
                  ),
                  TextButton(
                    onPressed: busy ? null : restoreOrLogin,
                    child: const Text('重試恢復登入'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
      if (snapshot.hasError && retained == null) {
        return ListView(
          padding: const EdgeInsets.all(NiuSpacing.lg),
          children: [
            if (widget.header != null) widget.header!,
            const Text('無法讀取校方資料，請檢查連線或重新登入。'),
            TextButton(onPressed: reload, child: const Text('重新讀取')),
          ],
        );
      }
      if (retained == null) {
        return ListView(
          padding: const EdgeInsets.all(NiuSpacing.lg),
          children: [
            if (widget.header != null) widget.header!,
            const AppLoadingState(message: '正在讀取課程資料…'),
          ],
        );
      }
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(NiuSpacing.lg),
          itemCount: retained!.length + 1,
          itemBuilder: (context, index) => index == 0
              ? Column(
                  children: [
                    if (widget.header != null) widget.header!,
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: NiuSpacing.md),
                        child: Text('正在更新，顯示上次資料…'),
                      ),
                    if (snapshot.hasError)
                      TextButton(
                        onPressed: refreshing ? null : reload,
                        child: const Text('更新失敗，顯示上次資料。點此重試'),
                      ),
                    if (retained!.isEmpty)
                      const NiuEmptyState(
                        title: '目前沒有資料',
                        message: '校方提供的資料會顯示在這裡。',
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: IosPageHeader(
      title: 'M 園區',
      actions: [
        CircleIconButton(
          tooltip: '點名掃描',
          onPressed: () => pushMoodle(
            context,
            AttendanceScannerScreen(repository: widget.repository),
          ),
          icon: Icons.qr_code_scanner,
        ),
        CircleIconButton(
          tooltip: '通知',
          onPressed: () => pushMoodle(
            context,
            Scaffold(
              appBar: AppBar(title: const Text('M 園區通知')),
              body: MoodleList(
                load: widget.repository.notifications,
                item: (n) => moodleCard(
                  ListTile(
                    title: Text(plain(n['subject'])),
                    subtitle: Text(
                      plain(
                        n['fullmessagehtml'] ??
                            n['fullmessage'] ??
                            n['smallmessage'],
                      ),
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
            ),
          ),
          icon: Icons.notifications_outlined,
        ),
      ],
    ),
    body: FutureBuilder<List<Json>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData &&
            !identical(retained, snapshot.data)) {
          retained = snapshot.data;
          presented = retained!.map(CoursePresentation.new).toList();
          if (semester != null &&
              !presented.any((c) => c.semester == semester)) {
            semester = null;
          }
        }
        if (snapshot.hasError && retained == null) {
          return AppErrorState(
            title: '資料更新失敗',
            message: '請檢查連線後重新整理。',
            onRetry: reload,
          );
        }
        if (retained == null) {
          return const AppLoadingState(message: '正在讀取我的課程…');
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
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(NiuSpacing.xl),
            itemCount: courses.length + 1,
            itemBuilder: (context, index) {
              if (index > 0) {
                final course = courses[index - 1];
                return MoodleCourseCard(
                  course: course,
                  onTap: () => pushMoodle(
                    context,
                    MoodleCourseScreen(
                      repository: widget.repository,
                      course: course.source,
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(NiuSpacing.xxl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 36,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: NiuSpacing.xl),
                          Text(
                            '我的課程',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: NiuSpacing.sm),
                          Text('${courses.length} 門課程 · 下拉更新'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: NiuSpacing.lg),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.only(bottom: NiuSpacing.md),
                      child: Text('正在更新，顯示上次課程…'),
                    ),
                  if (snapshot.hasError)
                    TextButton(
                      onPressed: refreshing ? null : reload,
                      child: const Text('更新失敗，保留上次資料。點此重試'),
                    ),
                  AppSearchField(
                    controller: search,
                    hint: '搜尋課程',
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: NiuSpacing.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('全部學期'),
                          selected: semester == null,
                          onSelected: (_) => setState(() => semester = null),
                        ),
                        for (final t in terms)
                          Padding(
                            padding: const EdgeInsets.only(left: NiuSpacing.sm),
                            child: ChoiceChip(
                              label: Text(
                                t.length == 4
                                    ? '${t.substring(0, 3)}-${t[3]}'
                                    : t,
                              ),
                              selected: semester == t,
                              onSelected: (_) => setState(() => semester = t),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NiuSpacing.lg),
                  if (courses.isEmpty)
                    const NiuEmptyState(
                      title: '沒有符合的課程',
                      message: '試試其他關鍵字或學期。',
                    ),
                ],
              );
            },
          ),
        );
      },
    ),
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
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('確認開啟點名'),
            content: const Text('開啟校方頁面可能立即記錄出席，是否繼續？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('開啟並點名'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟此連結')));
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
        TextButton.icon(
          onPressed: file['fileurl'] is String
              ? () => openMoodleUrl(
                  context,
                  repository,
                  file['fileurl'],
                  plain(file['filename']),
                  file: true,
                )
              : null,
          icon: const Icon(Icons.attach_file, size: 18),
          label: Text(plain(file['filename'])),
        ),
    ],
    onTap: () => pushMoodle(
      context,
      MoodleDiscussionScreen(repository: repository, discussion: d),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('課程詳情')),
    body: CourseDetailTabs(
      builders: [
        (context) => CourseDetailList(
          emptyTitle: '目前沒有課程公告',
          emptyMessage: '老師發布的最新消息會顯示在這裡。',
          header: MoodleCourseInformation(course: CoursePresentation(course)),
          load: () => repository.announcements(id),
          item: (d) => discussion(context, d),
        ),
        (context) => CourseDetailList(
          emptyTitle: '尚無教材',
          emptyMessage: '老師上傳的教材與課程資源會顯示在這裡。',
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
                  padding: const EdgeInsets.symmetric(vertical: NiuSpacing.md),
                  child: Text(
                    courseDateRange(plain(s['name'])),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (plain(s['summary']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(NiuSpacing.lg),
                    child: SelectableText(plain(s['summary'])),
                  ),
                for (final m in objects(s['modules']))
                  CourseResourceTile(
                    module: m,
                    onTap: () => pushMoodle(
                      context,
                      MoodleModuleScreen(repository: repository, module: m),
                    ),
                  ),
              ],
            ),
          ),
        ),
        (context) => CourseDetailList(
          emptyTitle: '目前沒有作業',
          emptyMessage: '老師指派的作業會依截止時間排列在這裡。',
          load: loadAssignments,
          item: (a) => CourseDetailItem(
            title: plain(a['name']),
            metadata: '截止：${campusTime(a['duedate'])}',
            excerpt: submissionLabel(
              a['submissionstatus'] ??
                  (a['submission'] is Map ? a['submission']['status'] : null),
            ),
            children: [
              if (a['graded'] is bool)
                Text(a['graded'] == true ? '已評分' : '尚未評分'),
            ],
            onTap: () => pushMoodle(
              context,
              MoodleAssignmentScreen(repository: repository, assignment: a),
            ),
          ),
        ),
        (context) => CourseDetailList(
          emptyTitle: '尚無討論區',
          emptyMessage: '課程開放的討論區會顯示在這裡。',
          load: () => repository.forums(id),
          item: (f) => moodleCard(
            ListTile(
              title: Text(plain(f['name'])),
              subtitle: Text(plain(f['intro'])),
              onTap: () => pushMoodle(
                context,
                MoodleForumScreen(repository: repository, forum: f),
              ),
            ),
          ),
        ),
        (context) => CourseDetailList(
          emptyTitle: '尚無成績項目',
          emptyMessage: '老師公布的評分項目與成績會顯示在這裡。',
          load: () => repository.grades(id),
          item: (g) => CourseDetailItem(
            title: plain(g['itemname']).isEmpty
                ? '課程總成績'
                : plain(g['itemname']),
            children: [
              const SizedBox(height: NiuSpacing.md),
              Text(
                '成績：${gradeValue(g['gradeformatted']) == '未提供' ? '尚未公布' : gradeValue(g['gradeformatted'])}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              AppFact(label: '範圍', value: gradeValue(g['rangeformatted'])),
              AppFact(
                label: '百分比',
                value: gradeValue(g['percentageformatted']),
              ),
              AppFact(label: '權重', value: gradeValue(g['weightformatted'])),
              if (plain(g['feedback']).isNotEmpty) ...[
                const SizedBox(height: NiuSpacing.md),
                Text('老師回饋', style: Theme.of(context).textTheme.titleSmall),
                SelectableText(plain(g['feedback'])),
              ],
            ],
          ),
        ),
        (context) => AttendanceRecords(repository: repository, courseId: id),
      ],
    ),
  );
}

String gradeValue(Object? value) {
  final text = plain(value).trim();
  return text.isEmpty || text == '-' || text == '—' ? '未提供' : text;
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(plain(module['name']))),
    body: ListView(
      padding: const EdgeInsets.all(NiuSpacing.page),
      children: [
        SelectableText(plain(module['description'])),
        for (final content in objects(module['contents'] ?? []))
          moodleCard(
            ListTile(
              title: Text(plain(content['filename'] ?? '開啟資源')),
              subtitle: Text(
                content['filesize'] == null
                    ? ''
                    : '${content['filesize']} bytes',
              ),
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
          ),
        if (module['url'] is String)
          FilledButton(
            onPressed: () => openMoodleUrl(
              context,
              repository,
              '${module['url']}',
              plain(module['name']),
            ),
            child: const Text('在 M 園區開啟完整內容'),
          ),
      ],
    ),
  );
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
    appBar: AppBar(title: Text(plain(widget.forum['name']))),
    body: CourseDetailList(
      emptyTitle: '目前沒有討論主題',
      emptyMessage: '這個討論區尚未有主題，或這一頁已沒有更多討論。',
      key: ValueKey(page),
      load: () =>
          widget.repository.discussions(number(widget.forum['id']), page: page),
      header: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: page > 0 ? () => setState(() => page--) : null,
            child: const Text('上一頁'),
          ),
          Text('第 ${page + 1} 頁'),
          TextButton(
            onPressed: () => setState(() => page++),
            child: const Text('下一頁'),
          ),
        ],
      ),
      item: (d) => CourseDetailItem(
        title: plain(d['subject'] ?? d['name']),
        metadata:
            '${plain(d['userfullname']).isEmpty ? '作者未提供' : plain(d['userfullname'])} · ${campusTime(d['timemodified'])}\n${d['numreplies'] == null ? '回覆數未提供' : '${d['numreplies']} 則回覆'}',
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
    appBar: AppBar(
      title: Text(plain(discussion['subject'] ?? discussion['name'])),
    ),
    body: CourseDetailList(
      emptyTitle: '尚無討論內容',
      emptyMessage: '這個主題目前沒有可顯示的貼文。',
      load: () => repository.posts(
        number(discussion['discussion'] ?? discussion['id']),
      ),
      item: (p) => moodleCard(
        Padding(
          padding: const EdgeInsets.all(NiuSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plain(p['subject']),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${plain(p['author'] is Map ? p['author']['fullname'] : '')}　${campusTime(p['timecreated'])}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Divider(),
              SelectableText(plain(p['message'])),
              for (final f in objects(p['attachments'] ?? []))
                TextButton(
                  onPressed: () => openMoodleUrl(
                    context,
                    repository,
                    '${f['fileurl']}',
                    plain(f['filename']),
                    file: true,
                  ),
                  child: Text(plain(f['filename'])),
                ),
            ],
          ),
        ),
      ),
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
          message = '操作完成，已重新讀取校方狀態。';
          future = widget.repository.submission(id);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          message = '校方未確認操作完成，未自動重送。請先重新整理狀態再決定下一步。';
          future = widget.repository.submission(id);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確定'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> upload() async {
    final result = await openFiles();
    if (!mounted || result.isEmpty) return;
    final files = <({String name, List<int> bytes})>[];
    try {
      for (final file in result) {
        files.add((name: file.name, bytes: await file.readAsBytes()));
      }
    } catch (_) {
      if (mounted) setState(() => message = '無法讀取選取的檔案，請重新選擇。');
      return;
    }
    if (!mounted) return;
    if (files.any((f) => f.bytes.isEmpty)) {
      setState(() => message = '無法讀取選取的檔案，請重新選擇。');
      return;
    }
    if (!await confirm('更新作業檔案', '本次選取的 ${files.length} 個檔案會取代目前的作業檔案。')) {
      return;
    }
    await mutate(() => widget.repository.uploadFiles(id, files));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(plain(widget.assignment['name'])),
      actions: [
        IconButton(
          tooltip: '重新整理',
          onPressed: busy
              ? null
              : () => setState(() => future = widget.repository.submission(id)),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(NiuSpacing.xl),
      children: [
        AppFact(label: '截止時間', value: campusTime(widget.assignment['duedate'])),
        const SizedBox(height: NiuSpacing.lg),
        SelectableText(plain(widget.assignment['intro'])),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NiuSpacing.lg),
            child: Text(message!),
          ),
        if (busy) const LinearProgressIndicator(),
        FutureBuilder<Json>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(NiuSpacing.lg),
                child: Text('無法取得繳交狀態，請重新整理或開啟校方頁面。'),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: AppLoadingState());
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                moodleCard(
                  Padding(
                    padding: const EdgeInsets.all(NiuSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '繳交狀態：${submissionLabel(status)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: NiuSpacing.sm),
                        Text(
                          '最後修改：${campusTime(submission['timemodified'])}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Text(
                          '評分：${switch (attempt['graded']) {
                            true => '已評分',
                            false => '尚未評分',
                            _ => '未提供',
                          }}',
                        ),
                        if (feedback is Map &&
                            feedback['gradefordisplay'] != null)
                          Text('成績：${plain(feedback['gradefordisplay'])}'),
                        for (final plugin in objects(
                          submission['plugins'] ?? [],
                        )) ...[
                          for (final area in objects(plugin['fileareas'] ?? []))
                            for (final file in objects(area['files'] ?? []))
                              TextButton(
                                onPressed: file['fileurl'] is String
                                    ? () => openMoodleUrl(
                                        context,
                                        widget.repository,
                                        '${file['fileurl']}',
                                        plain(file['filename']),
                                        file: true,
                                      )
                                    : null,
                                child: Text(plain(file['filename'])),
                              ),
                          for (final field in objects(
                            plugin['editorfields'] ?? [],
                          ))
                            SelectableText(plain(field['text'])),
                        ],
                      ],
                    ),
                  ),
                ),
                if (canEdit) ...[
                  FilledButton.icon(
                    onPressed: busy ? null : upload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('選擇檔案並儲存草稿'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (await confirm('清除作業檔案', '確定要清除目前儲存的作業檔案嗎？')) {
                              await mutate(() => widget.repository.clear(id));
                            }
                          },
                    child: const Text('清除已儲存檔案'),
                  ),
                  if (status == 'draft') ...[
                    CheckboxListTile(
                      value: accept,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => accept = v ?? false),
                      title: const Text('我確認這是自己的作業，並同意校方的繳交聲明。'),
                    ),
                    FilledButton(
                      onPressed: busy || !accept
                          ? null
                          : () async {
                              if (await confirm(
                                '正式繳交',
                                '送出後可能無法再次修改，確定繳交給老師評分嗎？',
                              )) {
                                await mutate(
                                  () => widget.repository.submit(
                                    id,
                                    acceptStatement: accept,
                                  ),
                                );
                              }
                            },
                      child: const Text('正式繳交給老師評分'),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
        TextButton(
          onPressed: () => openMoodleUrl(
            context,
            widget.repository,
            'https://euni.niu.edu.tw/mod/assign/view.php?id=${widget.assignment['cmid']}',
            '校方作業頁面',
          ),
          child: const Text('開啟校方作業頁面（線上文字、聲明與完整回饋）'),
        ),
      ],
    ),
  );
}
