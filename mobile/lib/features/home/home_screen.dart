import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/shared.dart';

class HomeCourse {
  const HomeCourse({
    required this.name,
    required this.time,
    this.room = '',
    this.current = false,
  });
  final String name;
  final String time;
  final String room;
  final bool current;
}

/// Home matches the iOS hierarchy: profile, greeting, today, attendance, cards.
class CampusHomeScreen extends StatelessWidget {
  const CampusHomeScreen({
    super.key,
    this.name,
    this.department,
    this.courses = const [],
    this.onRefresh,
    this.offline = false,
    this.ssoNeedsReauthentication = false,
    this.hasSchedule = false,
  });
  final String? name;
  final String? department;
  final List<HomeCourse> courses;
  final Future<void> Function()? onRefresh;
  final bool offline;
  final bool ssoNeedsReauthentication;
  final bool hasSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final attendanceBackground = theme.colorScheme.primaryContainer;
    final attendanceInk = theme.colorScheme.onPrimaryContainer;
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final date = '${now.month} 月 ${now.day} 日・星期${'一二三四五六日'[now.weekday - 1]}';
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            try {
              await onRefresh?.call();
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('暫時無法更新，目前顯示上次資料。')),
                );
              }
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: accent.withValues(alpha: .12),
                    child: Text(
                      name?.characters.firstOrNull ?? '宜',
                      style: TextStyle(color: accent),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name ?? 'NIU-Life',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          department?.isNotEmpty == true
                              ? department!
                              : '國立宜蘭大學',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  CircleIconButton(
                    onPressed: () => context.push('/settings'),
                    label: '設定',
                    icon: CupertinoIcons.gear,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text(
                name == null ? '歡迎來到' : '歡迎回來',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name ?? 'NIU-Life',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                date,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              if (ssoNeedsReauthentication)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('校務登入已過期，已保留個人資料與課表。其他服務可繼續使用各自的登入。'),
                      TextButton(
                        onPressed: () => context.push('/login'),
                        child: const Text('重新連接校務系統'),
                      ),
                    ],
                  ),
                ),
              if (offline)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('離線模式 · 顯示上次同步的課表，下拉可重新連線。'),
                ),
              _HomeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(CupertinoIcons.calendar, color: accent, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '今日課程',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/schedule'),
                          child: const Text('完整課表'),
                        ),
                      ],
                    ),
                    if (name == null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('登入校務帳號，同步你的課表與校園服務。'),
                      ),
                      FilledButton(
                        onPressed: () => context.push('/login'),
                        child: const Text('登入校務系統'),
                      ),
                    ] else if (courses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          hasSchedule
                              ? '今天接下來沒有課程，好好安排你的時間。'
                              : '尚未同步課表，開啟完整課表即可取得今日安排。',
                        ),
                      )
                    else
                      ...courses.map(
                        (course) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: course.current
                                      ? accent
                                      : accent.withValues(alpha: .3),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      course.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${course.time}  ${course.room}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (course.current)
                                Text(
                                  '上課中',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: accent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                button: true,
                label: '快速點名，開啟 QR Code 掃描器',
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => context.push('/attendance'),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          attendanceBackground,
                          Color.lerp(
                            attendanceBackground,
                            theme.colorScheme.surface,
                            .2,
                          )!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    padding: const EdgeInsets.all(22),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.qrcode_viewfinder,
                          color: attendanceInk,
                          size: 34,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '快速點名',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: attendanceInk,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '掃描課堂 QR Code',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: attendanceInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_right,
                          color: attendanceInk,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                '校園服務',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final singleColumn =
                      MediaQuery.textScalerOf(context).scale(16) > 24 ||
                      constraints.maxWidth < 300;
                  final width = singleColumn
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 16) / 2;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final item in const [
                        ('M 園區', '課程・公告・作業', CupertinoIcons.book, '/moodle'),
                        ('圖書館', '門禁與借書條碼', CupertinoIcons.barcode, '/library'),
                        (
                          '學年度行事曆',
                          '校園重要日程',
                          CupertinoIcons.calendar,
                          '/calendar',
                        ),
                        (
                          '歷年成績',
                          '學期成績與 GPA',
                          CupertinoIcons.chart_bar,
                          '/grades',
                        ),
                        (
                          '畢業門檻',
                          '多元・英文・體適能',
                          CupertinoIcons.checkmark_seal,
                          '/graduation',
                        ),
                        ('活動報名', '探索校園活動', CupertinoIcons.ticket, '/events'),
                        (
                          '註冊資訊',
                          '查詢・在學證明',
                          CupertinoIcons.doc_text,
                          '/registration',
                        ),
                      ])
                        SizedBox(
                          width: width,
                          child: NiuFeatureCard(
                            title: item.$1,
                            subtitle: item.$2,
                            icon: item.$3,
                            onTap: () => context.push(item.$4),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                '非官方校務工具 · 校務資訊以校方系統為準',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AppCard(child: child);
}
