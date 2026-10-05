import 'package:flutter/material.dart';
import '../../shared/shared.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const updated = '2026-10-05';

  /// The full policy, shared by the iOS app, this app and the website.
  static final policy = Uri.parse('https://niu-life.app/privacy');

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
      '行事曆、致謝名單與 App 公告會從 GitHub 公開資料更新，並在手機上保留離線副本。這些請求不需要學校帳密；關掉的公告只在手機上記住編號。',
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
      '校務資料以學校公告與系統紀錄為準。App 的問題可以透過設定中的「回報問題」告訴我們，或寄信到 hi@niu-life.app（iOS 版與 Android 版共用）。',
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
        OutlinedButton.icon(
          onPressed: () => openPublicUrl(context, policy),
          icon: const Icon(NiuIcons.external),
          label: const Text('完整隱私權政策'),
        ),
        const SizedBox(height: NiuSpacing.md),
        Text(
          '更新日期：$updated',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}
