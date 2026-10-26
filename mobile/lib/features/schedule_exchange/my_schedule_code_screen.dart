import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import 'schedule_exchange_screen.dart';
import 'schedule_exchange_store.dart';
import 'schedule_share.dart';

/// The student's own timetable as a QR code for a classmate to scan.
class MyScheduleCodeScreen extends StatefulWidget {
  const MyScheduleCodeScreen({
    super.key,
    required this.session,
    required this.store,
  });
  final CampusSession session;
  final ScheduleExchangeStore store;
  @override
  State<MyScheduleCodeScreen> createState() => _MyScheduleCodeScreenState();
}

class _MyScheduleCodeScreenState extends State<MyScheduleCodeScreen> {
  final current = ScheduleShareTerm.containing(DateTime.now());
  late ScheduleShareTerm term = current;
  late final name = TextEditingController(
    text: widget.store.preferences.customNickname,
  );
  bool editingName = false;
  Future<void> brightness = Future.value();

  /// The last code and what it was made from, so rebuilds keep it stable.
  String? codeKey;
  ({String? text, String? message}) code = (text: null, message: null);

  @override
  void initState() {
    super.initState();
    // A bright screen scans more reliably, as on the library code.
    brightness = brightness.then((_) async {
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(1);
      } catch (_) {}
    });
    AppAnalytics.instance.event('schedule_exchange', {'action': 'show_code'});
  }

  @override
  void dispose() {
    name.dispose();
    brightness.then((_) async {
      try {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } catch (_) {}
    });
    super.dispose();
  }

  String? get realName {
    final value = '${widget.session.profile['chName'] ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }

  String nickname(ScheduleSharePreferences p) =>
      ScheduleSharePayload.cleanNickname(
        p.useRealName && realName != null ? realName! : p.customNickname,
      );

  Future<void> update(
    ScheduleSharePreferences Function(ScheduleSharePreferences) change,
  ) async {
    final account = widget.session.account;
    if (account == null ||
        !await widget.store.updatePreferences(account, change)) {
      if (mounted) showExchangeError(context, '無法儲存變更，請稍後再試。');
    }
  }

  Future<void> saveName() async {
    final value = ScheduleSharePayload.cleanNickname(name.text);
    if (value.isEmpty) return;
    await update((p) => p.copyWith(customNickname: value, useRealName: false));
    if (mounted) setState(() => editingName = false);
  }

  ({String? text, String? message}) makeCode(
    ScheduleSharePreferences p,
    String nickname,
  ) {
    final cached = widget.session.cachedSchedule;
    final key = [
      p.toJson(),
      term.title,
      nickname,
      identityHashCode(cached?.rows),
    ].join('|');
    if (key == codeKey) return code;
    codeKey = key;
    final school = exchangeSchoolSchedule(widget.session);
    if (school == null) {
      return code = (text: null, message: '尚未載入課表，請先回到課表頁更新。');
    }
    final payload = ScheduleSharePayload.fromSchedule(
      school,
      shareId: p.shareId,
      term: term,
      nickname: nickname,
      createdAt: DateTime.now(),
      includeRooms: p.includeRooms,
      includeTeachers: p.includeTeachers,
    );
    if (payload.slots.isEmpty) {
      return code = (text: null, message: '課表中沒有可分享的課程。');
    }
    try {
      return code = (text: payload.encoded(), message: null);
    } on ScheduleShareError {
      return code = (
        text: null,
        message: p.includeRooms || p.includeTeachers
            ? '課表內容太多，QR Code 會難以掃描。請關閉「教室」或「授課教師」後再試。'
            : '課表內容太多，無法放進一個 QR Code。',
      );
    }
  }

  Future<void> shareImage(String text) async {
    try {
      final file = File(
        '${(await getTemporaryDirectory()).path}/schedule-qr.png',
      );
      await file.writeAsBytes(await qrPng(text));
      AppAnalytics.instance.event('schedule_exchange', {
        'action': 'share_image',
      });
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '我的課表 QR Code，用「課表交換」的「從相簿選取」讀取，24 小時內有效。',
        ),
      );
    } catch (_) {
      if (mounted) showExchangeError(context, '無法分享圖片，請稍後再試。');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.session, widget.store]),
    builder: (context, _) {
      final ready = widget.store.isReadyFor(widget.session.account);
      final p = widget.store.preferences;
      final shown = nickname(p);
      final naming = editingName || shown.isEmpty;
      return NiuScrollPage(
        title: '我的課表 QR Code',
        children: !ready
            ? const [NiuLoading()]
            : naming
            ? [nameEditor(context, canCancel: shown.isNotEmpty)]
            : [
                codeCard(context, shown, makeCode(p, shown)),
                const SizedBox(height: NiuSpacing.xl),
                options(context, p),
              ],
      );
    },
  );

  Widget nameEditor(BuildContext context, {required bool canCancel}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: NiuSpacing.lg),
        Text('同學會看到什麼名字？', style: theme.textTheme.titleLarge),
        const SizedBox(height: NiuSpacing.lg),
        TextField(
          controller: name,
          autofocus: true,
          maxLength: ScheduleSharePayload.maxNicknameLength,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => saveName(),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: '輸入暱稱，例如：小安'),
        ),
        const SizedBox(height: NiuSpacing.sm),
        FilledButton(
          onPressed: ScheduleSharePayload.cleanNickname(name.text).isEmpty
              ? null
              : saveName,
          child: const Text('使用這個暱稱'),
        ),
        if (realName != null) ...[
          const SizedBox(height: NiuSpacing.sm),
          OutlinedButton(
            onPressed: () async {
              await update((p) => p.copyWith(useRealName: true));
              if (mounted) setState(() => editingName = false);
            },
            child: Text('改用真實姓名「$realName」'),
          ),
        ],
        if (canCancel)
          TextButton(
            onPressed: () => setState(() => editingName = false),
            child: const Text('取消'),
          ),
      ],
    );
  }

  Widget codeCard(
    BuildContext context,
    String nickname,
    ({String? text, String? message}) code,
  ) {
    final theme = Theme.of(context);
    final text = code.text;
    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.all(NiuSpacing.xxl),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NiuRadius.xxl),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xff8a3fc4),
                    Color(0xff4f46c8),
                    Color(0xff0a62d0),
                  ],
                ),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xff8a3fc4),
                    child: Text(
                      nickname.characters.take(1).toString(),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: NiuSpacing.sm),
                  Text(
                    nickname,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    term.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: .85),
                    ),
                  ),
                  const SizedBox(height: NiuSpacing.lg),
                  AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(NiuRadius.lg),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(NiuSpacing.lg),
                        child: text != null
                            ? Semantics(
                                image: true,
                                label: '我的課表 QR Code',
                                child: CustomPaint(painter: QrPainter(text)),
                              )
                            : Center(
                                child: Text(
                                  code.message ?? '',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: NiuSpacing.md),
                  Text(
                    '在「課表交換」按「掃描」',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: .85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: NiuSpacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: NiuSpacing.sm,
          runSpacing: NiuSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                name.text = widget.store.preferences.customNickname;
                setState(() => editingName = true);
              },
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('修改顯示名稱'),
            ),
            if (text != null)
              OutlinedButton.icon(
                onPressed: () => shareImage(text),
                icon: const Icon(NiuIcons.share, size: 18),
                label: const Text('傳送圖片'),
              ),
          ],
        ),
        const SizedBox(height: NiuSpacing.md),
        Text(
          'QR Code 24 小時內有效。旁人也看得到內容，請只給想分享的同學掃。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget options(BuildContext context, ScheduleSharePreferences p) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NiuSegmented<ScheduleShareTerm>(
          segments: [(current, '本學期'), (current.next, '下學期')],
          value: term,
          onChanged: (value) => setState(() => term = value),
        ),
        const SizedBox(height: NiuSpacing.lg),
        NiuGroup(
          insetDividers: NiuSpacing.lg,
          children: [
            const NiuRow(title: '上課時間與課名', value: '一律包含'),
            SwitchListTile(
              title: const Text('教室'),
              value: p.includeRooms,
              onChanged: (v) => update((p) => p.copyWith(includeRooms: v)),
            ),
            SwitchListTile(
              title: const Text('授課教師'),
              value: p.includeTeachers,
              onChanged: (v) => update((p) => p.copyWith(includeTeachers: v)),
            ),
          ],
        ),
        const SizedBox(height: NiuSpacing.sm),
        Text(
          '自訂課程不會分享。學期結束後，同學那邊的這份課表會自動過期。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: NiuSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: NiuColors.of(context).error,
            ),
            onPressed: () async {
              final account = widget.session.account;
              if (account == null ||
                  !await confirm(
                    context,
                    title: '重設分享識別碼？',
                    message: '同學之後掃描你的新 QR Code 時，會變成新的一筆，而不是更新舊的。',
                    action: '重設',
                  )) {
                return;
              }
              if (!await widget.store.resetShareId(account) && mounted) {
                showExchangeError(this.context, '無法儲存變更，請稍後再試。');
              }
            },
            child: const Text('重設分享識別碼'),
          ),
        ),
      ],
    );
  }
}

QrImage _qr(String text) => QrImage(
  QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M),
);

/// Black modules on the white the caller puts behind them.
class QrPainter extends CustomPainter {
  QrPainter(this.text) : image = _qr(text);
  final String text;
  final QrImage image;
  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final module = size.shortestSide / count;
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var y = 0; y < count; y++) {
      for (var x = 0; x < count; x++) {
        if (image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * module, y * module, module + .5, module + .5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(QrPainter old) => old.text != text;
}

/// A PNG with the quiet zone scanners need, for sending as a picture.
Future<List<int>> qrPng(String text) async {
  final image = _qr(text);
  const scale = 12, quiet = 4;
  final side = (image.moduleCount + quiet * 2) * scale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..color = Colors.white,
  );
  final paint = Paint()..color = Colors.black;
  for (var y = 0; y < image.moduleCount; y++) {
    for (var x = 0; x < image.moduleCount; x++) {
      if (image.isDark(y, x)) {
        canvas.drawRect(
          Rect.fromLTWH(
            ((x + quiet) * scale).toDouble(),
            ((y + quiet) * scale).toDouble(),
            scale.toDouble(),
            scale.toDouble(),
          ),
          paint,
        );
      }
    }
  }
  final picture = await recorder.endRecording().toImage(side, side);
  final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
