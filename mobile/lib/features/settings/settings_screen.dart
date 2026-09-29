import 'package:flutter/cupertino.dart';
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const IosPageHeader(title: '設定'),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (username != null || name != null) ...[
            NiuCard(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    child: Text(
                      (name?.isNotEmpty ?? false)
                          ? name!.characters.first
                          : '宜',
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name ?? '校園帳號',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (username != null) Text(username!),
                  if (ssoNeedsReauthentication)
                    const Text('校務登入已過期 · 個人資料已保留')
                  else if (offline)
                    const Text('暫時無法連線 · 顯示上次同步的資料'),
                  if (onReconnect != null &&
                      (ssoNeedsReauthentication || offline))
                    TextButton(
                      onPressed: onReconnect,
                      child: const Text('重新連接校務系統'),
                    ),
                  const Divider(height: 32),
                  if (department != null) _info('系所', department!),
                  if (grade != null) _info('年級', grade!),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (onThemeModeChanged != null) ...[
            const _Heading('外觀'),
            NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('顯示模式'),
                  const SizedBox(height: 8),
                  DropdownButton<ThemeMode>(
                    isExpanded: true,
                    itemHeight: null,
                    value: themeMode,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('跟隨系統'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('淺色'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('深色'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) onThemeModeChanged!(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (onRefreshProfile != null) ...[
            const _Heading('同步'),
            _Action(
              icon: CupertinoIcons.arrow_clockwise,
              title: '重新抓取個人資訊',
              subtitle: '更新系所、年級與登入狀態',
              onTap: () async {
                try {
                  await onRefreshProfile!();
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('個人資訊已更新')));
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('更新失敗，請稍後再試。')),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 24),
          ],
          if (onForgetSchoolLogin != null) ...[
            const _Heading('登入與安全'),
            _Action(
              icon: CupertinoIcons.lock,
              title: '忘記已儲存的校務帳密',
              subtitle: '清除這台裝置的帳密預填資料',
              onTap: () async {
                try {
                  await onForgetSchoolLogin!();
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已清除記住的校務帳密')));
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('清除失敗，請重試。')));
                  }
                }
              },
            ),
            const SizedBox(height: 24),
          ],
          const _Heading('關於'),
          _Action(
            icon: CupertinoIcons.exclamationmark_bubble,
            title: '回報問題',
            subtitle: '填寫問題回報表單',
            onTap: () => openPublicUrl(
              context,
              Uri.parse('https://forms.gle/2ok6fydShrfe6PHr5'),
            ),
          ),
          _Action(
            icon: CupertinoIcons.shield,
            title: '隱私權聲明',
            subtitle: '查看資料處理說明',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
            ),
          ),
          _Action(
            icon: CupertinoIcons.chevron_left_slash_chevron_right,
            title: '開源專案',
            subtitle: 'GitHub 原始碼・MIT 授權',
            onTap: () => openPublicUrl(
              context,
              Uri.parse('https://github.com/qian403/NIU-app'),
            ),
          ),
          _Action(
            icon: CupertinoIcons.heart,
            title: '特別感謝',
            subtitle: '致謝開源專案開發者',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CreditsScreen(repository: creditsRepository),
              ),
            ),
          ),
          _Action(
            icon: CupertinoIcons.doc_text,
            title: '開源授權',
            subtitle: '使用的套件與授權聲明',
            onTap: () =>
                showLicensePage(context: context, applicationName: 'NIU-Life'),
          ),
          if (onLogout != null) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(CupertinoIcons.square_arrow_right),
              label: const Text('登出'),
              onPressed: () async {
                final confirmed = await showCupertinoDialog<bool>(
                  context: context,
                  builder: (context) => CupertinoAlertDialog(
                    title: const Text('確定要登出嗎？'),
                    content: const Text('將清除這台裝置的登入狀態。'),
                    actions: [
                      CupertinoDialogAction(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      CupertinoDialogAction(
                        isDestructiveAction: true,
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('登出'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await onLogout!();
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('登出未完成，請再試一次。')),
                      );
                    }
                  }
                }
              },
            ),
          ],
          const SizedBox(height: 24),
          const Text('NIU-Life\n由學生開發的校園生活工具', textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Text(label),
        const SizedBox(width: 20),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 12, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
        onTap: onTap,
      ),
    ),
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const IosPageHeader(title: '隱私權聲明'),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          NiuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '你的校園資料',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                Text(
                  '帳號與登入\n登入資訊用於連線至學校的教務及數位學習系統。送出校方登入時，App 使用同組帳密建立 M 園區與活動登入。成功核對身分後，會自動將帳密存入裝置安全儲存，供下次填入校方登入頁。人機驗證與提交仍由你操作。設定中的忘記帳密或登出可清除已記住的帳密；之後再次成功輸入帳密登入時會重新保存。Token 使用裝置安全儲存，網站 Session 由 App 的 WebView 管理。',
                ),
                SizedBox(height: 20),
                Text(
                  '課程與個人資訊\nApp 向學校服務取得你有權查看的課表、成績、作業及註冊資訊。在學證明PDF可能包含姓名、學號與學籍資料，僅在私人暫存預覽；儲存或分享由你選擇目的位置。使用學校網頁時，也適用該網站的隱私權政策。',
                ),
                SizedBox(height: 20),
                Text(
                  '公開內容與離線快取\n行事曆與致謝名單可由 GitHub 公開資料更新，並在本機保留離線副本。這些請求不需要校務帳號密碼。',
                ),
                SizedBox(height: 20),
                Text(
                  '外部連結與問題回報\n開啟校方 PDF、GitHub 或回報表單時，會連線到相應網站。請勿在回報內容中提供密碼或完整的敏感個人資料。',
                ),
                SizedBox(height: 20),
                Text('資料異動與聯絡\n校務資料以校方公告及系統紀錄為準。若有 App 問題，可透過設定中的「回報問題」聯絡開發者。'),
                SizedBox(height: 20),
                Text(
                  '裝置權限與檔案\n相機僅用於掃描點名 QR Code，不保存或上傳影像。通知用於使用者啟用的本機課程提醒。選取的作業附件送至學校 M 園區；匯出與分享副本由目的 App 管理。圖書館畫面可提高螢幕亮度，離開後恢復。',
                ),
                SizedBox(height: 20),
                Text(
                  '登出與資料清除\n登出清除登入憑證、網站資料、個人快取、附件暫存、課表小工具與提醒。匯出的副本須在目的 App 刪除；登出不會刪除學校帳號或校方紀錄。',
                ),
                SizedBox(height: 20),
                Text(
                  '使用統計\n此 Android 版本未啟用開發者活躍統計、廣告追蹤或遠端課程推播。聯絡：hi@chien.dev。更新日期：2026-09-28。',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
      setState(() => error = '名單更新失敗，請稍後再試。');
    } finally {
      if (mounted && request == generation) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const IosPageHeader(title: '特別感謝'),
    body: SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              CupertinoIcons.heart,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            _Action(
              icon: CupertinoIcons.chevron_left_slash_chevron_right,
              title: 'qian403 · NIU-app',
              subtitle:
                  '感謝原始校園 App 專案提供功能設計與實作參考。\nhttps://github.com/qian403/niu-app',
              onTap: () => openPublicUrl(
                context,
                Uri.parse('https://github.com/qian403/niu-app'),
              ),
            ),
            if (snapshot != null) ...[
              Text(snapshot!.document.introduction),
              const SizedBox(height: 20),
              for (final entry in snapshot!.document.entries)
                _Action(
                  icon: CupertinoIcons.person,
                  title: entry['name'] as String,
                  subtitle: '${entry['description']}\n${entry['projectName']}',
                  onTap: () =>
                      openPublicUrl(context, Uri.parse(entry['url'] as String)),
                ),
              const SizedBox(height: 20),
              Text(
                '${snapshot!.source} · 修訂 ${snapshot!.document.revision}',
                textAlign: TextAlign.center,
              ),
              if (snapshot!.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(snapshot!.message!),
                ),
            ],
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CupertinoActivityIndicator(),
              ),
            if (error != null) ...[
              Semantics(liveRegion: true, child: Text(error!)),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: loading ? null : _load,
                child: const Text('重新整理'),
              ),
            ],
            const SizedBox(height: 12),
            const Text('下拉更新名單', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
