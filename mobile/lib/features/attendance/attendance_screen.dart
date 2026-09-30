import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../shared/shared.dart';
import '../moodle/moodle_repository.dart';
import '../moodle/moodle_web_screen.dart';
import 'attendance_repository.dart';
import 'attendance_open_flow.dart';

class AttendanceScannerScreen extends StatefulWidget {
  const AttendanceScannerScreen({super.key, required this.repository});
  final MoodleRepository repository;
  @override
  State<AttendanceScannerScreen> createState() =>
      _AttendanceScannerScreenState();
}

class _AttendanceScannerScreenState extends State<AttendanceScannerScreen>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    autoStart: false,
  );
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final flow = AttendanceOpenFlow();
  bool active = true;
  Future<void> cameraTask = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    inputFocus.addListener(() => camera(!inputFocus.hasFocus));
    WidgetsBinding.instance.addPostFrameCallback((_) => camera(true));
  }

  Future<void> camera(bool start) {
    cameraTask = cameraTask
        .catchError((Object _) {})
        .then((_) async {
          if (!mounted) return;
          if (start && active && !flow.busy && !inputFocus.hasFocus) {
            await controller.start();
          } else {
            await controller.stop();
          }
        })
        .catchError((Object _) {
          if (mounted) setState(() => error = '相機沒有啟動。請確認相機權限，或改用貼上網址。');
        });
    return cameraTask;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    camera(active);
  }

  String? error;
  Future<void> open(String raw) async {
    if (!active || flow.busy) return;
    setState(() => error = null);
    FocusScope.of(context).unfocus();
    try {
      await flow.open(
        raw,
        pause: () => camera(false),
        confirm: (uri) async {
          if (!mounted || !active) return false;
          return confirmNiuAction(
            context,
            title: '要開啟點名嗎？',
            message:
                '即將開啟 M 園區第 ${uri.queryParameters['sessid']} 次點名，開啟後可能會直接記錄出席。',
            confirmLabel: '開啟並點名',
          );
        },
        navigate: (uri) async {
          if (!mounted || !active) return;
          widget.repository.requireCurrent();
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MoodleWebScreen(
                repository: widget.repository,
                target: uri,
                title: '點名',
                attendance: true,
              ),
            ),
          );
        },
        resume: () => camera(true),
      );
    } catch (_) {
      if (mounted) setState(() => error = '無法開啟點名。請確認已登入 M 園區，並重新掃描 QR Code。');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraTask.whenComplete(controller.dispose);
    input.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const NiuAppBar(title: '點名'),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.gutter,
            NiuSpacing.sm,
            NiuSpacing.gutter,
            NiuSpacing.huge,
          ),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(NiuRadius.xxl),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .42,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: MobileScanner(
                        controller: controller,
                        onDetect: (capture) {
                          for (final b in capture.barcodes) {
                            if (b.rawValue != null) {
                              open(b.rawValue!);
                              break;
                            }
                          }
                        },
                        errorBuilder: (_, error) => const _CameraUnavailable(),
                      ),
                    ),
                    const IgnorePointer(child: _Viewfinder()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NiuSpacing.lg),
            Text(
              '把老師投影的 QR Code 放進框內，會自動開啟點名。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (error != null) ...[
              const SizedBox(height: NiuSpacing.lg),
              NiuBanner(tone: NiuTone.error, message: error!),
            ],
            NiuSection(
              title: '沒辦法掃描？',
              subtitle: '貼上老師提供的點名網址',
              child: NiuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: input,
                      focusNode: inputFocus,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      autocorrect: false,
                      onSubmitted: open,
                      decoration: const InputDecoration(
                        hintText: 'https://euni.niu.edu.tw/…',
                        prefixIcon: Icon(NiuIcons.link),
                      ),
                    ),
                    const SizedBox(height: NiuSpacing.md),
                    FilledButton(
                      onPressed: () => open(input.text),
                      child: const Text('開啟點名'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(NiuSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white70,
            size: 36,
          ),
          const SizedBox(height: NiuSpacing.md),
          Text(
            '無法使用相機',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: NiuSpacing.xs),
          Text(
            '請到系統設定允許相機權限，或在下方貼上點名網址。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

/// Corner brackets marking the scan area.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();
  @override
  Widget build(BuildContext context) => Center(
    child: FractionallySizedBox(
      widthFactor: .62,
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(painter: _BracketPainter()),
      ),
    ),
  );
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final l = size.width * .18;
    const r = 18.0;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, l)
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
      ..lineTo(l, 0)
      ..moveTo(w - l, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
      ..lineTo(w, l)
      ..moveTo(w, h - l)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r))
      ..lineTo(w - l, h)
      ..moveTo(l, h)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r))
      ..lineTo(0, h - l);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AttendanceRecords extends StatefulWidget {
  const AttendanceRecords({
    super.key,
    required this.repository,
    required this.courseId,
  });
  final MoodleRepository repository;
  final int courseId;
  @override
  State<AttendanceRecords> createState() => _AttendanceRecordsState();
}

class _AttendanceRecordsState extends State<AttendanceRecords> {
  Future<List<AttendanceSection>> load() => AttendanceRepository(
    widget.repository,
  ).course(widget.courseId).timeout(const Duration(seconds: 45));
  late Future<List<AttendanceSection>> future = load();
  Future<void> retry() async {
    setState(() => future = load());
    try {
      await future;
    } catch (_) {
      // The builder displays the retry state.
    }
  }

  @override
  void didUpdateWidget(covariant AttendanceRecords oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.courseId != widget.courseId) {
      future = load();
    }
  }

  NiuTone statusTone(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => NiuTone.success,
    AttendanceStatus.late => NiuTone.warning,
    AttendanceStatus.absent => NiuTone.error,
    AttendanceStatus.leave => NiuTone.accent,
    AttendanceStatus.pending => NiuTone.neutral,
  };
  String statusText(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => '出席',
    AttendanceStatus.late => '遲到',
    AttendanceStatus.absent => '缺席',
    AttendanceStatus.leave => '請假',
    AttendanceStatus.pending => '尚未點名',
  };

  Future<void> openSchoolRecords(AttendanceSection section) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MoodleWebScreen(
          repository: widget.repository,
          target: Uri.https('euni.niu.edu.tw', '/mod/attendance/view.php', {
            'id': '${section.moduleId}',
            'view': '5',
          }),
          title: '出席紀錄',
        ),
      ),
    );
    if (mounted) await retry();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AttendanceSection>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: SingleChildScrollView(
            child: NiuError(
              title: '無法讀取點名紀錄',
              message: '檢查網路連線後再試一次。',
              onRetry: retry,
            ),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: NiuLoading(message: '正在讀取點名紀錄'));
      }
      final theme = Theme.of(context);
      return RefreshIndicator(
        onRefresh: retry,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.gutter,
            NiuSpacing.lg,
            NiuSpacing.gutter,
            NiuSpacing.huge,
          ),
          children: [
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AttendanceScannerScreen(repository: widget.repository),
                ),
              ),
              icon: const Icon(NiuIcons.attendance),
              label: const Text('掃描點名'),
            ),
            if (snapshot.data!.isEmpty)
              const NiuEmpty(
                icon: NiuIcons.attendance,
                title: '沒有點名活動',
                message: '這門課尚未提供點名活動。',
              ),
            for (final section in snapshot.data!)
              Padding(
                padding: const EdgeInsets.only(top: NiuSpacing.lg),
                child: NiuCard(
                  padding: const EdgeInsets.fromLTRB(
                    NiuSpacing.lg,
                    NiuSpacing.lg,
                    NiuSpacing.lg,
                    NiuSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(section.name, style: theme.textTheme.titleMedium),
                      if (section.records.isNotEmpty) ...[
                        const SizedBox(height: NiuSpacing.md),
                        Wrap(
                          spacing: NiuSpacing.sm,
                          runSpacing: NiuSpacing.sm,
                          children: [
                            for (final status in AttendanceStatus.values)
                              NiuBadge(
                                label:
                                    '${statusText(status)} ${section.records.where((r) => r.status == status).length}',
                                tone: statusTone(status),
                              ),
                          ],
                        ),
                      ],
                      if (section.error != null) ...[
                        const SizedBox(height: NiuSpacing.md),
                        NiuBanner(
                          tone: NiuTone.error,
                          message: section.error!,
                          actionLabel: '再試一次',
                          onAction: retry,
                        ),
                      ] else if (section.records.isEmpty) ...[
                        const SizedBox(height: NiuSpacing.sm),
                        Text(
                          '這個點名活動還沒有上課紀錄。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ] else if (section.pending == section.records.length) ...[
                        const SizedBox(height: NiuSpacing.md),
                        Text(
                          '所有時段都還沒點名，可以到學校網頁確認完整紀錄。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (section.records.isNotEmpty)
                        const SizedBox(height: NiuSpacing.sm),
                      for (final (i, record) in section.records.indexed) ...[
                        if (i > 0) const Divider(),
                        _RecordRow(
                          status: statusText(record.status),
                          label: record.label,
                          tone: statusTone(record.status),
                          date: attendanceDateLines(record.date),
                          description: record.description.replaceAll(
                            RegExp(r'QR code', caseSensitive: false),
                            'QR Code',
                          ),
                          remarks: record.remarks.trim() == '自行紀錄的'
                              ? '來源：自行記錄'
                              : record.remarks,
                        ),
                      ],
                      const Divider(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          icon: const Icon(NiuIcons.external, size: 16),
                          onPressed: () => openSchoolRecords(section),
                          label: const Text('在學校網頁查看完整紀錄'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.status,
    required this.label,
    required this.tone,
    required this.date,
    required this.description,
    required this.remarks,
  });
  final String status, label, description, remarks;
  final NiuTone tone;
  final List<String> date;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NiuSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: tone.foreground(context),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: NiuSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date.first,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: tabularFigures,
                  ),
                ),
                if (date.length > 1)
                  Text(
                    date.skip(1).join(' '),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFeatures: tabularFigures,
                    ),
                  ),
                if (description.trim().isNotEmpty) ...[
                  const SizedBox(height: NiuSpacing.xs),
                  Text(description, style: theme.textTheme.bodySmall),
                ],
                if (remarks.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    remarks,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: NiuColors.of(context).inkTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: NiuSpacing.sm),
          Text(
            label != status ? '$status（$label）' : status,
            style: theme.textTheme.titleSmall?.copyWith(
              color: tone.foreground(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Presentation only; preserve unfamiliar school date strings verbatim.
List<String> attendanceDateLines(String source) {
  final match = RegExp(
    r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})\s+(\d{1,2}:\d{2}(?:\s*[-–~]\s*\d{1,2}:\d{2})?)$',
  ).firstMatch(source.trim());
  if (match == null) return [source];
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return [source];
  }
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return [
    '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}（週${weekdays[date.weekday - 1]}）',
    match[4]!.replaceAll(RegExp(r'\s*[-–~]\s*'), '–'),
  ];
}
