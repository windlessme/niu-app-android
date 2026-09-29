import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/graduation/graduation_dashboard.dart';
import 'package:niu_mobile/features/graduation/graduation_presentation.dart';
import 'package:niu_mobile/features/graduation/graduation_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

GraduationPresentation present(Map<String, dynamic> json) {
  final data = GraduationData.fromJson(json);
  return GraduationPresentation(
    hours: data.hours,
    credits: data.credits,
    english: data.english,
    fitness: data.fitness,
    program: data.program,
  );
}

void main() {
  testWidgets('estimation details expand immediately with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: GraduationDashboard(data: GraduationData.fromJson({})),
          ),
        ),
      ),
    );
    expect(find.textContaining('完成項目依'), findsNothing);
    await tester.scrollUntilVisible(find.text('計算方式與資料說明'), 300);
    await tester.tap(find.text('計算方式與資料說明'));
    await tester.pump();
    expect(find.textContaining('完成項目依'), findsOneWidget);
    final expandedSize = tester.getSize(find.byType(ExpansionTile));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.getSize(find.byType(ExpansionTile)), expandedSize);
    expect(tester.takeException(), isNull);
  });

  test('unknown data is not zero progress', () {
    final model = present({});
    expect(model.progress, isNull);
    expect(model.measuredCount, 0);
    expect(model.missingCount, 8);
  });

  test(
    'remaining quantities clamp and preserve unknown or excluded values',
    () {
      expect(
        GraduationRequirement.quantity('credits', '64', '128').remaining,
        64,
      );
      expect(GraduationRequirement.quantity('hours', '12', '10').remaining, 0);
      expect(
        GraduationRequirement.quantity('hours', '1.5', '3').remaining,
        1.5,
      );
      expect(
        GraduationRequirement.quantity('hours', '', '10').remaining,
        isNull,
      );
      expect(
        GraduationRequirement.quantity('hours', '10', '').remaining,
        isNull,
      );
      expect(
        GraduationRequirement.quantity('hours', '10', '不計入').remaining,
        isNull,
      );
      expect(
        GraduationRequirement.quantity('hours', '10', '0').remaining,
        isNull,
      );
      final model = present({
        'creditRequired': ['128', '130'],
        'englishAbility': '尚未檢測',
      });
      expect(model.completedCount, 1);
      expect(model.remainingCount, 1);
      expect(model.missingCount, 6);
      expect(model.program.needsAttention, isTrue);
    },
  );

  test('credits are required then earned and retain fractional progress', () {
    final model = present({
      'creditRequired': ['128', '3'],
    });
    expect(model.credits.earned, 3);
    expect(model.credits.required, 128);
    expect(model.progress, 3 / 128);
    expect(model.measuredCount, 1);
    expect(model.missingCount, 7);
  });

  test('four values and zero requirements are non-applicable, not missing', () {
    final model = present({
      'diverseHours': ['1', '2', '3', '4'],
    });
    expect(model.hours.every((r) => r.nonApplicable), isTrue);
    expect(model.missingCount, 4);
    expect(model.progress, isNull);
    final zero = GraduationRequirement.quantity('hours', '', '0');
    expect(zero.nonApplicable, isTrue);
    expect(zero.progress, isNull);
  });

  test('known normalized requirements are averaged with capped completion', () {
    final model = present({
      'diverseHours': ['20', '10', '', '', '', '', '', ''],
      'creditRequired': ['128', '64'],
      'englishAbility': '已通過',
      'physicalFitness': '尚未檢測',
      'creditCourse': '學程資料待確認',
    });
    expect(model.measuredCount, 4);
    expect(model.progress, .625);
    expect(model.program.status, GraduationStatus.unknown);
    expect(
      GraduationRequirement.qualification('test', '未通過').status,
      GraduationStatus.failed,
    );
    expect(
      GraduationRequirement.qualification('test', '尚未登錄').status,
      GraduationStatus.unknown,
    );
    expect(
      GraduationRequirement.quantity('test', 'NaN', '10').progress,
      isNull,
    );
  });

  for (final dark in [false, true]) {
    testWidgets(
      'dashboard wraps at 320px and 2x text (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? NiuTheme.dark : NiuTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: GraduationDashboard(
                data: GraduationData.fromJson({
                  'diverseHours': ['1', '2', '3', '4'],
                  'creditRequired': ['128', '3'],
                  'englishAbility': '尚未檢測',
                  'physicalFitness': '未通過',
                  'creditCourse': '校方學分學程資料尚待確認，請以校方審核為準',
                }),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('3 / 128 學分'), 300);
        expect(find.text('尚差 125 學分'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('學分學程'), 200);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('計算方式與資料說明'), 200);
        await tester.tap(find.text('計算方式與資料說明'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('all unknown hero shows unknown count without a progress bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: Scaffold(
          body: GraduationDashboard(data: GraduationData.fromJson({})),
        ),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('graduation-overall')))
          .data,
      '已完成 0 項',
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('資料待確認 8 項'), findsOneWidget);
    expect(find.textContaining('非校方畢業資格審核結果'), findsNothing);
    await tester.tap(find.text('待處理'));
    await tester.pumpAndSettle();
    expect(find.text('包含尚未完成及資料待確認的項目'), findsOneWidget);
    expect(find.text('— / — 學分'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '已完成'));
    await tester.pumpAndSettle();
    expect(find.text('目前沒有符合的項目'), findsOneWidget);
  });
}
