import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../../shared/shared.dart';

/// One catalogue for every entry point, so names, icons and colours match
/// between Home and the Campus tab.
class CampusService {
  const CampusService(
    this.title,
    this.subtitle,
    this.icon,
    this.hue,
    this.route,
  );
  final String title, subtitle;
  final IconData icon;
  final NiuHue hue;
  final String route;
}

abstract final class CampusServices {
  static const moodle = CampusService(
    'M 園區',
    '課程、公告與作業',
    NiuIcons.moodle,
    NiuHue.blue,
    '/moodle',
  );
  static const attendance = CampusService(
    '點名',
    '掃描課堂 QR Code 簽到',
    NiuIcons.attendance,
    NiuHue.blue,
    '/attendance',
  );
  static const grades = CampusService(
    '成績',
    '歷年成績與 GPA',
    NiuIcons.grades,
    NiuHue.orange,
    '/grades',
  );
  static const graduation = CampusService(
    '畢業門檻',
    '英文、體適能與多元學習',
    NiuIcons.graduation,
    NiuHue.teal,
    '/graduation',
  );
  static const calendar = CampusService(
    '行事曆',
    '學期重要日程',
    NiuIcons.calendar,
    NiuHue.red,
    '/calendar',
  );
  static const library = CampusService(
    '圖書館',
    '入館碼與借書證',
    NiuIcons.library,
    NiuHue.indigo,
    '/library',
  );
  static const events = CampusService(
    '活動報名',
    '校園活動與我的報名',
    NiuIcons.events,
    NiuHue.green,
    '/events',
  );
  static const leave = CampusService(
    '請假',
    '請假紀錄與審核進度',
    NiuIcons.leave,
    NiuHue.pink,
    '/leave',
  );
  static const registration = CampusService(
    '在學證明',
    '註冊狀態與證明文件',
    NiuIcons.registration,
    NiuHue.cyan,
    '/registration',
  );
  static const settings = CampusService(
    '設定',
    '帳號、外觀與關於',
    NiuIcons.settings,
    NiuHue.gray,
    '/settings',
  );

  static const home = [
    moodle,
    grades,
    library,
    calendar,
    graduation,
    leave,
    events,
    registration,
  ];

  static const groups = [
    ('課業', [attendance, grades, graduation]),
    ('校園生活', [calendar, library, events]),
    ('行政', [leave, registration]),
    ('App', [settings]),
  ];
}

const _tabRoutes = {'/', '/schedule', '/moodle', '/campus'};

/// Tabs switch in place; every other service is pushed above the shell.
void openCampusService(BuildContext context, CampusService service) =>
    _tabRoutes.contains(service.route)
    ? GoRouter.of(context).go(service.route)
    : GoRouter.of(context).push(service.route);
