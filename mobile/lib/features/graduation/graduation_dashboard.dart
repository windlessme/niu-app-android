import 'dart:math';

import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'graduation_confetti.dart';
import 'graduation_presentation.dart';
import 'graduation_screen.dart';

class GraduationDashboard extends StatelessWidget {
  const GraduationDashboard({
    super.key,
    required this.data,
    this.updatedAt,
    this.offline = false,
    this.needsReauthentication = false,
    this.embedded = false,
  });
  final GraduationData data;
  final DateTime? updatedAt;
  final bool offline, needsReauthentication;

  /// Embedded dashboards render inside a parent scroll view.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = GraduationPresentation(
      hours: data.hours,
      credits: data.credits,
      english: data.english,
      fitness: data.fitness,
      program: data.program,
    );
    final program = data.program.trim();
    final hasProgram =
        program.isNotEmpty && program != '無' && program.length >= 2;
    final children = <Widget>[
      if (needsReauthentication) ...[
        const NiuBanner(tone: NiuTone.warning, message: '校務登入已過期，先顯示上次保存的資料。'),
        const SizedBox(height: NiuSpacing.lg),
      ],
      _Overview(progress: model.progress, complete: model.allComplete),
      const SizedBox(height: NiuSpacing.lg),
      _Card(
        icon: NiuIcons.time,
        title: '多元時數',
        child: Column(
          children: [
            for (var i = 0; i < model.hours.length; i++) ...[
              if (i > 0) const SizedBox(height: NiuSpacing.lg),
              _HoursRow(
                label: model.hours[i].label.replaceAll('學習', ''),
                requirement: model.hours[i],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: NiuSpacing.lg),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _AbilityTile(
                icon: Icons.translate_rounded,
                title: '外語能力',
                requirement: model.qualifications[0],
              ),
            ),
            const SizedBox(width: NiuSpacing.md),
            Expanded(
              child: _AbilityTile(
                icon: Icons.directions_run_rounded,
                title: '體適能',
                requirement: model.qualifications[1],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: NiuSpacing.lg),
      _Card(
        icon: Icons.menu_book_rounded,
        title: '畢業學分',
        child: _CreditsRow(requirement: model.credits),
      ),
      if (hasProgram) ...[
        const SizedBox(height: NiuSpacing.lg),
        _Card(
          icon: NiuIcons.graduation,
          title: '學分學程',
          child: Text(
            program.replaceAll('、', '\n'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
      const SizedBox(height: NiuSpacing.xl),
      if (updatedAt != null || offline)
        NiuSyncStatus(updatedAt: updatedAt, offline: offline),
      const SizedBox(height: NiuSpacing.xs),
      Text('僅供參考，以學校審核結果為準', style: theme.textTheme.labelMedium),
    ];
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.sm,
        NiuSpacing.gutter,
        NiuSpacing.huge,
      ),
      children: children,
    );
    if (!model.allComplete) return list;
    return Stack(
      children: [
        list,
        const Positioned.fill(child: GraduationConfetti()),
      ],
    );
  }
}

/// Whether [data] meets every requirement, for the confetti over a page
/// that embeds the dashboard.
bool graduationComplete(GraduationData data) => GraduationPresentation(
  hours: data.hours,
  credits: data.credits,
  english: data.english,
  fitness: data.fitness,
  program: data.program,
).allComplete;

String _quantity(double? value) => value == null
    ? '—'
    : value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

Color _tint(BuildContext context, double progress) {
  final colors = NiuColors.of(context);
  if (progress >= 1) return colors.success;
  if (progress >= .6) return colors.accent;
  return colors.warning;
}

class _Overview extends StatelessWidget {
  const _Overview({required this.progress, required this.complete});
  final double? progress;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    // 100% only when everything is met, never from rounding up 99.6%.
    final percent = progress == null
        ? null
        : complete
        ? 100
        : min(99, (progress! * 100).round());
    return Semantics(
      label:
          '整體達成度 ${percent == null ? '資料待確認' : '$percent%'}'
          '${complete ? '，恭喜！已全數完成！' : ''}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(NiuSpacing.xl),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NiuRadius.card),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.accent, colors.accent.withValues(alpha: .78)],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '整體達成度',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onAccent.withValues(alpha: .85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: NiuSpacing.xs),
                  Text.rich(
                    key: const ValueKey('graduation-overall'),
                    TextSpan(
                      children: [
                        TextSpan(
                          text: percent == null ? '—' : '$percent',
                          style: theme.textTheme.displayMedium?.copyWith(
                            color: colors.onAccent,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                        if (percent != null)
                          TextSpan(
                            text: ' %',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: colors.onAccent.withValues(alpha: .85),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (complete)
                    Text(
                      '恭喜！已全數完成！',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onAccent,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: NiuSpacing.lg),
            SizedBox.square(
              dimension: 84,
              child: CustomPaint(
                painter: _RingPainter(
                  value: progress ?? 0,
                  track: colors.onAccent.withValues(alpha: .22),
                  color: colors.onAccent,
                ),
                child: Center(
                  child: Icon(
                    NiuIcons.graduation,
                    color: colors.onAccent,
                    size: 28,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.track, required this.color});
  final double value;
  final Color track, color;
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final arc = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      arc,
      0,
      6.2832,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (value <= 0) return;
    canvas.drawArc(
      arc,
      -1.5708,
      6.2832 * value.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.track != track || old.color != color;
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => NiuCard(
    padding: const EdgeInsets.all(NiuSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: NiuColors.of(context).accent),
            const SizedBox(width: NiuSpacing.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: NiuSpacing.lg),
        child,
      ],
    ),
  );
}

class _HoursRow extends StatelessWidget {
  const _HoursRow({required this.label, required this.requirement});
  final String label;
  final GraduationRequirement requirement;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final progress = requirement.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(label, style: text.titleSmall)),
            const SizedBox(width: NiuSpacing.sm),
            Text(
              requirement.nonApplicable
                  ? '不計入'
                  : '${_quantity(requirement.earned)} / ${_quantity(requirement.required)}',
              style: text.bodySmall?.copyWith(fontFeatures: tabularFigures),
            ),
          ],
        ),
        if (!requirement.nonApplicable) ...[
          const SizedBox(height: 6),
          NiuProgressBar(
            value: progress ?? 0,
            color: _tint(context, progress ?? 0),
            semanticLabel: requirement.label,
          ),
        ],
      ],
    );
  }
}

class _CreditsRow extends StatelessWidget {
  const _CreditsRow({required this.requirement});
  final GraduationRequirement requirement;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    final progress = requirement.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _quantity(requirement.earned),
                      style: text.displaySmall,
                    ),
                    TextSpan(
                      text: ' / ${_quantity(requirement.required)}',
                      style: text.titleLarge?.copyWith(
                        color: colors.inkSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(fontFeatures: tabularFigures),
              ),
            ),
            Text(
              progress == null ? '—' : '${(progress * 100).round()}%',
              style: text.titleSmall?.copyWith(color: colors.inkSecondary),
            ),
          ],
        ),
        const SizedBox(height: NiuSpacing.md),
        NiuProgressBar(value: progress ?? 0, semanticLabel: '畢業學分'),
      ],
    );
  }
}

class _AbilityTile extends StatelessWidget {
  const _AbilityTile({
    required this.icon,
    required this.title,
    required this.requirement,
  });
  final IconData icon;
  final String title;
  final GraduationRequirement requirement;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    final passed = requirement.status == GraduationStatus.passed;
    final tint = passed ? colors.success : colors.warning;
    final value = requirement.source.isEmpty ? '尚未登錄' : requirement.source;
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: NiuSpacing.sm),
              Expanded(child: Text(title, style: text.titleSmall)),
            ],
          ),
          const SizedBox(height: NiuSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  passed ? Icons.verified_rounded : Icons.error_rounded,
                  size: 18,
                  color: tint,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: text.titleMedium?.copyWith(color: tint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
