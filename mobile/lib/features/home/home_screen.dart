import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/shared.dart';
import 'name_mask.dart';
import 'campus_services.dart';
import '../../core/demo/demo_account.dart';

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

  /// Start and end clock values when the school time text contains them.
  (String, String)? get range {
    final times = RegExp(
      r'\d{1,2}:\d{2}',
    ).allMatches(time).map((m) => m.group(0)!).toList();
    return times.length < 2 ? null : (times.first, times.last);
  }
}

/// Home answers "what's next today?" first, then offers one-tap services.
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
    this.onOpenCourse,
    this.demo = false,
    this.announcements,
  });

  /// Announcement cards under the greeting (see AnnouncementBoard).
  final Widget? announcements;

  /// Google Play review demo: everything shown is sample data.
  final bool demo;
  final String? name;
  final String? department;
  final List<HomeCourse> courses;
  final Future<void> Function()? onRefresh;
  final bool offline;
  final bool ssoNeedsReauthentication;
  final bool hasSchedule;

  /// Opens the matching M 園區 course for a timetable entry.
  final void Function(String course)? onOpenCourse;

  static String greeting(DateTime taipei) => switch (taipei.hour) {
    >= 5 && < 11 => '早安',
    >= 11 && < 18 => '午安',
    _ => '晚上好',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final date = '${now.month} 月 ${now.day} 日　星期${'一二三四五六日'[now.weekday - 1]}';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            try {
              await onRefresh?.call();
            } catch (_) {
              if (context.mounted) {
                showNiuMessage(context, '更新失敗，先顯示上次的資料');
              }
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              NiuSpacing.gutter,
              NiuSpacing.md,
              NiuSpacing.gutter,
              NiuSpacing.huge,
            ),
            children: [
              _ProfileHeader(name: name, department: department),
              const SizedBox(height: NiuSpacing.xxl),
              Text(date, style: theme.textTheme.labelMedium),
              const SizedBox(height: NiuSpacing.xs),
              Semantics(
                header: true,
                child: name == null
                    ? Text(
                        '歡迎使用 NIU-Life',
                        style: theme.textTheme.headlineLarge,
                      )
                    : Row(
                        children: [
                          Flexible(
                            child: MaskedName(
                              name: name!,
                              prefix: '${greeting(now)}，',
                              style: theme.textTheme.headlineLarge,
                            ),
                          ),
                          const NameMaskButton(),
                        ],
                      ),
              ),
              ?announcements,
              // Store screenshots show the app as students see it.
              if (demo && !storeScreenshots) ...[
                const SizedBox(height: NiuSpacing.lg),
                const NiuBanner(
                  tone: NiuTone.accent,
                  title: '示範模式',
                  message: '所有資料皆為示範內容；請假、報名、點名等送出操作只會模擬，不會連線學校系統。',
                ),
              ],
              if (ssoNeedsReauthentication) ...[
                const SizedBox(height: NiuSpacing.lg),
                NiuBanner(
                  tone: NiuTone.warning,
                  title: '校務系統需要重新登入',
                  message: '課表與個人資料仍保留在裝置上，M 園區等服務不受影響。',
                  actionLabel: '重新登入',
                  onAction: () => context.push('/login'),
                ),
              ],
              if (offline) ...[
                const SizedBox(height: NiuSpacing.lg),
                const NiuBanner(
                  tone: NiuTone.neutral,
                  icon: NiuIcons.offline,
                  message: '目前離線，顯示上次同步的課表。下拉即可重新連線。',
                ),
              ],
              NiuSection(
                title: '今天',
                action: name == null
                    ? null
                    : TextButton(
                        onPressed: () => context.go('/schedule'),
                        child: const Text('完整課表'),
                      ),
                child: _TodayCard(
                  signedIn: name != null,
                  courses: courses,
                  hasSchedule: hasSchedule,
                  onOpenCourse: onOpenCourse,
                ),
              ),
              const SizedBox(height: NiuSpacing.md),
              NiuCard(
                semanticLabel: 'M 園區快速點名，掃描課堂 QR Code 簽到',
                onTap: () => context.push('/attendance'),
                child: Row(
                  children: [
                    const NiuIconTile(
                      icon: NiuIcons.attendance,
                      size: NiuSize.iconTileLarge,
                    ),
                    const SizedBox(width: NiuSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('M 園區快速點名', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            '掃描課堂 QR Code 簽到',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(NiuIcons.forward, color: colors.inkTertiary),
                  ],
                ),
              ),
              NiuSection(
                title: '校園服務',
                child: const _ServiceGrid(services: CampusServices.home),
              ),
              const SizedBox(height: NiuSpacing.xxxl),
              Text(
                '非官方工具，校務資訊以學校系統為準。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.inkTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({this.name, this.department});
  final String? name;
  final String? department;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              name?.characters.firstOrNull ?? '宜',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onAccent,
              ),
            ),
          ),
        ),
        const SizedBox(width: NiuSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name == null)
                Text('NIU-Life', style: theme.textTheme.titleSmall)
              else
                MaskedName(
                  name: name!,
                  maxLines: 1,
                  style: theme.textTheme.titleSmall,
                ),
              Text(
                department?.isNotEmpty == true ? department! : '國立宜蘭大學',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
        NiuIconButton(
          icon: NiuIcons.settings,
          tooltip: '設定',
          tonal: true,
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.signedIn,
    required this.courses,
    required this.hasSchedule,
    this.onOpenCourse,
  });
  final bool signedIn;
  final List<HomeCourse> courses;
  final bool hasSchedule;
  final void Function(String course)? onOpenCourse;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!signedIn) {
      return NiuCard(
        padding: const EdgeInsets.all(NiuSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('登入後查看今天的課', style: theme.textTheme.titleMedium),
            const SizedBox(height: NiuSpacing.xs),
            Text('使用學校帳號登入，同步課表、M 園區與校園服務。', style: theme.textTheme.bodySmall),
            const SizedBox(height: NiuSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('登入校務系統'),
              ),
            ),
          ],
        ),
      );
    }
    if (courses.isEmpty) {
      final (icon, title, message) = hasSchedule
          ? (NiuIcons.rest, '今天沒有接下來的課', '好好安排剩下的時間。')
          : (NiuIcons.schedule, '還沒有課表', '開啟課表同步一次，這裡就會顯示今天的課。');
      return NiuCard(
        onTap: hasSchedule ? null : () => context.go('/schedule'),
        child: Row(
          children: [
            NiuIconTile(icon: icon, hue: NiuHue.amber),
            const SizedBox(width: NiuSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(message, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return NiuCard(
      padding: const EdgeInsets.symmetric(vertical: NiuSpacing.xs),
      child: Column(
        children: [
          for (final (i, course) in courses.indexed) ...[
            if (i > 0) const Divider(indent: 84),
            _CourseRow(
              course: course,
              // Only the first class not yet started is 下一堂.
              label: course.current
                  ? '上課中'
                  : courses.take(i).every((c) => c.current)
                  ? '下一堂'
                  : '稍後',
              onOpen: onOpenCourse,
            ),
          ],
        ],
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course, required this.label, this.onOpen});
  final HomeCourse course;
  final String label;
  final void Function(String course)? onOpen;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final range = course.range;
    return InkWell(
      onTap: onOpen == null
          ? () => context.go('/schedule')
          : () => onOpen!(course.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NiuSpacing.lg,
          vertical: 14,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      range?.$1 ?? course.time,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    if (range != null)
                      Text(
                        range.$2,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFeatures: tabularFigures,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                width: 3,
                margin: const EdgeInsets.symmetric(horizontal: NiuSpacing.md),
                decoration: BoxDecoration(
                  color: course.current ? colors.accent : colors.fillStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NiuBadge(
                      label: label,
                      tone: course.current ? NiuTone.accent : NiuTone.neutral,
                      solid: course.current,
                    ),
                    const SizedBox(height: 6),
                    Text(course.name, style: theme.textTheme.titleMedium),
                    if (course.room.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            NiuIcons.location,
                            size: 15,
                            color: colors.inkTertiary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              course.room,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({required this.services});
  final List<CampusService> services;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final single =
          MediaQuery.textScalerOf(context).scale(16) > 26 ||
          constraints.maxWidth < 300;
      const gap = NiuSpacing.md;
      final width = single
          ? constraints.maxWidth
          : (constraints.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final service in services)
            SizedBox(
              width: width,
              child: _ServiceTile(service: service),
            ),
        ],
      );
    },
  );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service});
  final CampusService service;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NiuCard(
      semanticLabel: '${service.title}，${service.subtitle}',
      onTap: () => openCampusService(context, service),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NiuIconTile(icon: service.icon, hue: service.hue),
          const SizedBox(height: NiuSpacing.md),
          Text(service.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            service.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
