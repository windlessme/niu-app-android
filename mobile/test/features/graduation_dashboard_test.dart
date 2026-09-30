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
  testWidgets('dashboard stays plain: no status verdicts or filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraduationDashboard(
            data: GraduationData.fromJson({
              'diverseHours': ['12', '20', '20', '20', '5', '20', '0', '40'],
              'creditRequired': ['128', '96'],
              'englishAbility': '已通過',
              'physicalFitness': '尚未檢測',
              'creditCourse': '',
            }),
          ),
        ),
      ),
    );
    for (final word in ['尚差', '已完成', '未完成', '待處理']) {
      expect(find.textContaining(word), findsNothing);
    }
    expect(find.text('12 / 20'), findsOneWidget);
    expect(find.text('已通過'), findsOneWidget);
    expect(find.text('尚未檢測'), findsOneWidget);
    expect(find.text('學分學程'), findsNothing);
    expect(find.byType(NiuSegmented<Object>), findsNothing);
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
        await tester.scrollUntilVisible(find.text('學分學程'), 300);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('all unknown data shows a dash instead of zero progress', (
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
          .textSpan!
          .toPlainText(),
      '—',
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('尚未登錄'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
