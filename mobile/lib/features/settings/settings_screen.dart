import 'package:flutter/material.dart';
import '../../core/analytics/app_analytics.dart';
import '../../core/platform/app_version.dart';
import '../notifications/campus_notifications.dart';
import '../notifications/notification_settings_screen.dart';
import '../../shared/shared.dart';
import 'credits_repository.dart';

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

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const updated = '2026-10-02';

  static const sections = [
    (
      NiuIcons.lock,
      '帳號與登入',
      '登入資訊只用來連線學校系統：教務系統、M 園區、活動報名、校園信箱與圖書館。送出學校登入時，App 會用同一組帳密建立 M 園區、活動報名、校園信箱與圖書館的登入；送到圖書館系統的帳密會先依該網站的方式加密。成功核對身分後，帳密會存進裝置的安全儲存，下次自動登入；人機驗證仍由你操作。在設定中清除帳密或登出即可刪除。Token 與各系統的登入狀態使用裝置安全儲存，網站 Session 由 App 內的 WebView 管理。',
    ),
    (
      NiuIcons.course,
      '課程與個人資訊',
      'App 向學校服務取得你有權查看的課表、成績、作業、請假、註冊、信件與圖書館預約資料。讀信、寄信、搬移與刪除信件，以及預約或取消圖書館空間，都是你操作後直接送到學校系統。在學證明 PDF 可能包含姓名、學號與學籍資料，只在私人暫存中預覽；要存到哪裡或分享給誰由你決定。使用學校網頁時，也適用該網站的隱私權政策。',
    ),
    (
      NiuIcons.history,
      '手機上的副本',
      '課表、成績、畢業門檻、請假與在學證明的最近一次結果會加密保存在手機上，讓你離線或學校系統忙碌時也能查看。校園信箱登入時的驗證碼由手機上的 Google ML Kit 辨識，圖片不會上傳。',
    ),
    (
      NiuIcons.calendar,
      '公開內容',
      '行事曆與致謝名單會從 GitHub 公開資料更新，並在手機上保留離線副本。這些請求不需要學校帳密。',
    ),
    (
      Icons.query_stats_rounded,
      '匿名使用統計',
      'App 使用 Google Analytics for Firebase 統計開啟了哪些頁面、用了哪些功能和結果（例如點名或寄信是否成功），以及學校系統出了哪一類錯誤，用來改善 App。Google 也會收集裝置型號、系統與 App 版本、大略地區等基本資訊。不會送出帳號、學號、姓名、成績、信件、課程名稱或其他校務內容，不使用廣告 ID。可以在設定的「分享匿名使用統計」關閉；示範模式不會收集。',
    ),
    (
      NiuIcons.external,
      '外部連結、更新與問題回報',
      '開啟學校 PDF、GitHub 或回報表單時，會連線到對應網站。從 Google Play 安裝的 App 會向 Google Play 檢查是否有新版本。回報問題時請不要附上密碼或完整的敏感個資。',
    ),
    (
      Icons.photo_camera_outlined,
      '裝置權限與檔案',
      '相機只用來掃描點名 QR Code，不保存也不上傳影像。通知只用於你在通知設定開啟的作業死線、重要日期與上課提醒，全部在裝置上排程。選取的作業檔案和信件附件會送到學校系統；匯出與分享的副本由對方 App 管理。圖書館畫面會暫時調亮螢幕，離開後恢復。',
    ),
    (
      NiuIcons.logout,
      '登出與資料清除',
      '登出會清除登入憑證、網站資料、手機上的副本、附件暫存、課表小工具與提醒。已匯出的副本需要在對方 App 刪除；登出不會刪除學校帳號或學校的紀錄。',
    ),
    (
      Icons.mail_outline_rounded,
      '資料異動與聯絡',
      '校務資料以學校公告與系統紀錄為準。App 的問題可以透過設定中的「回報問題」告訴我們，或寄信到 hi@windless.me。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NiuScrollPage(
      title: '隱私權',
      children: [
        Text(
          'NIU-Life 沒有自己的伺服器：校務資料只在你的手機和學校系統之間傳遞，匿名使用統計送到 Google Analytics。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: NiuColors.of(context).inkSecondary,
          ),
        ),
        const SizedBox(height: NiuSpacing.lg),
        for (final (icon, title, body) in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.md),
            child: NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      NiuIconTile(icon: icon, size: 32),
                      const SizedBox(width: NiuSpacing.md),
                      Expanded(
                        child: Text(title, style: theme.textTheme.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: NiuSpacing.sm),
                  Text(body, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        const SizedBox(height: NiuSpacing.sm),
        Text(
          '更新日期：$updated',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}

class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key, this.repository});
  final CreditsRepository? repository;
  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  late final repository = widget.repository ?? CreditsRepository();
  CreditsSnapshot? snapshot;
  bool loading = true;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (snapshot == null) {
        final local = await repository.local();
        if (!mounted || request != generation) return;
        setState(() => snapshot = local);
      }
      final latest = await repository.refresh();
      if (!mounted || request != generation) return;
      setState(() => snapshot = latest);
    } catch (_) {
      if (!mounted || request != generation) return;
      setState(() => error = '名單更新失敗，稍後再試一次。');
    } finally {
      if (mounted && request == generation) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NiuScrollPage(
      title: '特別感謝',
      onRefresh: _load,
      children: [
        if (snapshot != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NiuSpacing.xs),
            child: Text(
              snapshot!.document.introduction,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: NiuSpacing.lg),
          if (snapshot!.document.entries.isNotEmpty)
            NiuGroup(
              children: [
                for (final entry in snapshot!.document.entries)
                  NiuRow(
                    icon: NiuIcons.person,
                    hue: NiuHue.pink,
                    title: entry['name'] as String,
                    subtitle:
                        '${entry['description']}\n${entry['projectName']}',
                    maxSubtitleLines: 4,
                    onTap: () => openPublicUrl(
                      context,
                      Uri.parse(entry['url'] as String),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: NiuSpacing.lg),
          Text(
            '${snapshot!.source} · 修訂 ${snapshot!.document.revision}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium,
          ),
          if (snapshot!.message != null)
            Padding(
              padding: const EdgeInsets.only(top: NiuSpacing.md),
              child: NiuBanner(
                tone: NiuTone.neutral,
                message: snapshot!.message!,
              ),
            ),
        ],
        if (loading) const NiuLoading(message: '正在更新名單', compact: true),
        if (error != null) ...[
          const SizedBox(height: NiuSpacing.lg),
          NiuBanner(
            tone: NiuTone.warning,
            message: error!,
            actionLabel: loading ? null : '重新整理',
            onAction: loading ? null : _load,
          ),
        ],
      ],
    );
  }
}
