import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/events/events_screen.dart';

void main() {
  List<String> labels(String raw) =>
      EventCredit.parse(raw).map((c) => c.label).toList();

  test('school 多元認證 text becomes category and hours', () {
    expect(labels('專業進取（已認證，3 小時）'), ['專業進取　3 小時']);
    expect(labels('多元成長(已認證,2小時)'), ['多元成長　2 小時']);
    expect(labels('專業進取（已認證，1.5 小時）、多元成長（已認證，2 小時）'), [
      '專業進取　1.5 小時',
      '多元成長　2 小時',
    ]);
    expect(labels('服務學習'), ['服務學習']);
    expect(labels('2 小時'), ['2 小時']);
    expect(labels(''), isEmpty);
    expect(labels('-'), isEmpty);
    expect(EventCredit.parse('多元成長(已認證,2小時)').single.category, '多元成長');
  });
}
