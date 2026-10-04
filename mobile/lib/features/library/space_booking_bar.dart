import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'space_booking_controller.dart';
import 'space_models.dart';

/// Pinned summary of the choice, the length slider and the review button.
class SpaceBookingBar extends StatelessWidget {
  const SpaceBookingBar({
    super.key,
    required this.controller,
    required this.dayLabel,
    required this.onReview,
    required this.onVerify,
  });
  final SpaceBookingController controller;
  final String dayLabel;
  final VoidCallback onReview, onVerify;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final c = controller;
    final label = c.timeLabel;
    final max = c.maxDuration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label ?? '尚未選擇時段',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    Text(
                      '${c.room?.name ?? '請選擇設備'} · $dayLabel',
                      maxLines: 2,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (label != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.md,
                    vertical: NiuSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accentSoft,
                    borderRadius: BorderRadius.circular(NiuRadius.pill),
                  ),
                  child: Text(
                    '${formatHours(c.duration / 60)} 小時',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.accent,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (label != null && max != null && max > c.minDuration) ...[
          Slider(
            value: c.duration.toDouble(),
            min: c.minDuration.toDouble(),
            max: max.toDouble(),
            divisions: (max - c.minDuration) ~/ 30,
            label: '${formatHours(c.duration / 60)} 小時',
            semanticFormatterCallback: (v) => '${formatHours(v / 60)} 小時',
            onChanged: c.busy ? null : (v) => c.setDuration(v.round()),
          ),
          ExcludeSemantics(
            child: Row(
              children: [
                Text(
                  '${formatHours(c.minDuration / 60)} 小時',
                  style: theme.textTheme.labelSmall,
                ),
                const Spacer(),
                Text(
                  '最多 ${formatHours(max / 60)} 小時',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ] else if (label != null && max != null)
          Padding(
            padding: const EdgeInsets.only(top: NiuSpacing.xs),
            child: Text(
              '這個開始時間只能預約 ${formatHours(max / 60)} 小時。',
              style: theme.textTheme.bodySmall,
            ),
          )
        else if (c.start == null)
          Padding(
            padding: const EdgeInsets.only(top: NiuSpacing.xs),
            child: Text(
              '點選上方的開始時間，再拖曳滑桿調整時長。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (c.selectionMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: NiuSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(NiuIcons.info, size: 16, color: colors.inkSecondary),
                const SizedBox(width: NiuSpacing.xs),
                Expanded(
                  child: Text(
                    c.selectionMessage!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: NiuSpacing.md),
        if (c.needsVerification)
          FilledButton(onPressed: onVerify, child: const Text('查看我的預約並核對'))
        else
          FilledButton.icon(
            onPressed: c.busy || c.selectionError != null ? null : onReview,
            iconAlignment: IconAlignment.end,
            icon: c.loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: Text(c.loading ? '正在核對…' : '核對預約'),
          ),
      ],
    );
  }
}

// ── Confirmation ─────────────────────────────────────────────────────────────

class SpaceConfirmSheet extends StatefulWidget {
  const SpaceConfirmSheet({
    super.key,
    required this.controller,
    required this.draft,
    required this.dateLabel,
  });
  final SpaceBookingController controller;
  final SpaceDraft draft;
  final String dateLabel;
  @override
  State<SpaceConfirmSheet> createState() => _SpaceConfirmSheetState();
}

class _SpaceConfirmSheetState extends State<SpaceConfirmSheet> {
  bool sending = false;

  Future<void> send() async {
    setState(() => sending = true);
    final result = await widget.controller.submit(widget.draft);
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.draft;
    return PopScope(
      canPop: !sending,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.gutter,
            0,
            NiuSpacing.gutter,
            NiuSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('確認設備預約', style: theme.textTheme.titleLarge),
              const SizedBox(height: NiuSpacing.lg),
              Row(
                children: [
                  const NiuIconTile(
                    icon: Icons.event_available_rounded,
                    hue: NiuHue.indigo,
                  ),
                  const SizedBox(width: NiuSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.room.name, style: theme.textTheme.titleMedium),
                        Text(d.group.name, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NiuSpacing.lg),
              NiuWell(
                child: Column(
                  children: [
                    NiuKeyValue(label: '日期', value: widget.dateLabel),
                    NiuKeyValue(label: '時段', value: d.timeLabel),
                    NiuKeyValue(
                      label: '時長',
                      value: '${formatHours(d.minutes / 60)} 小時',
                    ),
                    NiuKeyValue(
                      label: '目前剩餘額度',
                      value: '${formatHours(d.rules.remainingHours)} 小時',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NiuSpacing.sm),
              Text(
                '送出時會再次核對時段與規則。預約完成後，請依圖書館規定報到。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: NiuSpacing.xl),
              FilledButton(
                onPressed: sending ? null : send,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sending) ...[
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: NiuSpacing.sm),
                    ],
                    Text(sending ? '正在送出…' : '確認並送出預約'),
                  ],
                ),
              ),
              const SizedBox(height: NiuSpacing.sm),
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 我的預約 card ─────────────────────────────────────────────────────────────
