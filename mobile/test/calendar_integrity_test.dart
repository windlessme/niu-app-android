import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_repository.dart';

class DamagedBundle extends CachingAssetBundle {
  DamagedBundle({this.payload});
  final Map<String, dynamic>? payload;
  @override
  Future<ByteData> load(String key) async {
    final String value;
    if (key.endsWith('index.json')) {
      value = jsonEncode({
        'schemaVersion': 1,
        'calendars': [
          {
            'academicYear': 115,
            'revision': 1,
            'path': 'years/115.json',
            'sha256': payload == null
                ? 'wrong'
                : sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
          },
        ],
      });
    } else {
      value = jsonEncode(payload ?? {});
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

void main() {
  test('matching hash cannot make invalid semester boundaries valid', () async {
    final bundle = DamagedBundle(
      payload: {
        'schemaVersion': 1,
        'academicYear': 115,
        'revision': 1,
        'timeZone': 'Asia/Taipei',
        'startDate': '2026-09-01',
        'endDate': '2027-07-31',
        'events': [],
        'sources': [],
      },
    );
    await expectLater(
      BundledCalendarRepository(bundle).load(115),
      throwsFormatException,
    );
  });

  test('invalid or reversed civil dates cannot enter a snapshot', () {
    Map<String, dynamic> event(String start, String end) => {
      'id': 'fixture',
      'title': 'Fixture',
      'startDate': start,
      'endDate': end,
      'category': 'academic',
      'note': null,
      'sourceText': 'Fixture',
    };
    expect(
      () => CalendarEvent.fromJson(event('2026-02-30', '2026-03-01')),
      throwsFormatException,
    );
    expect(
      () => CalendarEvent.fromJson(event('2026-03-02', '2026-03-01')),
      throwsFormatException,
    );
  });

  test(
    'damaged snapshot is rejected before JSON becomes calendar data',
    () async {
      await expectLater(
        BundledCalendarRepository(DamagedBundle()).load(115),
        throwsFormatException,
      );
    },
  );
}
