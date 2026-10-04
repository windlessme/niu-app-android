import '../../core/demo/demo_data.dart';
import '../../core/demo/demo_documents.dart';
import 'event_actions.dart';
import 'event_models.dart';

/// Registrations made during the demo, kept in memory only.
abstract final class DemoEvents {
  static final registered = <String>{'11188'};

  static List<Map<String, dynamic>> list({required bool applied}) {
    final all = [DemoData.registeredEvent, ...DemoData.events];
    return [
      for (final event in all)
        if (applied == registered.contains(event['id']))
          {...event, if (applied) 'status': '報名成功'},
    ];
  }
}

class DemoEventActions implements EventActions {
  @override
  Future<EventActionResult> register(CampusEvent event) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    DemoEvents.registered.add(event.id);
    return EventActionResult(true, demoNote('報名成功'));
  }

  @override
  Future<EventActionResult> cancel(CampusEvent event) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    DemoEvents.registered.remove(event.id);
    return EventActionResult(true, demoNote('已取消報名'));
  }

  @override
  Future<EventRegistrationForm> loadForm(CampusEvent event) async =>
      EventRegistrationForm.fromJson({
        'tel': '0912345678',
        'email': 'demo@example.com',
        'memo': '',
        'food': [
          {'value': '1', 'label': '葷食', 'checked': true},
          {'value': '2', 'label': '素食', 'checked': false},
        ],
        'proof': [
          {'value': '1', 'label': '需要多元認證', 'checked': true},
          {'value': '0', 'label': '不需要', 'checked': false},
        ],
        'info': [
          ['身份', '學生'],
          ['班級', '資工三'],
          ['學號', 'niulifedemo'],
          ['姓名', DemoData.studentName],
        ],
      });

  @override
  Future<EventActionResult> save(
    CampusEvent event, {
    required String tel,
    required String email,
    required String memo,
    String? food,
    String? proof,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return EventActionResult(true, demoNote('已儲存修改'));
  }

  @override
  Future<List<CampusEvent>> registrations() async => [
    for (final e in DemoEvents.list(applied: true)) CampusEvent.fromJson(e),
  ];
}
