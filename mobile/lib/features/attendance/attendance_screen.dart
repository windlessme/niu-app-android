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
          if (mounted) setState(() => error = '無法啟動相機，請確認權限或貼上點名網址。');
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
          return await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  scrollable: true,
                  title: const Text('確認開啟點名'),
                  content: Text(
                    '即將開啟 M 園區第 ${uri.queryParameters['sessid']} 次點名。開啟校方頁面可能立即記錄出席，是否繼續？',
                  ),
                  actions: [
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('開啟並點名'),
                    ),
                  ],
                ),
              ) ??
              false;
        },
        navigate: (uri) async {
          if (!mounted || !active) return;
          widget.repository.requireCurrent();
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MoodleWebScreen(
                repository: widget.repository,
                target: uri,
                title: 'M 園區點名',
                attendance: true,
              ),
            ),
          );
        },
        resume: () => camera(true),
      );
    } catch (_) {
      if (mounted) setState(() => error = '無法開啟點名，請確認登入與 QR Code 後重試。');
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
  Widget build(BuildContext context) => Scaffold(
    appBar: const IosPageHeader(title: '掃描點名'),
    body: SafeArea(
      top: false,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .35,
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
              errorBuilder: (_, error) =>
                  const Center(child: Text('無法使用相機，請在系統設定允許相機權限，或貼上點名網址。')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (error != null)
                  Semantics(liveRegion: true, child: Text(error!)),
                TextField(
                  controller: input,
                  focusNode: inputFocus,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  onSubmitted: open,
                  decoration: const InputDecoration(labelText: '貼上老師提供的點名網址'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: () => open(input.text),
                  child: const Text('開啟點名'),
                ),
              ],
            ),
          ),
        ],
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

  Color statusColor(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.green.shade300
          : Colors.green.shade800,
    AttendanceStatus.late =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.amber.shade300
          : Colors.brown.shade700,
    AttendanceStatus.absent => Theme.of(context).colorScheme.error,
    AttendanceStatus.leave =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.blue.shade300
          : Colors.blue.shade800,
    AttendanceStatus.pending => Theme.of(context).colorScheme.onSurfaceVariant,
  };
  String statusText(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => '出席',
    AttendanceStatus.late => '遲到',
    AttendanceStatus.absent => '缺席',
    AttendanceStatus.leave => '請假',
    AttendanceStatus.pending => '尚未點名',
  };
  @override
  Widget build(BuildContext context) => FutureBuilder<List<AttendanceSection>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('無法載入這門課的點名活動，請確認網路後重試。', textAlign: TextAlign.center),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: retry,
                child: const Text('重新載入點名紀錄'),
              ),
            ],
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在載入點名紀錄…'),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: retry,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AttendanceScannerScreen(repository: widget.repository),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('掃描點名'),
            ),
            if (snapshot.data!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('這門課尚未提供點名活動。'),
              ),
            for (final section in snapshot.data!)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (section.records.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            for (final status in AttendanceStatus.values)
                              Text(
                                '${statusText(status)} ${section.records.where((r) => r.status == status).length}',
                                style: TextStyle(color: statusColor(status)),
                              ),
                          ],
                        ),
                      ],
                      if (section.error != null) ...[
                        Text(
                          section.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: retry,
                          child: const Text('重試讀取紀錄'),
                        ),
                      ] else if (section.records.isEmpty)
                        const Text('這個點名活動目前沒有上課紀錄。')
                      else if (section.pending == section.records.length)
                        const Text('目前所有上課時段皆尚未點名，可查看校方完整紀錄確認。'),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MoodleWebScreen(
                                repository: widget.repository,
                                target: Uri.https(
                                  'euni.niu.edu.tw',
                                  '/mod/attendance/view.php',
                                  {'id': '${section.moduleId}', 'view': '5'},
                                ),
                                title: '校方出席紀錄',
                              ),
                            ),
                          );
                          if (mounted) await retry();
                        },
                        child: const Text('查看校方完整紀錄'),
                      ),
                      for (final record in section.records)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(record.date),
                          subtitle: Text(
                            '${statusText(record.status)}${record.label != statusText(record.status) ? '（${record.label}）' : ''}\n${record.description}\n${record.remarks}'
                                .trim(),
                          ),
                          leading: Icon(switch (record.status) {
                            AttendanceStatus.present =>
                              Icons.check_circle_outline,
                            AttendanceStatus.late => Icons.watch_later_outlined,
                            AttendanceStatus.absent => Icons.cancel_outlined,
                            AttendanceStatus.leave =>
                              Icons.event_available_outlined,
                            AttendanceStatus.pending => Icons.schedule,
                          }, color: statusColor(record.status)),
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
