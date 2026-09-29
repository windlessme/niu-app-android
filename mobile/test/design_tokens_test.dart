import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  test('cross-platform roles retain core scale and Android transitions', () {
    expect(
      [
        NiuSpacing.xs,
        NiuSpacing.sm,
        NiuSpacing.md,
        NiuSpacing.lg,
        NiuSpacing.xxl,
        NiuSpacing.xxxl,
        NiuSpacing.x4l,
      ],
      [4, 8, 12, 16, 24, 32, 48],
    );
    expect(
      [
        NiuRadius.xsmall,
        NiuRadius.small,
        NiuRadius.medium,
        NiuRadius.large,
        NiuRadius.xlarge,
        NiuRadius.xxlarge,
      ],
      [6, 10, 14, 18, 24, 32],
    );
    expect(
      NiuTheme.dark.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<PredictiveBackPageTransitionsBuilder>(),
    );
  });
  for (final dark in [false, true]) {
    testWidgets(
      'status and filter primitives scale without overflow dark=$dark',
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
                    for (final tone in NiuStatusTone.values)
                      NiuStatusChip(label: '狀態資訊與資料更新狀態', tone: tone),
                    NiuFilterChip(
                      label: '全部',
                      selected: true,
                      onSelected: (_) {},
                    ),
                    const NiuFilterChip(label: '停用條件', selected: false),
                    const NiuInfoChip(label: '營運業者與站牌資訊', icon: NiuIcons.bus),
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
