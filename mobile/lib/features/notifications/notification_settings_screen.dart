import 'package:flutter/material.dart';

import '../../core/platform/schedule_gateway.dart';
import '../../shared/shared.dart';
import 'campus_notifications.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    required this.notifications,
    this.gateway = const ScheduleGateway(),
  });
  final CampusNotifications notifications;
  final ScheduleGateway gateway;
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool assignments = false, calendar = false, classes = false;
  bool classNow = false;
  bool loaded = false, busy = false, refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = widget.gateway.reminderStatus();
      final values = await Future.wait([
        widget.notifications.enabled(CampusNotifications.assignmentsKey),
        widget.notifications.enabled(CampusNotifications.calendarKey),
        status.then((s) => s.enabled),
        status.then((s) => s.classNow),
      ]);
      if (!mounted) return;
      setState(() {
        assignments = values[0];
        calendar = values[1];
        classes = values[2];
        classNow = values[3];
      });
    } catch (_) {
      /* Switches stay off when the device cannot report them. */
    } finally {
      if (mounted) setState(() => loaded = true);
    }
  }

  Future<bool> _permitted() async {
    try {
      if (await widget.gateway.requestNotificationPermission()) return true;
    } catch (_) {}
    if (mounted) showNiuMessage(context, '請先在系統設定允許 NIU-Life 傳送通知');
    return false;
  }

  Future<void> _toggle(
    bool value,
    void Function(bool) apply,
    Future<void> Function(bool) save,
    String failure,
  ) async {
    if (busy) return;
    if (value && !await _permitted()) return;
    setState(() {
      busy = true;
      apply(value);
    });
    try {
      await save(value);
    } catch (_) {
      if (mounted) showNiuMessage(context, failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      await widget.notifications.refresh();
      if (mounted) showNiuMessage(context, '通知已更新');
    } catch (_) {
      if (mounted) showNiuMessage(context, '部分通知沒有更新，請確認登入狀態後再試一次');
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  /// A setting row that toggles from anywhere on it, not just the switch.
  Widget _switchRow({
    required IconData icon,
    required NiuHue hue,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final enabled = loaded && !busy;
    return NiuRow(
      icon: icon,
      hue: hue,
      title: title,
      subtitle: subtitle,
      chevron: false,
      onTap: enabled ? () => onChanged(!value) : null,
      trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
    );
  }

  @override
  Widget build(BuildContext context) => NiuScrollPage(
    title: '通知設定',
    children: [
      NiuGroup(
        children: [
          _switchRow(
            icon: Icons.assignment_turned_in_outlined,
            hue: NiuHue.blue,
            title: '作業死線通知',
            subtitle: 'M 園區作業截止前一天提醒',
            value: assignments,
            onChanged: (value) => _toggle(
              value,
              (v) => assignments = v,
              (v) => widget.notifications.setEnabled(
                CampusNotifications.assignmentsKey,
                v,
              ),
              '已儲存設定，但暫時無法取得 M 園區作業',
            ),
          ),
          _switchRow(
            icon: Icons.event_note_outlined,
            hue: NiuHue.pink,
            title: '重要日期通知',
            subtitle: '學年行事曆重要日期前一天提醒',
            value: calendar,
            onChanged: (value) => _toggle(
              value,
              (v) => calendar = v,
              (v) => widget.notifications.setEnabled(
                CampusNotifications.calendarKey,
                v,
              ),
              '已儲存設定，但暫時無法讀取行事曆',
            ),
          ),
          _switchRow(
            icon: NiuIcons.notifications,
            hue: NiuHue.orange,
            title: '上課前提醒',
            subtitle: '每週固定於上課前 10 分鐘提醒',
            value: classes,
            onChanged: (value) => _toggle(value, (v) => classes = v, (v) async {
              try {
                await widget.notifications.setClassReminders(v);
              } catch (_) {
                if (mounted) setState(() => classes = !v);
                rethrow;
              }
            }, '無法開啟上課提醒，請先開啟課表並確認已連線'),
          ),
          _switchRow(
            icon: Icons.timelapse_rounded,
            hue: NiuHue.teal,
            title: '上課中通知',
            subtitle: '上課時顯示課名、教室與下課倒數',
            value: classNow,
            onChanged: (value) =>
                _toggle(value, (v) => classNow = v, (v) async {
                  try {
                    await widget.notifications.setClassNow(v);
                  } catch (_) {
                    if (mounted) setState(() => classNow = !v);
                    rethrow;
                  }
                }, '無法開啟上課中通知，請先開啟課表並確認已連線'),
          ),
        ],
      ),
      const SizedBox(height: NiuSpacing.lg),
      NiuGroup(
        children: [
          NiuRow(
            icon: Icons.sync_rounded,
            hue: NiuHue.gray,
            title: '立即更新通知',
            subtitle: refreshing ? '更新中…' : '重新同步作業、行事曆與課表提醒',
            chevron: false,
            onTap: refreshing ? null : _refresh,
            trailing: refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ],
      ),
    ],
  );
}
