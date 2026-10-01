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
  bool loaded = false, busy = false, refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        widget.notifications.enabled(CampusNotifications.assignmentsKey),
        widget.notifications.enabled(CampusNotifications.calendarKey),
        widget.gateway.reminderStatus().then((s) => s.enabled),
      ]);
      if (!mounted) return;
      setState(() {
        assignments = values[0];
        calendar = values[1];
        classes = values[2];
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

  Widget _switch(bool value, ValueChanged<bool> onChanged) =>
      Switch(value: value, onChanged: loaded && !busy ? onChanged : null);

  @override
  Widget build(BuildContext context) => NiuScrollPage(
    title: '通知設定',
    children: [
      NiuGroup(
        children: [
          NiuRow(
            icon: Icons.assignment_turned_in_outlined,
            hue: NiuHue.blue,
            title: '作業死線通知',
            subtitle: 'M 園區作業截止前一天提醒',
            trailing: _switch(
              assignments,
              (value) => _toggle(
                value,
                (v) => assignments = v,
                (v) => widget.notifications.setEnabled(
                  CampusNotifications.assignmentsKey,
                  v,
                ),
                '已儲存設定，但暫時無法取得 M 園區作業',
              ),
            ),
          ),
          NiuRow(
            icon: Icons.event_note_outlined,
            hue: NiuHue.pink,
            title: '重要日期通知',
            subtitle: '學年行事曆重要日期前一天提醒',
            trailing: _switch(
              calendar,
              (value) => _toggle(
                value,
                (v) => calendar = v,
                (v) => widget.notifications.setEnabled(
                  CampusNotifications.calendarKey,
                  v,
                ),
                '已儲存設定，但暫時無法讀取行事曆',
              ),
            ),
          ),
          NiuRow(
            icon: NiuIcons.notifications,
            hue: NiuHue.orange,
            title: '上課前提醒',
            subtitle: '每週固定於上課前 10 分鐘提醒',
            trailing: _switch(
              classes,
              (value) => _toggle(value, (v) => classes = v, (v) async {
                try {
                  await widget.notifications.setClassReminders(v);
                } catch (_) {
                  if (mounted) setState(() => classes = !v);
                  rethrow;
                }
              }, '無法開啟上課提醒，請先開啟課表並確認已連線'),
            ),
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
