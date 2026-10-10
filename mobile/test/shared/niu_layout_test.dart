import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/app/app.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the gutter keeps a readable column on wide screens', (
    tester,
  ) async {
    late BuildContext context;
    Future<void> at(double width) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
    }

    await at(400);
    expect(NiuLayout.isWide(context), isFalse);
    expect(NiuLayout.gutter(context), NiuSpacing.gutter);
    await at(1000);
    expect(NiuLayout.isWide(context), isTrue);
    expect(NiuLayout.gutter(context), 140);
    expect(NiuLayout.gutter(context, maxWidth: NiuLayout.spacious), 20);
    expect(NiuLayout.page(context, top: 4).left, 140);
  });

  for (final (width, rail) in [(400.0, false), (1000.0, true)]) {
    testWidgets('tabs use a ${rail ? 'side rail' : 'bottom bar'} at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const ProviderScope(child: NiuApp()));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), rail ? findsOneWidget : findsNothing);
      expect(find.byType(NavigationBar), rail ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
