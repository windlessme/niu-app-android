import 'package:flutter/material.dart';
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
  });
  final String? name, username, department, grade;
  final Future<void> Function()? onLogout, onRefreshProfile;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final CreditsRepository? creditsRepository;
  final bool offline, ssoNeedsReauthentication;
  final VoidCallback? onReconnect;
  final Future<void> Function()? onForgetSchoolLogin;

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
        const NiuEyebrow('關於'),
        NiuGroup(
          children: [
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
                Uri.parse('https://github.com/qian403/NIU-app'),
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

  static const sections = [
    (
      NiuIcons.lock,
      '帳號與登入',
      '登入資訊用於連線學校的教務與數位學習系統。送出學校登入時，App 會用同一組帳密建立 M 園區與活動報名的登入。成功核對身分後，帳密會存進裝置的安全儲存，下次自動填入學校登入頁；人機驗證與送出仍由你操作。在設定中清除帳密或登出即可刪除；之後再次成功登入時會重新保存。Token 使用裝置安全儲存，網站 Session 由 App 內的 WebView 管理。',
    ),
    (
      NiuIcons.course,
      '課程與個人資訊',
      'App 向學校服務取得你有權查看的課表、成績、作業與註冊資訊。在學證明 PDF 可能包含姓名、學號與學籍資料，只在私人暫存中預覽；要存到哪裡或分享給誰由你決定。使用學校網頁時，也適用該網站的隱私權政策。',
    ),
    (
      NiuIcons.calendar,
      '公開內容與離線副本',
      '行事曆與致謝名單會從 GitHub 公開資料更新，並在手機上保留離線副本。這些請求不需要學校帳密。',
    ),
    (
      NiuIcons.external,
      '外部連結與問題回報',
      '開啟學校 PDF、GitHub 或回報表單時，會連線到對應網站。回報問題時請不要附上密碼或完整的敏感個資。',
    ),
    (
      Icons.photo_camera_outlined,
      '裝置權限與檔案',
      '相機只用來掃描點名 QR Code，不保存也不上傳影像。通知用於你開啟的上課提醒。選取的作業檔案會送到學校 M 園區；匯出與分享的副本由對方 App 管理。圖書館畫面會暫時調亮螢幕，離開後恢復。',
    ),
    (
      NiuIcons.logout,
      '登出與資料清除',
      '登出會清除登入憑證、網站資料、個人快取、附件暫存、課表小工具與提醒。已匯出的副本需要在對方 App 刪除；登出不會刪除學校帳號或學校的紀錄。',
    ),
    (Icons.query_stats_rounded, '使用統計', '這個 Android 版本沒有開發者活躍統計、廣告追蹤或遠端推播。'),
    (
      Icons.mail_outline_rounded,
      '資料異動與聯絡',
      '校務資料以學校公告與系統紀錄為準。App 的問題可以透過設定中的「回報問題」告訴我們，或寄信到 hi@chien.dev。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NiuScrollPage(
      title: '隱私權',
      children: [
        Text(
          'NIU-Life 只在你的手機和學校系統之間傳遞資料，沒有自己的伺服器。',
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
          '更新日期：2026-09-28',
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
