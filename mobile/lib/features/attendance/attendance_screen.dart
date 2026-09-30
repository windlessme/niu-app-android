import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../shared/shared.dart';
import '../moodle/moodle_repository.dart';
import '../moodle/moodle_web_screen.dart';
import 'attendance_repository.dart';
import 'attendance_open_flow.dart';
import 'attendance_result_screen.dart';

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
  final flow = AttendanceOpenFlow();

  /// Codes the school already reported as expired in this scanner session.
  final expired = <Uri>{};
  bool active = true;
  String? warning;
  Timer? warningTimer;
  double zoomAtPinch = 0;
  Future<void> cameraTask = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => camera(true));
  }

  Future<void> camera(bool start) {
    cameraTask = cameraTask
        .catchError((Object _) {})
        .then((_) async {
          if (!mounted) return;
          if (start && active && !flow.busy) {
            await controller.start();
          } else {
            await controller.stop();
          }
        })
        .catchError((Object _) {});
    return cameraTask;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    camera(active);
  }

  void warn(String message) {
    HapticFeedback.heavyImpact();
    warningTimer?.cancel();
    setState(() => warning = message);
    warningTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => warning = null);
    });
  }

  Future<void> open(String raw) async {
    if (!active || flow.busy || warning != null) return;
    final uri = attendanceQr(raw);
    if (uri == null) {
      warn('這不是 M 園區點名 QR Code');
      return;
    }
    if (expired.contains(uri)) {
      warn('這個 QR Code 已過期，請掃描老師目前顯示的最新 QR Code');
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      await flow.open(
        raw,
        pause: () => camera(false),
        // Scanning the code is the student's explicit intent, as on iOS.
        confirm: (_) async => mounted && active,
        navigate: (uri) async {
          if (!mounted) return;
          widget.repository.requireCurrent();
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AttendanceResultScreen(
                repository: widget.repository,
                target: uri,
                onExpired: () => expired.add(uri),
              ),
            ),
          );
        },
        resume: () => camera(true),
      );
    } catch (_) {
      if (mounted) warn('無法開啟點名，請確認已登入 M 園區');
    }
  }

  Future<void> enterLink() async {
    // Pause in the background; the sheet must not wait on the camera.
    unawaited(camera(false));
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LinkSheet(),
    );
    if (!mounted) return;
    unawaited(camera(true));
    if (value != null && value.trim().isNotEmpty) await open(value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    warningTimer?.cancel();
    cameraTask.whenComplete(controller.dispose);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: NiuTheme.dark,
    child: Builder(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        // The link sheet handles the keyboard; the camera view stays put.
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          systemOverlayStyle: NiuTheme.overlay(
            Brightness.dark,
            Colors.transparent,
          ),
          automaticallyImplyLeading: false,
          leading: const NiuBackButton(),
          titleSpacing: NiuSpacing.xs,
          title: const Text('快速點名'),
          actions: [
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: controller,
              builder: (context, state, _) =>
                  state.isRunning && state.torchState != TorchState.unavailable
                  ? NiuIconButton(
                      icon: state.torchState == TorchState.on
                          ? Icons.flashlight_off_rounded
                          : NiuIcons.flashlight,
                      tooltip: state.torchState == TorchState.on
                          ? '關閉手電筒'
                          : '開啟手電筒',
                      onPressed: controller.toggleTorch,
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: NiuSpacing.xs),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              if (!controller.value.isRunning) return;
              controller
                  .setFocusPoint(
                    Offset(
                      details.localPosition.dx / constraints.maxWidth,
                      details.localPosition.dy / constraints.maxHeight,
                    ),
                  )
                  .catchError((Object _) {});
            },
            onScaleStart: (_) => zoomAtPinch = controller.value.zoomScale,
            onScaleUpdate: (details) {
              if (details.pointerCount < 2 || !controller.value.isRunning) {
                return;
              }
              controller
                  .setZoomScale(
                    (zoomAtPinch + (details.scale - 1) * .5).clamp(0.0, 1.0),
                  )
                  .catchError((Object _) {});
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: controller,
                  fit: BoxFit.cover,
                  onDetect: (capture) {
                    for (final b in capture.barcodes) {
                      if (b.rawValue != null) {
                        open(b.rawValue!);
                        break;
                      }
                    }
                  },
                  placeholderBuilder: (context) => const _ScannerMessage(
                    icon: Icons.photo_camera_outlined,
                    title: '正在啟動相機',
                  ),
                  errorBuilder: (context, error) => _ScannerMessage(
                    icon: error.errorCode == MobileScannerErrorCode.unsupported
                        ? Icons.no_photography_outlined
                        : Icons.photo_camera_outlined,
                    title: switch (error.errorCode) {
                      MobileScannerErrorCode.permissionDenied => '需要相機權限',
                      MobileScannerErrorCode.unsupported => '找不到可用的相機',
                      _ => '相機啟動失敗',
                    },
                    message: switch (error.errorCode) {
                      MobileScannerErrorCode.permissionDenied =>
                        '請到系統設定允許 NIU-Life 使用相機，才能掃描點名 QR Code。',
                      MobileScannerErrorCode.unsupported =>
                        '這台裝置沒有可用的相機，可以改用輸入點名網址。',
                      _ => '請關閉其他使用相機的 App 後再試一次。',
                    },
                    actionLabel:
                        error.errorCode == MobileScannerErrorCode.unsupported
                        ? null
                        : '再試一次',
                    onAction: () => camera(true),
                  ),
                ),
                const IgnorePointer(child: _ScannerOverlay()),
                SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: NiuSpacing.lg),
                      Text(
                        '對準老師顯示的 QR Code',
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: NiuSpacing.xs),
                      Text(
                        '掃描後會開啟 M 園區點名網址並完成網頁登入',
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                      if (warning != null) ...[
                        const SizedBox(height: NiuSpacing.lg),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: NiuSpacing.gutter,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xe6d33a33),
                              borderRadius: BorderRadius.circular(
                                NiuRadius.pill,
                              ),
                            ),
                            child: Text(
                              warning!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      _ScannerControls(
                        controller: controller,
                        onEnterLink: enterLink,
                      ),
                    ],
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

/// Manual fallback for a link shared by the teacher.
class _LinkSheet extends StatefulWidget {
  const _LinkSheet();
  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      NiuSpacing.gutter,
      0,
      NiuSpacing.gutter,
      NiuSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('輸入點名網址', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: NiuSpacing.xs),
          Text(
            '貼上老師提供的 M 園區點名連結。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: NiuSpacing.lg),
          TextField(
            controller: text,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            onSubmitted: (v) => Navigator.pop(context, v),
            decoration: const InputDecoration(
              hintText: 'https://euni.niu.edu.tw/…',
              prefixIcon: Icon(NiuIcons.link),
            ),
          ),
          const SizedBox(height: NiuSpacing.md),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('開啟點名'),
          ),
        ],
      ),
    ),
  );
}

/// Dim everything except a rounded, dashed scan window.
class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _OverlayPainter());
}

class _OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = (size.shortestSide * .72).clamp(0.0, 310.0);
    final window = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * .46),
        width: side,
        height: side,
      ),
      const Radius.circular(24),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(window),
      ),
      Paint()..color = const Color(0x8c000000),
    );
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final metric in (Path()..addRRect(window)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 28) {
        canvas.drawPath(metric.extractPath(d, d + 20), border);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScannerControls extends StatelessWidget {
  const _ScannerControls({required this.controller, required this.onEnterLink});
  final MobileScannerController controller;
  final VoidCallback onEnterLink;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(
      NiuSpacing.gutter,
      0,
      NiuSpacing.gutter,
      NiuSpacing.lg,
    ),
    padding: const EdgeInsets.fromLTRB(
      NiuSpacing.lg,
      NiuSpacing.sm,
      NiuSpacing.lg,
      NiuSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: const Color(0xb3141518),
      borderRadius: BorderRadius.circular(NiuRadius.xl),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<MobileScannerState>(
          valueListenable: controller,
          builder: (context, state, _) => Row(
            children: [
              const Icon(Icons.zoom_out_rounded, color: Colors.white70),
              Expanded(
                child: Slider(
                  value: state.zoomScale.clamp(0.0, 1.0),
                  onChanged: state.isRunning
                      ? (v) =>
                            controller.setZoomScale(v).catchError((Object _) {})
                      : null,
                  semanticFormatterCallback: (v) => '縮放 ${(v * 100).round()}%',
                ),
              ),
              const Icon(Icons.zoom_in_rounded, color: Colors.white70),
            ],
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: onEnterLink,
          icon: const Icon(NiuIcons.link, size: 18),
          label: const Text('改用點名網址'),
        ),
      ],
    ),
  );
}

class _ScannerMessage extends StatelessWidget {
  const _ScannerMessage({
    required this.title,
    this.icon,
    this.message,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final IconData? icon;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NiuSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 42),
            const SizedBox(height: NiuSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            if (message != null) ...[
              const SizedBox(height: NiuSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: NiuSpacing.xl),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ),
  );
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
