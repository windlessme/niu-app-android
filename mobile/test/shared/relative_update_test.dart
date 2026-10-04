import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/shared/relative_update_text.dart';

void main() {
  test('freshness is human readable across Taipei midnight', () {
    final now = DateTime.utc(2026, 9, 29, 4);
    expect(formatRelativeUpdate(null, now: now), '尚未更新');
    expect(formatRelativeUpdate(now, now: now), '剛剛更新');
    expect(
      formatRelativeUpdate(now.subtract(const Duration(minutes: 5)), now: now),
      '5 分鐘前更新',
    );
    expect(
      formatRelativeUpdate(DateTime.utc(2026, 9, 29, 2, 48), now: now),
      '今天 10:48 更新',
    );
    expect(
      formatRelativeUpdate(DateTime.utc(2026, 9, 28, 15), now: now),
      '昨天更新',
    );
    expect(
      formatRelativeUpdate(now.subtract(const Duration(days: 5)), now: now),
      '5 天前更新',
    );
  });
}
