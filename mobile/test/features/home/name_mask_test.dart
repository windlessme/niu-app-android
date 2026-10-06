import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/home/name_mask.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('keeps the surname, including compound ones', () {
    expect(NameMask.hide('王小明'), '王同學');
    expect(NameMask.hide('歐陽娜娜'), '歐陽同學');
    expect(NameMask.hide('歐陽'), '歐同學');
    expect(NameMask.hide('  '), '同學');
  });

  testWidgets('the eye hides the name and the choice is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    NameMask.masked.value = null;
    await NameMask.load();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              MaskedName(name: '王小明', prefix: '午安，'),
              NameMaskButton(),
            ],
          ),
        ),
      ),
    );
    expect(find.text('午安，王小明'), findsOneWidget);
    await tester.tap(find.byTooltip('隱藏完整姓名'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('午安，王同學'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(NameMask.key),
      isTrue,
    );
    await tester.tap(find.byTooltip('顯示完整姓名'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('午安，王小明'), findsOneWidget);
  });

  testWidgets('the name stays hidden until the choice is read', (tester) async {
    NameMask.masked.value = null;
    await tester.pumpWidget(const MaterialApp(home: MaskedName(name: '王小明')));
    expect(find.text('王同學'), findsOneWidget);
  });
}
