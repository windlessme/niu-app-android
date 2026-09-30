import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'graduation_presentation.dart';
import 'graduation_screen.dart';

enum _StatusFilter { all, attention, completed }

class GraduationDashboard extends StatefulWidget {
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
  State<GraduationDashboard> createState() => _GraduationDashboardState();
}

class _GraduationDashboardState extends State<GraduationDashboard> {
  _StatusFilter _filter = _StatusFilter.all;

  bool _visible(GraduationRequirement requirement) => switch (_filter) {
    _StatusFilter.all => true,
    _StatusFilter.attention => requirement.needsAttention,
    _StatusFilter.completed => requirement.isComplete,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = GraduationPresentation(
      hours: widget.data.hours,
      credits: widget.data.credits,
      english: widget.data.english,
      fitness: widget.data.fitness,
      program: widget.data.program,
    );
    final hours = model.hours.where(_visible).toList();
    final qualifications = [
      ...model.qualifications,
      model.program,
    ].where(_visible).toList();
    final children = <Widget>[
      if (widget.needsReauthentication) ...[
        const NiuBanner(tone: NiuTone.warning, message: '校務登入已過期，先顯示上次保存的資料。'),
        const SizedBox(height: NiuSpacing.lg),
      ],
      _Overview(model: model),
      const SizedBox(height: NiuSpacing.lg),
      NiuSegmented<_StatusFilter>(
        segments: const [
          (_StatusFilter.all, '全部'),
          (_StatusFilter.attention, '待處理'),
          (_StatusFilter.completed, '已完成'),
        ],
        value: _filter,
        onChanged: (filter) => setState(() => _filter = filter),
      ),
      if (_filter == _StatusFilter.attention) ...[
        const SizedBox(height: NiuSpacing.sm),
        Text(
          '包含尚未完成及資料待確認的項目',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium,
        ),
      ],
      if (!model.requirements.any(_visible))
        const Padding(
          padding: EdgeInsets.only(top: NiuSpacing.lg),
          child: NiuCard(
            child: NiuEmpty(
              padding: EdgeInsets.symmetric(vertical: NiuSpacing.xl),
              icon: NiuIcons.graduation,
              title: '目前沒有符合的項目',
            ),
          ),
        ),
      if (_visible(model.credits))
        NiuSection(
          title: '畢業學分',
          child: NiuCard(
            padding: const EdgeInsets.all(NiuSpacing.xl),
            child: _QuantityRow(
              requirement: model.credits,
              unit: '學分',
              prominent: true,
            ),
          ),
        ),
      if (hours.isNotEmpty)
        NiuSection(
          title: '多元學習時數',
          subtitle: '已完成時數／應修時數',
          child: NiuCard(
            child: Column(
              children: [
                for (var i = 0; i < hours.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: NiuSpacing.md),
                      child: Divider(),
                    ),
                  _QuantityRow(requirement: hours[i], unit: '小時'),
                ],
              ],
            ),
          ),
        ),
      if (qualifications.isNotEmpty)
        NiuSection(
          title: '能力檢定與學程',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final twoColumns = constraints.maxWidth >= 300 * scale;
              final width = twoColumns
                  ? (constraints.maxWidth - NiuSpacing.md) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: NiuSpacing.md,
                runSpacing: NiuSpacing.md,
                children: [
                  for (final requirement in qualifications)
                    SizedBox(
                      width: width,
                      child: _QualificationCard(requirement: requirement),
                    ),
                ],
              );
            },
          ),
        ),
      const SizedBox(height: NiuSpacing.xl),
      NiuCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
                ? AnimationStyle.noAnimation
                : null,
            tilePadding: const EdgeInsets.symmetric(horizontal: NiuSpacing.lg),
            childrenPadding: const EdgeInsets.fromLTRB(
              NiuSpacing.lg,
              0,
              NiuSpacing.lg,
              NiuSpacing.lg,
            ),
            leading: Icon(
              NiuIcons.info,
              color: NiuColors.of(context).inkSecondary,
            ),
            title: Text('計算方式與資料說明', style: theme.textTheme.titleSmall),
            children: [
              Text(
                '已修數量達到應修門檻，或學校標示為通過，即算完成。環形圖顯示已完成項目占適用項目的比例；資料待確認的項目仍計入總數，但不當作零進度，不計入的項目則排除。尚差數量只在已修與應修都已知時顯示，最低為 0。以上為整理參考，非校方畢業資格審核結果。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      if (widget.updatedAt != null) ...[
        const SizedBox(height: NiuSpacing.lg),
        NiuSyncStatus(updatedAt: widget.updatedAt, offline: widget.offline),
      ],
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.sm,
        NiuSpacing.gutter,
        NiuSpacing.huge,
      ),
      children: children,
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.model});
  final GraduationPresentation model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('畢業進度', style: theme.textTheme.labelMedium),
        const SizedBox(height: NiuSpacing.xs),
        Text(
          '已完成 ${model.completedCount} 項',
          key: const ValueKey('graduation-overall'),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: NiuSpacing.sm),
        Wrap(
          spacing: NiuSpacing.sm,
          runSpacing: NiuSpacing.xs,
          children: [
            NiuBadge(
              label: '尚未完成 ${model.remainingCount} 項',
              tone: model.remainingCount > 0
                  ? NiuTone.warning
                  : NiuTone.neutral,
            ),
            NiuBadge(label: '資料待確認 ${model.missingCount} 項'),
          ],
        ),
      ],
    );
    final fraction = model.applicableCount == 0
        ? 0.0
        : model.completedCount / model.applicableCount;
    final ring = Semantics(
      excludeSemantics: true,
      label:
          '${model.applicableCount} 項適用門檻，已完成 ${model.completedCount} 項，資料待確認 ${model.missingCount} 項',
      child: SizedBox.square(
        dimension: 84,
        child: CustomPaint(
          painter: _RingPainter(
            value: model.measuredCount > 0 ? fraction : 0,
            track: colors.fill,
            color: colors.success,
          ),
          child: Center(
            child: Text(
              '${model.completedCount}/${model.applicableCount}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
        ),
      ),
    );
    return NiuCard(
      padding: const EdgeInsets.all(NiuSpacing.xl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          if (constraints.maxWidth < 240 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ring,
                const SizedBox(height: NiuSpacing.lg),
                summary,
              ],
            );
          }
          return Row(
            children: [
              ring,
              const SizedBox(width: NiuSpacing.xl),
              Expanded(child: summary),
            ],
          );
        },
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
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(arc, 0, 6.2832, false, base);
    if (value <= 0) return;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(arc, -1.5708, 6.2832 * value.clamp(0, 1), false, fill);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.track != track || old.color != color;
}

String _quantity(double? value) => value == null
    ? '—'
    : value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

class _QuantityRow extends StatelessWidget {
  const _QuantityRow({
    required this.requirement,
    required this.unit,
    this.prominent = false,
  });
  final GraduationRequirement requirement;
  final String unit;
  final bool prominent;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    final progress = requirement.progress;
    final amount = requirement.nonApplicable
        ? '${_quantity(requirement.earned)} $unit・不計入'
        : '${_quantity(requirement.earned)} / ${_quantity(requirement.required)} $unit';
    final status = progress == null
        ? Text(
            requirement.nonApplicable ? '不列入門檻' : '資料待確認',
            style: text.labelMedium,
          )
        : requirement.isComplete
        ? const NiuBadge(label: '已完成', tone: NiuTone.success)
        : Text(
            '尚差 ${_quantity(requirement.remaining)} $unit',
            style: text.labelMedium?.copyWith(
              color: colors.warning,
              fontWeight: FontWeight.w600,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!prominent)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(requirement.label, style: text.titleMedium)),
              const SizedBox(width: NiuSpacing.sm),
              Flexible(
                child: Text(
                  amount,
                  textAlign: TextAlign.end,
                  style: text.bodyMedium?.copyWith(
                    color: colors.inkSecondary,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
            ],
          )
        else
          Text(
            amount,
            style: text.headlineSmall?.copyWith(fontFeatures: tabularFigures),
          ),
        const SizedBox(height: NiuSpacing.sm),
        if (progress != null) ...[
          NiuProgressBar(
            value: progress,
            color: requirement.isComplete ? colors.success : colors.accent,
            semanticLabel: '${requirement.label}完成比例',
          ),
          const SizedBox(height: NiuSpacing.sm),
        ],
        Align(alignment: Alignment.centerLeft, child: status),
      ],
    );
  }
}

class _QualificationCard extends StatelessWidget {
  const _QualificationCard({required this.requirement});
  final GraduationRequirement requirement;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (tone, icon, label) = switch (requirement.status) {
      GraduationStatus.notTested => (NiuTone.warning, NiuIcons.pending, '尚未檢測'),
      GraduationStatus.passed => (NiuTone.success, NiuIcons.success, '已通過'),
      GraduationStatus.failed => (NiuTone.error, NiuIcons.error, '未通過'),
      _ => (NiuTone.neutral, NiuIcons.neutral, '資料待確認'),
    };
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(requirement.label, style: text.titleMedium),
          const SizedBox(height: NiuSpacing.sm),
          NiuBadge(label: label, tone: tone, icon: icon),
          const SizedBox(height: NiuSpacing.sm),
          Text(
            requirement.source.isEmpty || requirement.source == label
                ? '-'
                : requirement.source,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
