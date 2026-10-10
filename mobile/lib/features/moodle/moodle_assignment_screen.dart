import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'course_detail_presentation.dart';
import 'moodle_repository.dart';
import 'moodle_links.dart';

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
        padding: NiuLayout.page(
          context,
          top: NiuSpacing.md,
          bottom: NiuSpacing.huge,
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
                            MoodleAttachmentButton(
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
