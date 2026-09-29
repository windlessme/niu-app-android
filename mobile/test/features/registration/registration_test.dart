import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/registration/certificate_service.dart';
import 'package:niu_mobile/features/registration/registration_data.dart';
import 'package:niu_mobile/features/registration/registration_screen.dart';

void main() {
  RegistrationData data({String rowOwner = 'b1234567'}) =>
      RegistrationData.fromJson({
        'student': 'B1234567',
        'printable': true,
        'rows': [
          {'學號': rowOwner, '註冊學年期': '1151', '註冊狀態': '校方原文', '學雜費': 0},
        ],
      });

  test(
    'certificate identity requires account, query identity and every row',
    () {
      expect(data().belongsTo('b1234567'), isTrue);
      expect(data().belongsTo(null), isFalse);
      expect(data().belongsTo('other'), isFalse);
      expect(data(rowOwner: 'other').belongsTo('b1234567'), isFalse);
      expect(
        RegistrationData.fromJson({
          'student': 'b1234567',
        }).belongsTo('b1234567'),
        isFalse,
      );
    },
  );

  test('missing and numeric status are not converted to success', () {
    expect(RegistrationData.display(null), '-');
    expect(RegistrationData.display('null'), '-');
    expect(RegistrationData.display('  '), '-');
    expect(RegistrationData.display(0), '0');
  });

  test('HTML login responses and redirects are never PDFs', () {
    final pdf = '%PDF-1.7'.codeUnits;
    expect(isCertificatePdf(200, 'application/pdf', pdf), isTrue);
    expect(
      isCertificatePdf(200, 'application/pdf; charset=binary', pdf),
      isTrue,
    );
    expect(isCertificatePdf(302, 'application/pdf', pdf), isFalse);
    expect(isCertificatePdf(200, 'text/html', pdf), isFalse);
    expect(
      isCertificatePdf(200, 'application/pdf', '<html>'.codeUnits),
      isFalse,
    );
    expect(isCertificatePdf(200, 'application/pdf', []), isFalse);
  });

  testWidgets('dashboard exposes both actions and raw school status', (
    tester,
  ) async {
    var viewed = false;
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RegistrationDashboard(
            data: data(),
            onView: () => viewed = true,
            onSave: () => saved = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('瀏覽 PDF'));
    await tester.tap(find.text('下載 PDF'));
    expect(viewed, isTrue);
    expect(saved, isTrue);
    expect(find.text('校方原文'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('-'), findsWidgets);
  });
}
