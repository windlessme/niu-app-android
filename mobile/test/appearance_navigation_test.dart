import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niu_mobile/app/app.dart';

void main() {
  testWidgets(
    'settings reflects appearance immediately and persists selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const ProviderScope(child: NiuApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.text('深色'),
                    matching: find.byWidgetPredicate(
                      (w) => w is Semantics && w.properties.selected != null,
                    ),
                  )
                  .first,
            )
            .properties
            .selected,
        isTrue,
      );
      expect(
        Theme.of(tester.element(find.text('深色'))).brightness,
        Brightness.dark,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('appearance'),
        'dark',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
