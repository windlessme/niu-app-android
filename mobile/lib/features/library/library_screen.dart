import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../../core/network/school_clients.dart';
import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import 'library_repository.dart';
import '../demo/demo_services.dart';

/// Register with the navigator that owns this screen, including popup routes.
final libraryRouteObserver = RouteObserver<ModalRoute<dynamic>>();

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.account,
    this.repository,
    this.now,
  });
  final String account;
  final LibraryRepository? repository;
  final DateTime Function()? now;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver, RouteAware {
  late final repository =
      widget.repository ??
      (CampusSession.instance.isDemo
          ? DemoLibraryRepository()
          : LibraryRepository(schoolClient('https://sso.niu.edu.tw')));
  LibraryCodeKind kind = LibraryCodeKind.entrance;
  Uint8List? image;
  DateTime? updated;
  String? error;
  Timer? timer;
  int generation = 0;
  bool active = true;
  bool foreground = true;
  bool covered = false;
  bool loading = false;
  bool pending = false;
  String? imageAccount;
  LibraryCodeKind? imageKind;
  ModalRoute<dynamic>? route;
  bool sessionCleared = false;
  Future<void> brightnessTask = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CampusSession.instance.registerCleanup(clearSession);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    active = foreground;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      brighten();
      refresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    if (route != next) {
      libraryRouteObserver.unsubscribe(this);
      route = next;
      if (next != null) libraryRouteObserver.subscribe(this, next);
    }
  }

  DateTime now() => (widget.now?.call() ?? DateTime.now()).toUtc();
  DateTime day(DateTime date) {
    final local = date.toUtc().add(const Duration(hours: 8));
    return DateTime.utc(local.year, local.month, local.day);
  }

  bool get valid {
    if (image == null ||
        updated == null ||
        imageAccount != widget.account ||
        imageKind != kind) {
      return false;
    }
    final age = now().difference(updated!);
    return !age.isNegative &&
        age < const Duration(minutes: 5) &&
        day(now()) == day(updated!);
  }

  void clearImage() {
    image = null;
    updated = null;
    imageAccount = null;
    imageKind = null;
  }

  void invalidate() {
    generation++;
    timer?.cancel();
    setState(() {
      clearImage();
      error = null;
    });
    pending = loading && active;
    if (active) {
      brighten();
      refresh();
    } else {
      restore();
    }
  }

  @override
  void didPushNext() {
    covered = true;
    active = false;
    invalidate();
  }

  @override
  void didPopNext() {
    covered = false;
    active = foreground && !sessionCleared;
    invalidate();
  }

  Future<void> brighten() => brightnessTask = brightnessTask.then((_) async {
    if (!mounted || !active || sessionCleared) return;
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(1);
    } catch (_) {}
  });

  Future<void> restore() => brightnessTask = brightnessTask.then((_) async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  });

  DateTime taipei() => now().add(const Duration(hours: 8));
  Future<void> refresh() async {
    if (sessionCleared || !active || !mounted || loading) return;
    final request = generation;
    final epoch = CampusSession.instance.coordinator.epoch;
    final start = now();
    final account = widget.account;
    final requestedKind = kind;
    setState(() {
      loading = true;
      if (!valid) clearImage();
      error = null;
    });
    try {
      final bytes = await repository.image(account, requestedKind);
      if (!mounted || request != generation || !active) return;
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted || request != generation || !active) return;
      CampusSession.instance.coordinator.requireCurrent(epoch);
      if (day(now()) != day(start) ||
          now().difference(start) >= const Duration(minutes: 5)) {
        pending = true;
        return;
      }
      setState(() {
        image = bytes;
        updated = start;
        imageAccount = account;
        imageKind = requestedKind;
      });
    } catch (_) {
      if (!mounted || request != generation || !active) return;
      setState(() {
        if (!valid) clearImage();
        error = image == null ? '暫時無法取得圖碼，檢查網路後再試一次。' : '更新失敗，目前的圖碼仍有效。';
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
        if (pending && active && !sessionCleared) {
          pending = false;
          refresh();
        } else {
          schedule();
        }
      }
    }
  }

  void schedule() {
    timer?.cancel();
    if (!mounted || !active || sessionCleared) return;
    final now = taipei();
    final midnight = DateTime.utc(now.year, now.month, now.day + 1);
    final delay = midnight.difference(now);
    final remaining = updated == null
        ? const Duration(minutes: 5)
        : updated!.add(const Duration(minutes: 5)).difference(this.now());
    final wait = delay < remaining ? delay : remaining;
    timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (!mounted || !active) return;
      setState(() {
        if (!valid) clearImage();
      });
      if (loading) pending = true;
      refresh();
    });
  }

  @override
  void didUpdateWidget(covariant LibraryScreen old) {
    super.didUpdateWidget(old);
    if (old.account != widget.account) invalidate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (sessionCleared) return;
    foreground = state == AppLifecycleState.resumed;
    active = foreground && !covered;
    invalidate();
  }

  @override
  void dispose() {
    CampusSession.instance.unregisterCleanup(clearSession);
    libraryRouteObserver.unsubscribe(this);
    generation++;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    restore();
    super.dispose();
  }

  Future<void> clearSession() async {
    sessionCleared = true;
    generation++;
    timer?.cancel();
    active = false;
    if (mounted) {
      setState(() {
        image = null;
        updated = null;
        error = null;
      });
    }
    await restore();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final entrance = kind == LibraryCodeKind.entrance;
    final account = widget.account;
    return NiuScrollPage(
      title: '圖書館',
      children: [
        NiuSegmented<LibraryCodeKind>(
          segments: const [
            (LibraryCodeKind.entrance, '入館 QR Code'),
            (LibraryCodeKind.borrowing, '借書條碼'),
          ],
          value: kind,
          onChanged: (value) {
            if (kind == value) return;
            kind = value;
            invalidate();
          },
        ),
        const SizedBox(height: NiuSpacing.xxl),
        NiuCard(
          padding: const EdgeInsets.all(NiuSpacing.xl),
          child: Column(
            children: [
              Text(
                entrance ? '入館 QR Code' : '借書條碼',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: NiuSpacing.xs),
              Text(
                entrance ? '對準入口閘門的掃描器，只限今天使用' : '借書時出示給櫃台人員',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: NiuSpacing.xl),
              if (image != null)
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: entrance ? 420 : 700),
                    child: AspectRatio(
                      aspectRatio: entrance ? 1 : 2.2,
                      child: DecoratedBox(
                        key: const ValueKey('library-code-surface'),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(NiuRadius.lg),
                          border: Border.all(color: colors.hairline),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(NiuSpacing.lg),
                          child: Center(
                            child: Image.memory(
                              image!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.contain,
                              gaplessPlayback: false,
                              filterQuality: FilterQuality.none,
                              semanticLabel: entrance ? '入館 QR Code' : '借書條碼',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                AspectRatio(
                  aspectRatio: entrance ? 1.4 : 2.2,
                  child: NiuWell(
                    child: Center(
                      child: !active
                          ? Text(
                              '回到 App 後會重新取得',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            )
                          : loading
                          ? const NiuLoading(message: '正在取得', compact: true)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  entrance ? NiuIcons.qr : NiuIcons.barcode,
                                  size: 36,
                                  color: colors.inkTertiary,
                                ),
                                const SizedBox(height: NiuSpacing.sm),
                                Text('還沒有圖碼', style: theme.textTheme.bodySmall),
                              ],
                            ),
                    ),
                  ),
                ),
              const SizedBox(height: NiuSpacing.lg),
              Text(
                updated == null
                    ? account
                    : '$account · ${formatTaipeiClock(updated!)} 更新',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: NiuSpacing.lg),
          NiuBanner(
            tone: image == null ? NiuTone.error : NiuTone.warning,
            message: error!,
          ),
        ],
        const SizedBox(height: NiuSpacing.xl),
        FilledButton.tonal(
          onPressed: active && !loading ? refresh : null,
          child: Text(loading ? '更新中' : '重新整理'),
        ),
        const SizedBox(height: NiuSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(NiuIcons.brightness, size: 16, color: colors.inkTertiary),
            const SizedBox(width: NiuSpacing.xs),
            Flexible(
              child: Text(
                '已調到最亮方便掃描，每 5 分鐘自動更新',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ],
        ),
        NiuSection(
          title: '更多服務',
          child: NiuGroup(
            children: [
              NiuRow(
                title: '設備預約',
                subtitle: '研究小間、討論室與 Switch',
                icon: Icons.meeting_room_outlined,
                hue: NiuHue.indigo,
                onTap: () => GoRouter.of(context).push('/library/spaces'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
