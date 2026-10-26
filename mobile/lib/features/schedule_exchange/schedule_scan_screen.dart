import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import 'schedule_exchange_store.dart';
import 'schedule_share.dart';

/// A decoded code waiting for confirmation, bound to the sign-in that
/// scanned it.
class _Candidate {
  const _Candidate(this.payload, this.existing, this.account, this.epoch);
  final ScheduleSharePayload payload;
  final ExchangedSchedule? existing;
  final String account;
  final int epoch;
}

/// Camera first; a decoded code becomes a confirmation card over the camera.
/// Pops with the saved entry.
class ScheduleScanScreen extends StatefulWidget {
  const ScheduleScanScreen({
    super.key,
    required this.session,
    required this.store,
  });
  final CampusSession session;
  final ScheduleExchangeStore store;
  @override
  State<ScheduleScanScreen> createState() => _ScheduleScanScreenState();
}

class _ScheduleScanScreenState extends State<ScheduleScanScreen>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    autoStart: false,
  );
  Future<void> cameraTask = Future.value();
  _Candidate? candidate;
  String? message;
  bool readingPhoto = false, saving = false;

  /// One code at a time, from the camera or a photo.
  bool get accepting =>
      candidate == null && message == null && !readingPhoto && !saving;

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
          start ? await controller.start() : await controller.stop();
        })
        .catchError((Object _) {});
    return cameraTask;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      camera(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraTask.whenComplete(controller.dispose);
    super.dispose();
  }

  void decode(String text) {
    final account = widget.session.account;
    if (account == null) {
      setState(() => message = '請先登入學校帳號。');
      return;
    }
    try {
      final payload = ScheduleSharePayload.decode(text, now: DateTime.now());
      HapticFeedback.mediumImpact();
      setState(
        () => candidate = _Candidate(
          payload,
          widget.store.existing(payload),
          account,
          widget.session.coordinator.epoch,
        ),
      );
    } on ScheduleShareError catch (error) {
      HapticFeedback.heavyImpact();
      setState(() => message = error.message);
    }
  }

  void onDetect(BarcodeCapture capture) {
    if (!accepting) return;
    final value = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value != null) decode(value);
  }

  Future<void> pickPhoto() async {
    if (!accepting) return;
    setState(() => readingPhoto = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '照片',
            extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
            mimeTypes: ['image/*'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final capture = await controller.analyzeImage(
        file.path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (!mounted) return;
      final codes = [
        for (final b in capture?.barcodes ?? const <Barcode>[]) ?b.rawValue,
      ];
      final code =
          codes.where((c) => c.startsWith('NIUTT')).firstOrNull ??
          codes.firstOrNull;
      readingPhoto = false;
      if (code == null) {
        setState(() => message = '照片中找不到 QR Code，請確認截圖清楚完整。');
      } else {
        decode(code);
      }
    } catch (_) {
      if (mounted) setState(() => message = '無法讀取這張照片。');
    } finally {
      if (mounted && readingPhoto) setState(() => readingPhoto = false);
    }
  }

  Future<void> save(_Candidate c, {required bool replace}) async {
    final session = widget.session;
    if (c.account != session.account ||
        c.epoch != session.coordinator.epoch ||
        !widget.store.isReadyFor(c.account)) {
      setState(() {
        candidate = null;
        message = '帳號已變更，未儲存這份課表。';
      });
      return;
    }
    setState(() => saving = true);
    final id = await widget.store.save(
      c.account,
      c.payload,
      replacing: replace ? c.existing?.id : null,
    );
    if (!mounted) return;
    final saved = widget.store.schedules.where((e) => e.id == id).firstOrNull;
    if (saved == null) {
      setState(() {
        saving = false;
        candidate = null;
        message = '無法儲存這份課表，請稍後再試。';
      });
      return;
    }
    AppAnalytics.instance.event('schedule_exchange', {
      'action': replace ? 'update' : 'add',
    });
    Navigator.pop(context, saved);
  }

  void again() => setState(() {
    candidate = null;
    message = null;
  });

  @override
  Widget build(BuildContext context) => Theme(
    data: NiuTheme.dark,
    child: Builder(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          systemOverlayStyle: NiuTheme.overlay(
            Brightness.dark,
            Colors.transparent,
          ),
          automaticallyImplyLeading: false,
          leading: const NiuBackButton(),
          titleSpacing: NiuSpacing.xs,
          title: const Text('掃描同學的課表'),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              fit: BoxFit.cover,
              onDetect: onDetect,
              placeholderBuilder: (context) =>
                  const _CameraMessage(title: '正在啟動相機'),
              errorBuilder: (context, error) => _CameraMessage(
                title: switch (error.errorCode) {
                  MobileScannerErrorCode.permissionDenied => '需要相機權限',
                  MobileScannerErrorCode.unsupported => '找不到可用的相機',
                  _ => '相機啟動失敗',
                },
                message:
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? '請到系統設定允許 NIU-Life 使用相機，或改用「從相簿選取」。'
                    : '可以改用「從相簿選取」讀取同學傳來的截圖。',
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: NiuSpacing.lg),
                  if (accepting || readingPhoto)
                    Text(
                      '對準同學的課表 QR Code',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NiuSpacing.gutter,
                      0,
                      NiuSpacing.gutter,
                      NiuSpacing.lg,
                    ),
                    child: panel(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget panel(BuildContext context) {
    final theme = Theme.of(context);
    final c = candidate;
    if (c == null && message == null) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: readingPhoto ? null : pickPhoto,
          icon: readingPhoto
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_library_rounded),
          label: const Text('從相簿選取'),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(NiuSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xf2141518),
        borderRadius: BorderRadius.circular(NiuRadius.xl),
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: c == null
              ? [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        NiuIcons.warning,
                        color: NiuColors.of(context).warning,
                      ),
                      const SizedBox(width: NiuSpacing.sm),
                      Expanded(
                        child: Text(message!, style: theme.textTheme.bodyLarge),
                      ),
                    ],
                  ),
                  const SizedBox(height: NiuSpacing.md),
                  FilledButton(onPressed: again, child: const Text('重新掃描')),
                ]
              : [
                  Text(
                    c.payload.nickname.isEmpty ? '未命名同學' : c.payload.nickname,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${c.payload.term.title}・${c.payload.courseCount} 門課・${c.payload.includedFields}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (c.existing != null) ...[
                    const SizedBox(height: NiuSpacing.sm),
                    Text('你已經有「${c.existing!.displayName}」這學期的課表。'),
                  ],
                  const SizedBox(height: NiuSpacing.sm),
                  Text(
                    'QR Code 無法證明對方身分，請確認是你認識的同學。',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: NiuSpacing.lg),
                  if (c.existing != null) ...[
                    FilledButton(
                      onPressed: saving ? null : () => save(c, replace: true),
                      child: Text('更新「${c.existing!.displayName}」'),
                    ),
                    const SizedBox(height: NiuSpacing.sm),
                    OutlinedButton(
                      onPressed: saving ? null : () => save(c, replace: false),
                      child: const Text('另存為新的一筆'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: saving ? null : () => save(c, replace: false),
                      child: const Text('加入'),
                    ),
                  TextButton(
                    onPressed: saving ? null : again,
                    child: const Text('取消'),
                  ),
                ],
        ),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.title, this.message});
  final String title;
  final String? message;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(NiuSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_camera_outlined,
              color: Colors.white,
              size: 42,
            ),
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
          ],
        ),
      ),
    ),
  );
}
