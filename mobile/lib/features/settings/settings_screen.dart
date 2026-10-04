import 'package:flutter/material.dart';
import '../../core/analytics/app_analytics.dart';
import '../../core/platform/app_version.dart';
import '../notifications/campus_notifications.dart';
import '../notifications/notification_settings_screen.dart';
import '../../shared/shared.dart';
import 'credits_repository.dart';
import '../announcements/announcements_screen.dart';
import 'privacy_screen.dart';
import 'credits_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.name,
    this.username,
    this.department,
    this.grade,
    this.onLogout,
    this.onRefreshProfile,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.creditsRepository,
    this.offline = false,
    this.ssoNeedsReauthentication = false,
    this.onReconnect,
    this.onForgetSchoolLogin,
    this.notifications,
  });
  final String? name, username, department, grade;
  final Future<void> Function()? onLogout, onRefreshProfile;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final CreditsRepository? creditsRepository;
  final bool offline, ssoNeedsReauthentication;
  final VoidCallback? onReconnect;
  final Future<void> Function()? onForgetSchoolLogin;

  /// Shown only for a signed-in account; reminders need its data.
  final CampusNotifications? notifications;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String success,
    String failure,
  ) async {
    try {
      await action();
      if (context.mounted) showNiuMessage(context, success);
    } catch (_) {
      if (context.mounted) showNiuMessage(context, failure);
    }
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await confirmNiuAction(
      context,
      title: '要登出嗎？',
      message: '這台裝置上的登入狀態、快取資料與課表提醒都會清除。',
      confirmLabel: '登出',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await onLogout!();
    } catch (_) {
      if (context.mounted) showNiuMessage(context, '登出沒有完成，請再試一次');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final signedIn = username != null || name != null;
    return NiuScrollPage(
      title: '設定',
      children: [
        if (signedIn) ...[
          NiuCard(
            padding: const EdgeInsets.all(NiuSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          (name?.isNotEmpty ?? false)
                              ? name!.characters.first
                              : '宜',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: colors.onAccent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name ?? '學校帳號',
                            style: theme.textTheme.titleLarge,
                          ),
                          if (username != null)
                            Text(
                              username!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFeatures: tabularFigures,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (department != null || grade != null) ...[
                  const SizedBox(height: NiuSpacing.lg),
                  Wrap(
                    spacing: NiuSpacing.sm,
                    runSpacing: NiuSpacing.sm,
                    children: [
                      if (department != null)
                        NiuTag(
                          label: department!,
                          icon: Icons.apartment_rounded,
                        ),
                      if (grade != null)
                        NiuTag(label: grade!, icon: Icons.school_outlined),
                    ],
                  ),
                ],
                if (ssoNeedsReauthentication || offline) ...[
                  const SizedBox(height: NiuSpacing.lg),
                  NiuBanner(
                    tone: ssoNeedsReauthentication
                        ? NiuTone.warning
                        : NiuTone.neutral,
                    icon: ssoNeedsReauthentication ? null : NiuIcons.offline,
                    message: ssoNeedsReauthentication
                        ? '校務登入已過期，個人資料仍保留在裝置上。'
                        : '目前離線，顯示上次同步的資料。',
                    actionLabel: onReconnect == null ? null : '重新登入',
                    onAction: onReconnect,
                  ),
                ],
              ],
            ),
          ),
        ],
        if (onThemeModeChanged != null) ...[
          const NiuEyebrow('外觀'),
          NiuGroup(
            insetDividers: NiuSpacing.lg,
            children: [
              for (final (mode, label) in const [
                (ThemeMode.system, '跟隨系統'),
                (ThemeMode.light, '淺色'),
                (ThemeMode.dark, '深色'),
              ])
                Semantics(
                  selected: themeMode == mode,
                  inMutuallyExclusiveGroup: true,
                  child: NiuRow(
                    title: label,
                    chevron: false,
                    onTap: () => onThemeModeChanged!(mode),
                    trailing: Icon(
                      themeMode == mode
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: themeMode == mode
                          ? colors.accent
                          : colors.inkTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (onRefreshProfile != null || onForgetSchoolLogin != null) ...[
          const NiuEyebrow('帳號'),
          NiuGroup(
            children: [
              if (onRefreshProfile != null)
                NiuRow(
                  icon: NiuIcons.refresh,
                  title: '重新整理個人資料',
                  subtitle: '更新系所、年級與登入狀態',
                  onTap: () => _run(
                    context,
                    onRefreshProfile!,
                    '個人資料已更新',
                    '更新失敗，稍後再試一次',
                  ),
                ),
              if (onForgetSchoolLogin != null)
                NiuRow(
                  icon: NiuIcons.lock,
                  hue: NiuHue.gray,
                  title: '清除已保存的帳密',
                  subtitle: '下次登入需要重新輸入',
                  onTap: () => _run(
                    context,
                    onForgetSchoolLogin!,
                    '已清除保存的帳密',
                    '清除失敗，請再試一次',
                  ),
                ),
            ],
          ),
        ],
        if (notifications != null && signedIn) ...[
          const NiuEyebrow('通知'),
          NiuGroup(
            children: [
              NiuRow(
                icon: NiuIcons.notifications,
                hue: NiuHue.red,
                title: '通知設定',
                subtitle: '作業死線、重要日期、上課提醒',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NotificationSettingsScreen(
                      notifications: notifications!,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const NiuEyebrow('隱私'),
        NiuGroup(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: AppAnalytics.instance.enabled,
              builder: (context, enabled, _) => NiuRow(
                icon: Icons.query_stats_rounded,
                hue: NiuHue.teal,
                title: '分享匿名使用統計',
                subtitle: '用過哪些功能、哪裡出錯；不含帳號、成績或信件',
                onTap: () => AppAnalytics.instance.setEnabled(!enabled),
                chevron: false,
                trailing: Switch(
                  value: enabled,
                  onChanged: AppAnalytics.instance.setEnabled,
                ),
              ),
            ),
          ],
        ),
        const NiuEyebrow('關於'),
        NiuGroup(
          children: [
            NiuRow(
              icon: Icons.campaign_rounded,
              hue: NiuHue.blue,
              title: '公告',
              subtitle: 'App 的最新消息與重要通知',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AnnouncementsScreen(),
                ),
              ),
            ),
            NiuRow(
              icon: Icons.feedback_outlined,
              hue: NiuHue.orange,
              title: '回報問題',
              subtitle: '告訴我們哪裡不對勁',
              onTap: () => openPublicUrl(
                context,
                Uri.parse('https://forms.gle/2ok6fydShrfe6PHr5'),
              ),
            ),
            NiuRow(
              icon: NiuIcons.shield,
              hue: NiuHue.green,
              title: '隱私權',
              subtitle: 'App 如何處理你的資料',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
              ),
            ),
            NiuRow(
              icon: NiuIcons.code,
              hue: NiuHue.indigo,
              title: '開源專案',
              subtitle: 'GitHub・MIT 授權',
              onTap: () => openPublicUrl(
                context,
                Uri.parse('https://github.com/windlessme/niu-app-android'),
              ),
            ),
            NiuRow(
              icon: NiuIcons.heart,
              hue: NiuHue.pink,
              title: '特別感謝',
              subtitle: '讓這個 App 成真的人',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CreditsScreen(repository: creditsRepository),
                ),
              ),
            ),
            NiuRow(
              icon: NiuIcons.document,
              hue: NiuHue.gray,
              title: '開源授權',
              subtitle: '使用的套件與授權聲明',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'NIU-Life',
              ),
            ),
            FutureBuilder<AppVersion?>(
              future: AppVersion.current(),
              builder: (context, snapshot) => NiuRow(
                icon: NiuIcons.info,
                hue: NiuHue.gray,
                title: '版本',
                value: snapshot.data?.toString() ?? '—',
                chevron: false,
              ),
            ),
          ],
        ),
        if (onLogout != null) ...[
          const SizedBox(height: NiuSpacing.xxl),
          NiuGroup(
            children: [
              NiuRow(
                icon: NiuIcons.logout,
                hue: NiuHue.red,
                title: '登出',
                destructive: true,
                chevron: false,
                onTap: () => _logout(context),
              ),
            ],
          ),
        ],
        const SizedBox(height: NiuSpacing.xxxl),
        Text(
          'NIU-Life\n由學生開發的非官方校園工具',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.inkTertiary,
          ),
        ),
      ],
    );
  }
}
