import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/shared/shared.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  test('spacing and radius scales stay on the 4pt grid', () {
    expect(
      [
        NiuSpacing.xs,
        NiuSpacing.sm,
        NiuSpacing.md,
        NiuSpacing.lg,
        NiuSpacing.xl,
        NiuSpacing.xxl,
        NiuSpacing.xxxl,
        NiuSpacing.huge,
      ],
      [4, 8, 12, 16, 20, 24, 32, 48],
    );
    expect(NiuSpacing.gutter, 20);
    expect(NiuRadius.card, 20);
    expect(NiuSize.touchTarget, greaterThanOrEqualTo(48));
    expect(
      NiuTheme.dark.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<PredictiveBackPageTransitionsBuilder>(),
    );
  });

  test('every hue and tone is readable on its surface in both modes', () {
    for (final colors in [NiuColors.light, NiuColors.dark]) {
      expect(contrast(colors.ink, colors.surface), greaterThan(12));
      expect(contrast(colors.inkSecondary, colors.surface), greaterThan(4.5));
      expect(contrast(colors.inkTertiary, colors.surface), greaterThan(3.5));
      expect(contrast(colors.accent, colors.surface), greaterThan(4.5));
      expect(contrast(colors.onAccent, colors.accent), greaterThan(4.5));
      for (final tone in [colors.success, colors.warning, colors.error]) {
        expect(contrast(tone, colors.surface), greaterThan(4.5));
      }
    }
    for (final hue in NiuHue.values) {
      expect(contrast(hue.light, NiuColors.light.surface), greaterThan(4.5));
      expect(contrast(hue.dark, NiuColors.dark.surface), greaterThan(4.5));
    }
  });

  for (final dark in [false, true]) {
    testWidgets(
      'badges, filters and banners scale without overflow dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? NiuTheme.dark : NiuTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: ListView(
                  children: [
                    for (final tone in NiuTone.values)
                      NiuBadge(label: '狀態資訊與資料更新狀態', tone: tone),
                    NiuFilterChip(
                      label: '全部',
                      selected: true,
                      onSelected: (_) {},
                    ),
                    const NiuFilterChip(label: '停用條件', selected: false),
                    const NiuTag(label: '開放時間與地點資訊', icon: NiuIcons.library),
                    NiuBanner(
                      tone: NiuTone.warning,
                      title: '校務系統需要重新登入',
                      message: '課表與個人資料仍保留在裝置上。',
                      actionLabel: '重新登入',
                      onAction: () {},
                    ),
                    NiuSegmented<int>(
                      segments: const [(0, '全部'), (1, '待處理'), (2, '已完成')],
                      value: 1,
                      onChanged: (_) {},
                    ),
                    const NiuEmpty(title: '沒有資料', message: '有新資料時會出現在這裡。'),
                    const NiuStat(
                      label: '累計',
                      value: '12',
                      unit: '節',
                      large: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(FilterChip).first).height,
          greaterThanOrEqualTo(48),
        );
      },
    );
  }
}
