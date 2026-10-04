import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/postal/postal_models.dart';

/// Real public page (a search with no results) and a synthetic copy with rows.
final empty = File('test/fixtures/postal_empty.html').readAsStringSync();

String withRows(List<List<String>> rows) {
  final start = empty.indexOf('<tr class="rgNoRecords">');
  final end = empty.indexOf('</tr>', start) + '</tr>'.length;
  final body = [
    for (final (i, row) in rows.indexed)
      '<tr class="${i.isEven ? 'rgRow' : 'rgAltRow'}">'
          '${row.map((c) => '<td>$c</td>').join()}</tr>',
  ].join();
  return empty.replaceRange(start, end, body);
}

void main() {
  const query = PostalQuery(name: '測試', status: PostalStatus.waiting);

  test('the live page contract yields an explicit empty result', () {
    final fields = PostalHtml.form(empty);
    expect(fields['__VIEWSTATE'], isNotEmpty);
    final form = PostalHtml.searchForm(fields, query);
    expect(form['Key_name'], '測試');
    expect(form['DL_Status'], '');
    expect(form['Btn_Search'], '開始查詢');
    final page = PostalHtml.page(empty, query);
    expect(page.records, isEmpty);
    expect(page.pageCount, 1);
    expect(page.nextForm, isNull);
  });

  test('rows become records with the searched status', () {
    final page = PostalHtml.page(
      withRows([
        ['1', '115/09/30', 'RR123', '資工系', '王同學', '包裹', '1', '否', '', ''],
        ['2', '115/10/01', 'RR456', '資工系', '王同學', '掛號', '1', '否', '', '請攜帶證件'],
      ]),
      query,
    );
    expect(page.records, hasLength(2));
    expect(page.records.last.trackingNumber, 'RR456');
    expect(page.records.last.note, '請攜帶證件');
    expect(page.records.first.status, PostalStatus.waiting);
  });

  test('a changed page is an error, never an empty success', () {
    expect(
      () => PostalHtml.page(empty.replaceAll('收件者', '收件人'), query),
      throwsA(isA<PostalException>()),
    );
    expect(
      () => PostalHtml.page(
        withRows([
          ['1', '', 'x', '', '', '', '', '', '', ''],
        ]),
        query,
      ),
      throwsA(isA<PostalException>()),
    );
    expect(
      () => PostalHtml.form('<html></html>'),
      throwsA(isA<PostalException>()),
    );
  });

  test('a query needs at least one criterion', () {
    expect(const PostalQuery().canSearch, isFalse);
    expect(const PostalQuery(name: '  ').canSearch, isFalse);
    expect(const PostalQuery(trackingNumber: 'RR1').canSearch, isTrue);
  });
}
