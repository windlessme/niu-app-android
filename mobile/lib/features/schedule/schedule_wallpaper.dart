import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/shared.dart';
import 'schedule_models.dart';
import 'schedule_presentation.dart';
import 'schedule_week_view.dart';

/// One course over its consecutive periods in the wallpaper grid.
typedef WallpaperBlock = ({
  ScheduleLesson lesson,
  int column,
  int top,
  int bottom,
});

/// The week for a wallpaper, as on iOS: Monday to Friday plus a weekend day
/// with classes, trimmed to the first and last periods in use. No dates,
/// since the picture does not change.
class WallpaperContent {
  WallpaperContent(ClassSchedule schedule) : periods = schedule.periods {
    final index = {for (final (i, p) in periods.indexed) p.label: i};
    for (final (d, day) in scheduleWeekdays.indexed) {
      final lessons = scheduleLessons(schedule, day, mergeConsecutive: true);
      if (d >= 5 && lessons.isEmpty) continue;
      final column = days.length;
      days.add(d);
      for (final lesson in lessons) {
        final rows = [for (final p in lesson.periods) ?index[p]];
        if (rows.isEmpty) continue;
        blocks.add((
          lesson: lesson,
          column: column,
          top: rows.reduce((a, b) => a < b ? a : b),
          bottom: rows.reduce((a, b) => a > b ? a : b),
        ));
      }
    }
    if (blocks.isNotEmpty) {
      first = blocks.map((b) => b.top).reduce((a, b) => a < b ? a : b);
      last = blocks.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);
    }
  }
  final List<SchedulePeriod> periods;

  /// Monday-based weekdays shown, in order.
  final days = <int>[];
  final blocks = <WallpaperBlock>[];
  int first = 0, last = -1;
  bool get isEmpty => blocks.isEmpty;
  int get rows => last - first + 1;
}

/// The picture itself, at the phone's screen size. The top is kept clear for
/// the lock screen clock and the bottom for its shortcut buttons.
class ScheduleWallpaperCanvas extends StatelessWidget {
  const ScheduleWallpaperCanvas({
    super.key,
    required this.content,
    required this.size,
    this.background,
    this.dark = false,
    this.compact = false,
  });
  final WallpaperContent content;
  final Size size;
  final ui.Image? background;
  final bool dark, compact;

  static const _padding = 10.0, _header = 22.0, _gutter = 28.0;

  Rect get card {
    final bottom = size.height * 0.885;
    final top = size.height * (compact ? 0.52 : 0.34);
    final rows = content.rows < 1 ? 1 : content.rows;
    final rowHeight = ((bottom - top - _padding * 2 - _header) / rows).clamp(
      0.0,
      56.0,
    );
    final height = _padding * 2 + _header + rowHeight * rows;
    return Rect.fromLTWH(14, bottom - height, size.width - 28, height);
  }

  Widget backdrop() => SizedBox.fromSize(
    size: size,
    child: background != null
        ? RawImage(image: background, fit: BoxFit.cover)
        : const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xff5478db), Color(0xff9961c7)],
              ),
            ),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final rect = card;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    final ink = dark ? Colors.white : Colors.black;
    return Theme(
      data: dark ? NiuTheme.dark : NiuTheme.light,
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          children: [
            backdrop(),
            if (!content.isEmpty) ...[
              // A blurred copy behind the card keeps text legible on photos.
              ClipPath(
                clipper: _RRectClipper(shape),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: backdrop(),
                ),
              ),
              Positioned.fromRect(
                rect: rect,
                child: Container(
                  padding: const EdgeInsets.all(_padding),
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.black.withValues(alpha: .45)
                        : Colors.white.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: ink.withValues(alpha: .12),
                      width: .5,
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, box) => _grid(context, box.biggest, ink),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// [space] is the card's inside, after its padding and border.
  Widget _grid(BuildContext context, Size space, Color ink) {
    final rowHeight = (space.height - _header) / content.rows;
    final columnWidth = (space.width - _gutter) / content.days.length;
    String clock(SchedulePeriod p) =>
        RegExp(r'\d{1,2}:\d{2}').firstMatch(p.time)?[0] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _header,
          child: Row(
            children: [
              const SizedBox(width: _gutter),
              for (final d in content.days)
                SizedBox(
                  width: columnWidth,
                  child: Text(
                    '週${'一二三四五六日'[d]}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: .7),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              for (var row = content.first; row <= content.last; row++) ...[
                Positioned(
                  top: (row - content.first) * rowHeight,
                  left: 0,
                  width: _gutter,
                  height: rowHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          schedulePeriodNumber(content.periods[row].label),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: ink.withValues(alpha: .75),
                          ),
                        ),
                        if (rowHeight >= 30 &&
                            clock(content.periods[row]).isNotEmpty)
                          Text(
                            clock(content.periods[row]),
                            style: TextStyle(
                              fontSize: 7.5,
                              color: ink.withValues(alpha: .5),
                              fontFeatures: tabularFigures,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: (row - content.first) * rowHeight,
                  left: _gutter,
                  right: 0,
                  child: Container(
                    height: .5,
                    color: ink.withValues(alpha: .08),
                  ),
                ),
              ],
              for (final block in content.blocks)
                Positioned(
                  left: _gutter + block.column * columnWidth + 1.5,
                  top: (block.top - content.first) * rowHeight + 1.5,
                  width: columnWidth - 3,
                  height: (block.bottom - block.top + 1) * rowHeight - 3,
                  child: Builder(
                    builder: (context) =>
                        _block(context, block, rowHeight, ink),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _block(
    BuildContext context,
    WallpaperBlock block,
    double rowHeight,
    Color ink,
  ) {
    final colour = lessonHue(block.lesson.name).foreground(context);
    final height = (block.bottom - block.top + 1) * rowHeight;
    final nameSize = (rowHeight * .3).clamp(8.5, 11.5).toDouble();
    final custom = block.lesson.customId != null;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: dark ? .42 : .24),
        borderRadius: BorderRadius.circular(6),
        border: custom
            ? Border.all(color: colour.withValues(alpha: .9))
            : Border(left: BorderSide(color: colour, width: 2.5)),
      ),
      padding: const EdgeInsets.fromLTRB(5, 4, 2, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              block.lesson.name,
              maxLines: ((height - 16) / (nameSize * 1.25)).floor().clamp(1, 8),
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: nameSize,
                fontWeight: FontWeight.w600,
                color: ink,
                height: 1.15,
              ),
            ),
          ),
          if (height >= 36 && block.lesson.room.isNotEmpty)
            Text(
              block.lesson.room,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w500,
                color: ink.withValues(alpha: .75),
              ),
            ),
        ],
      ),
    );
  }
}

class _RRectClipper extends CustomClipper<Path> {
  _RRectClipper(this.shape);
  final RRect shape;
  @override
  Path getClip(Size size) => Path()..addRRect(shape);
  @override
  bool shouldReclip(_RRectClipper old) => old.shape != shape;
}

/// Sets or saves a rendered wallpaper; the photo library is never read.
class WallpaperGateway {
  const WallpaperGateway();
  static const channel = MethodChannel('niulife/wallpaper');

  /// [target] is 'lock' or 'both'.
  Future<bool> set(Uint8List png, String target) async =>
      await channel.invokeMethod<bool>('setWallpaper', {
        'bytes': png,
        'target': target,
      }) ??
      false;

  /// False on Android 9 and older, where the picture is shared instead.
  Future<bool> save(Uint8List png) async =>
      await channel.invokeMethod<bool>('saveImage', {'bytes': png}) ?? false;
}

/// 製作課表桌布: a photo (or the default gradient), the week on top of it,
/// then set as the lock screen or saved.
class ScheduleWallpaperScreen extends StatefulWidget {
  const ScheduleWallpaperScreen({
    super.key,
    required this.schedule,
    required this.withCustom,
    this.gateway = const WallpaperGateway(),
  });

  /// The school timetable, and the same with this week's custom courses.
  final ClassSchedule schedule, withCustom;
  final WallpaperGateway gateway;
  @override
  State<ScheduleWallpaperScreen> createState() =>
      _ScheduleWallpaperScreenState();
}

class _ScheduleWallpaperScreenState extends State<ScheduleWallpaperScreen> {
  final boundary = GlobalKey();
  bool dark = false, compact = false, includeCustom = true;
  ui.Image? background;
  bool loadingImage = false, busy = false;

  static const _prefix = 'scheduleWallpaper.';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        dark = prefs.getBool('${_prefix}dark') ?? dark;
        compact = prefs.getBool('${_prefix}compact') ?? compact;
        includeCustom = prefs.getBool('${_prefix}custom') ?? includeCustom;
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    background?.dispose();
    super.dispose();
  }

  void remember(String key, bool value) => SharedPreferences.getInstance().then(
    (p) => p.setBool('$_prefix$key', value),
    onError: (_) => false,
  );

  Size screen(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    return Size(s.shortestSide, s.longestSide);
  }

  Future<void> pickPhoto() async {
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
    final pixels = screen(context) * MediaQuery.devicePixelRatioOf(context);
    setState(() => loadingImage = true);
    try {
      final bytes = await file.readAsBytes();
      // Decode only as large as the screen; camera photos are huge.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = [
        pixels.width / descriptor.width,
        pixels.height / descriptor.height,
      ].reduce((a, b) => a > b ? a : b).clamp(0.0, 1.0);
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        background?.dispose();
        background = frame.image;
      });
    } catch (_) {
      if (mounted) showNiuMessage(context, '無法讀取這張照片，請換一張再試。');
    } finally {
      if (mounted) setState(() => loadingImage = false);
    }
  }

  Future<Uint8List> render() async {
    final object = boundary.currentContext!.findRenderObject()!;
    final image = await (object as RenderRepaintBoundary).toImage(
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('render');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> run(Future<String> Function(Uint8List png) action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final message = await action(await render());
      if (mounted) showNiuMessage(context, message);
    } catch (_) {
      if (mounted) showNiuMessage(context, '桌布產生失敗，請再試一次。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String> setAs(Uint8List png, String target) async {
    final ok = await widget.gateway.set(png, target);
    return ok ? (target == 'lock' ? '已設為鎖定畫面桌布' : '已設為主畫面與鎖定畫面桌布') : '無法設定桌布';
  }

  Future<String> save(Uint8List png) async {
    if (await widget.gateway.save(png)) return '已儲存到相簿的 NIU-Life 資料夾';
    // Android 9 and older: hand the picture to another app instead.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/NIU-Life 課表桌布.png');
    await file.writeAsBytes(png);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
    );
    return '已開啟分享，可以儲存到相簿';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = screen(context);
    final content = WallpaperContent(
      includeCustom ? widget.withCustom : widget.schedule,
    );
    final hasCustom = !identical(widget.withCustom, widget.schedule);
    final canvas = RepaintBoundary(
      key: boundary,
      child: ScheduleWallpaperCanvas(
        content: content,
        size: size,
        background: background,
        dark: dark,
        compact: compact,
      ),
    );
    return Scaffold(
      appBar: const NiuAppBar(title: '課表桌布'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          NiuSpacing.gutter,
          NiuSpacing.md,
          NiuSpacing.gutter,
          NiuSpacing.huge,
        ),
        children: [
          Center(
            child: SizedBox(
              height: 440,
              width: 440 * size.width / size.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(NiuRadius.card),
                child: Stack(
                  children: [
                    FittedBox(child: canvas),
                    // The clock is only in the preview, to show what stays clear.
                    Positioned(
                      top: 440 * .07,
                      left: 0,
                      right: 0,
                      child: Text(
                        '9:41',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 440 * 96 / size.height,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: .55),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (content.isEmpty) ...[
            const SizedBox(height: NiuSpacing.lg),
            const NiuBanner(tone: NiuTone.warning, message: '目前課表沒有課程，無法產生桌布。'),
          ],
          NiuSection(
            title: '背景',
            subtitle: '照片只在這支手機上處理，不會上傳。',
            child: NiuGroup(
              children: [
                NiuRow(
                  icon: Icons.photo_library_outlined,
                  hue: NiuHue.blue,
                  title: background == null ? '選擇照片' : '更換照片',
                  value: loadingImage ? '讀取中…' : null,
                  onTap: loadingImage ? null : pickPhoto,
                ),
                if (background != null)
                  NiuRow(
                    icon: NiuIcons.clear,
                    hue: NiuHue.gray,
                    title: '移除照片，改用預設背景',
                    onTap: () => setState(() {
                      background?.dispose();
                      background = null;
                    }),
                  ),
              ],
            ),
          ),
          NiuSection(
            title: '樣式',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NiuSegmented<bool>(
                  segments: const [(false, '淺色'), (true, '深色')],
                  value: dark,
                  onChanged: (v) {
                    setState(() => dark = v);
                    remember('dark', v);
                  },
                ),
                const SizedBox(height: NiuSpacing.md),
                NiuSegmented<bool>(
                  segments: const [(false, '標準'), (true, '精簡')],
                  value: compact,
                  onChanged: (v) {
                    setState(() => compact = v);
                    remember('compact', v);
                  },
                ),
                if (hasCustom) ...[
                  const SizedBox(height: NiuSpacing.md),
                  NiuGroup(
                    children: [
                      NiuRow(
                        title: '包含自訂課程',
                        chevron: false,
                        onTap: () {
                          setState(() => includeCustom = !includeCustom);
                          remember('custom', includeCustom);
                        },
                        trailing: Switch(
                          value: includeCustom,
                          onChanged: (v) {
                            setState(() => includeCustom = v);
                            remember('custom', v);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: NiuSpacing.section),
          FilledButton.icon(
            onPressed: content.isEmpty || busy
                ? null
                : () => run((png) => setAs(png, 'lock')),
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('設為鎖定畫面桌布'),
          ),
          const SizedBox(height: NiuSpacing.sm),
          OutlinedButton(
            onPressed: content.isEmpty || busy
                ? null
                : () => run((png) => setAs(png, 'both')),
            child: const Text('設為主畫面與鎖定畫面'),
          ),
          const SizedBox(height: NiuSpacing.sm),
          TextButton.icon(
            onPressed: content.isEmpty || busy ? null : () => run(save),
            icon: const Icon(NiuIcons.download),
            label: const Text('儲存到相簿'),
          ),
          const SizedBox(height: NiuSpacing.lg),
          Text(
            '上方留給鎖定畫面的時間，下方避開手電筒與相機按鈕。桌布是固定的圖片，課表更新或自訂課程到期後需要重新產生。',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
