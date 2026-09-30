import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// The school's three DL_Status values.
enum PostalStatus {
  waiting('', '未領取'),
  collected('Y', '已領取'),
  returned('R', '退件');

  const PostalStatus(this.value, this.label);
  final String value, label;
}

class PostalQuery {
  const PostalQuery({
    this.name = '',
    this.phone = '',
    this.trackingNumber = '',
    this.status = PostalStatus.waiting,
  });
  final String name, phone, trackingNumber;
  final PostalStatus status;

  PostalQuery get normalized => PostalQuery(
    name: name.trim(),
    phone: phone.trim(),
    trackingNumber: trackingNumber.trim(),
    status: status,
  );

  bool get canSearch {
    final q = normalized;
    return q.name.isNotEmpty ||
        q.phone.isNotEmpty ||
        q.trackingNumber.isNotEmpty;
  }
}

class PostalRecord {
  const PostalRecord({
    required this.sequence,
    required this.receivedDate,
    required this.trackingNumber,
    required this.unit,
    required this.recipient,
    required this.category,
    required this.quantity,
    required this.signature,
    required this.completedDate,
    required this.note,
    required this.status,
  });
  final String sequence, receivedDate, trackingNumber, unit, recipient;
  final String category, quantity, signature, completedDate, note;
  final PostalStatus status;

  String get id =>
      [sequence, receivedDate, trackingNumber, recipient, unit].join('|');
}

class PostalPage {
  const PostalPage({
    required this.records,
    required this.query,
    required this.pageIndex,
    required this.pageCount,
    this.nextForm,
  });
  final List<PostalRecord> records;
  final PostalQuery query;
  final int pageIndex, pageCount;

  /// Fresh WebForms state that replays the grid's own 「下一頁」 control.
  final Map<String, String>? nextForm;
}

class PostalException implements Exception {
  const PostalException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _headers = [
  '序號',
  '收件日期',
  '郵件號碼',
  '收件單位',
  '收件者',
  '類別',
  '數量',
  '是否簽收',
  '簽收(退件)日期',
  '備註',
];

/// Parser for the public ccsys2 GA/Postal WebForms page (same contract as
/// iOS). A changed page is an error, never an empty result.
abstract final class PostalHtml {
  static String _text(dom.Element e) =>
      e.text.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static Map<String, String> form(String source) {
    final doc = html.parse(source);
    final fields = <String, String>{};
    final names = <String>{};
    for (final input in doc.querySelectorAll('input')) {
      final name = input.attributes['name'];
      if (name == null) continue;
      names.add(name);
      if ((input.attributes['type'] ?? '').toLowerCase() == 'hidden') {
        fields[name] = input.attributes['value'] ?? '';
      }
    }
    if (!names.contains('Key_name') ||
        !names.contains('Btn_Search') ||
        (fields['__VIEWSTATE'] ?? '').isEmpty ||
        (fields['__EVENTVALIDATION'] ?? '').isEmpty) {
      throw const PostalException('查詢頁面格式已變更');
    }
    return fields;
  }

  static Map<String, String> searchForm(
    Map<String, String> fields,
    PostalQuery query,
  ) => {
    ...fields,
    '__EVENTTARGET': '',
    '__EVENTARGUMENT': '',
    'DL_Status': query.status.value,
    'CB_Kind': '',
    'CB_Unit': '',
    'RB_Date': '0',
    'Key_name': query.name,
    'Key_Phone': query.phone,
    'Key_BillID': query.trackingNumber,
    'Btn_Search': '開始查詢',
  };

  static PostalPage page(String source, PostalQuery query) {
    final fields = form(source);
    final doc = html.parse(source);
    final grid = doc.getElementById('RadGrid1_ctl00');
    if (grid == null) throw const PostalException('查詢結果格式已變更');
    final headers = grid.querySelectorAll('th').map(_text).take(10).toList();
    if (headers.length != 10 ||
        [
          for (var i = 0; i < 10; i++) headers[i] == _headers[i],
        ].contains(false)) {
      throw const PostalException('查詢結果格式已變更');
    }
    final records = <PostalRecord>[];
    var explicitlyEmpty = false;
    for (final row in grid.querySelectorAll('tr')) {
      final classes = row.classes;
      if (classes.contains('rgNoRecords')) {
        explicitlyEmpty = _text(row).contains('查無資料');
      }
      if (!classes.contains('rgRow') && !classes.contains('rgAltRow')) continue;
      final cells = row.children
          .where((c) => c.localName == 'td')
          .map(_text)
          .toList();
      if (cells.length != 10 ||
          cells[0].isEmpty ||
          cells[1].isEmpty ||
          cells[4].isEmpty) {
        throw const PostalException('查詢結果格式已變更');
      }
      records.add(
        PostalRecord(
          sequence: cells[0],
          receivedDate: cells[1],
          trackingNumber: cells[2],
          unit: cells[3],
          recipient: cells[4],
          category: cells[5],
          quantity: cells[6],
          signature: cells[7],
          completedDate: cells[8],
          note: cells[9],
          status: query.status,
        ),
      );
    }
    if (records.isEmpty != explicitlyEmpty ||
        records.map((r) => r.id).toSet().length != records.length) {
      throw const PostalException('查詢結果格式已變更');
    }
    final encoded = RegExp(
      r'"_gridTableViewsData"\s*:\s*("(?:\\.|[^"\\])*")',
    ).firstMatch(source)?.group(1);
    if (encoded == null) throw const PostalException('查詢結果格式已變更');
    final grids = jsonDecode(jsonDecode(encoded) as String) as List;
    final meta = grids.whereType<Map>().firstWhere(
      (g) => g['ClientID'] == 'RadGrid1_ctl00',
      orElse: () => throw const PostalException('查詢結果格式已變更'),
    );
    final count = meta['PageCount'], index = meta['CurrentPageIndex'];
    if (count is! int ||
        index is! int ||
        count < 0 ||
        index < 0 ||
        index >= (count < 1 ? 1 : count)) {
      throw const PostalException('查詢結果格式已變更');
    }
    Map<String, String>? next;
    if (index + 1 < count) {
      for (final input in grid.querySelectorAll('input.rgPageNext')) {
        final name = input.attributes['name'];
        if (name == null ||
            input.attributes.containsKey('disabled') ||
            (input.attributes['type'] ?? '').toLowerCase() != 'submit') {
          continue;
        }
        next = searchForm(fields, query)
          ..remove('Btn_Search')
          ..[name] = input.attributes['value'] ?? '';
        break;
      }
    }
    return PostalPage(
      records: records,
      query: query,
      pageIndex: index,
      pageCount: count < 1 ? 1 : count,
      nextForm: next,
    );
  }
}
