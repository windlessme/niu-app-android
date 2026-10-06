import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import '../attendance/attendance_screen.dart';
import 'moodle_assignment_screen.dart';
import 'moodle_attachment_screen.dart';
import 'moodle_forum_screen.dart';
import 'moodle_links.dart';
import 'moodle_module_screen.dart';
import 'moodle_page_screen.dart';
import 'moodle_repository.dart';

/// Opens a course material where its content is, as the iOS app does: page
/// text in the app, forums as discussions, a single file straight to its
/// preview. Anything else lists what the module holds.
void openMoodleModule(
  BuildContext context,
  MoodleRepository repository,
  int courseId,
  Json module,
) {
  final name = plain(module['name']);
  final files = [
    for (final content in objects(module['contents'] ?? []))
      if (content['fileurl'] is String) content,
  ];
  final instance = int.tryParse('${module['instance']}');
  switch ('${module['modname']}') {
    case 'page':
      return pushMoodle(
        context,
        MoodlePageScreen(
          repository: repository,
          courseId: courseId,
          module: module,
        ),
      );
    case 'forum' when instance != null:
      return pushMoodle(
        context,
        MoodleForumScreen(
          repository: repository,
          forum: {'id': instance, 'name': name},
        ),
      );
    case 'assign':
      return pushMoodle(
        context,
        _AssignmentLoader(
          repository: repository,
          courseId: courseId,
          module: module,
        ),
      );
    case 'attendance':
      return pushMoodle(
        context,
        Scaffold(
          appBar: NiuAppBar(title: name),
          body: AttendanceRecords(repository: repository, courseId: courseId),
        ),
      );
    case 'url' when files.length == 1:
      openMoodleUrl(context, repository, '${files.single['fileurl']}', name);
      return;
    case 'resource' when files.length == 1:
      return pushMoodle(
        context,
        MoodleAttachmentScreen(
          repository: repository,
          url: '${files.single['fileurl']}',
          name: plain(files.single['filename'] ?? name),
        ),
      );
  }
  pushMoodle(
    context,
    MoodleModuleScreen(repository: repository, module: module),
  );
}

/// Finds the assignment behind a course-page link, then shows it.
class _AssignmentLoader extends StatefulWidget {
  const _AssignmentLoader({
    required this.repository,
    required this.courseId,
    required this.module,
  });
  final MoodleRepository repository;
  final int courseId;
  final Json module;
  @override
  State<_AssignmentLoader> createState() => _AssignmentLoaderState();
}

class _AssignmentLoaderState extends State<_AssignmentLoader> {
  late Future<Json> future = find();

  Future<Json> find() async {
    final assignments = await widget.repository.assignments(widget.courseId);
    for (final test in <bool Function(Json)>[
      (a) => '${a['cmid']}' == '${widget.module['id']}',
      (a) => '${a['id']}' == '${widget.module['instance']}',
    ]) {
      final match = assignments.where(test).firstOrNull;
      if (match != null) return match;
    }
    throw const FormatException('找不到這份作業');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return MoodleAssignmentScreen(
          repository: widget.repository,
          assignment: snapshot.data!,
        );
      }
      return Scaffold(
        appBar: NiuAppBar(title: plain(widget.module['name'])),
        body: Center(
          child: snapshot.hasError
              ? SingleChildScrollView(
                  child: NiuError(
                    title: '無法開啟這份作業',
                    message: '這份作業可能已被移除或尚未開放。',
                    onRetry: () => setState(() => future = find()),
                  ),
                )
              : const NiuLoading(message: '正在讀取作業'),
        ),
      );
    },
  );
}
