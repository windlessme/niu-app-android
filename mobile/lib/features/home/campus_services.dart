import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/shared.dart';

/// Home's service catalogue; one place for names, icons and colours.
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
  static const mail = CampusService(
    '校園信箱',
    '收信、寫信與附件',
    Icons.mail_rounded,
    NiuHue.blue,
    '/mail',
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

  static const postal = CampusService(
    '郵件包裹',
    '收件與領取狀態',
    Icons.inventory_2_rounded,
    NiuHue.amber,
    '/postal',
  );

  static const home = [
    mail,
    grades,
    library,
    calendar,
    graduation,
    leave,
    events,
    registration,
    postal,
  ];
}

const _tabRoutes = {'/', '/schedule', '/moodle'};

/// Tabs switch in place; every other service is pushed above the shell.
void openCampusService(BuildContext context, CampusService service) =>
    _tabRoutes.contains(service.route)
    ? GoRouter.of(context).go(service.route)
    : GoRouter.of(context).push(service.route);
