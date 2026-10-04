import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/events/event_models.dart';

void main() {
  test('event display cannot redirect registration to an untrusted link', () {
    final event = CampusEvent.fromJson({
      'id': 'fixture',
      'name': '活動',
      'action': 'https://example.org/collect',
      'targets': '本校在校生',
    });
    expect(event.actionUri(applied: false).host, 'ccsys.niu.edu.tw');
    expect(event.actionUri(applied: false).path, '/MvcTeam/Act/Apply/fixture');
    expect(event.actionUri(applied: true).path, '/MvcTeam/Act/RegData/fixture');
  });
  test('ended events do not offer application as an enabled action', () {
    final event = CampusEvent.fromJson({'id': 'fixture', 'status': '活動已結束'});
    expect(event.canApply, isFalse);
  });
}
