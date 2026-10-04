import 'package:flutter/material.dart';
import '../../core/time/campus_date.dart';
import '../../shared/shared.dart';
import 'space_models.dart';

class SpaceReservationCard extends StatelessWidget {
  const SpaceReservationCard({
    super.key,
    required this.reservation,
    required this.today,
    required this.onCancel,
  });
  final SpaceReservation reservation;
  final CampusDate today;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final r = reservation;
    final inUse = r.state == ReservationState.inUse;
    String two(int v) => v.toString().padLeft(2, '0');
    final endDay = r.endDate == r.date
        ? ''
        : '${two(r.endDate.month)}/${two(r.endDate.day)} ';
    final time = '${formatMinute(r.start)}–$endDay${formatMinute(r.end)}';
    final keep = r.keepUntil;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: tabularFigures,
    );
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 60,
                    minHeight: 60,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accentSoft,
                    borderRadius: BorderRadius.circular(NiuRadius.md),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        relativeDay(r.date, today) ?? shortWeekday(r.date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.accent,
                        ),
                      ),
                      Text(
                        '${r.date.month}/${r.date.day}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.accent,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            r.roomName,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        NiuBadge(
                          label: inUse ? '使用中' : '已預約',
                          tone: inUse ? NiuTone.accent : NiuTone.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: NiuSpacing.xs),
                    _line(
                      NiuIcons.calendar,
                      '${webpacDate(r.date)}（${shortWeekday(r.date)}）',
                      secondary,
                      colors,
                    ),
                    _line(
                      NiuIcons.time,
                      '$time · ${formatHours(r.minutes / 60)} 小時',
                      secondary,
                      colors,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((keep != null && !inUse) ||
              r.state == ReservationState.reserved) ...[
            const SizedBox(height: NiuSpacing.md),
            Divider(height: 1, color: colors.hairline),
            const SizedBox(height: NiuSpacing.sm),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: NiuSpacing.sm,
              runSpacing: NiuSpacing.xs,
              children: [
                if (keep != null && !inUse)
                  _line(
                    Icons.hourglass_bottom_rounded,
                    '保留期限 ${webpacDate(keep.$1)} ${formatMinute(keep.$2)}',
                    secondary,
                    colors,
                  ),
                if (r.state == ReservationState.reserved)
                  Semantics(
                    label:
                        '取消 ${r.roomName}，${webpacDate(r.date)} ${formatMinute(r.start)} 的預約',
                    button: true,
                    excludeSemantics: true,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        side: BorderSide(
                          color: colors.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text('取消預約'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(
    IconData icon,
    String text,
    TextStyle? style,
    NiuColors colors,
  ) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.inkTertiary),
        const SizedBox(width: NiuSpacing.xs),
        Flexible(child: Text(text, style: style)),
      ],
    ),
  );
}
