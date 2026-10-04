import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/shared.dart';
import 'course_presentation.dart';
import 'course_widgets.dart';
import 'course_detail_widgets.dart';
import '../attendance/attendance_screen.dart';
import 'moodle_repository.dart';
import 'moodle_links.dart';
import 'moodle_course_screen.dart';

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
