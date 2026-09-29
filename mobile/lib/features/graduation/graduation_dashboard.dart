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
  });
  final GraduationData data;
  final DateTime? updatedAt;
  final bool offline, needsReauthentication;

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.xl,
        NiuSpacing.sm,
        NiuSpacing.xl,
        NiuSpacing.xxxl,
      ),
      children: [
        if (widget.updatedAt != null) ...[
          RelativeUpdateText(updatedAt: widget.updatedAt),
          if (widget.offline || widget.needsReauthentication) ...[
            const SizedBox(height: NiuSpacing.xs),
            Text(
              widget.offline ? '離線' : '登入已過期',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: NiuSpacing.lg),
        ],
        _Overview(model: model),
        const SizedBox(height: NiuSpacing.lg),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in _StatusFilter.values)
              ChoiceChip(
                label: Text(switch (filter) {
                  _StatusFilter.all => '全部',
                  _StatusFilter.attention => '待處理',
                  _StatusFilter.completed => '已完成',
                }),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              ),
          ],
        ),
        if (_filter == _StatusFilter.attention) ...[
          const SizedBox(height: NiuSpacing.sm),
          const Text('包含尚未完成及資料待確認的項目'),
        ],
        if (!model.requirements.any(_visible)) ...[
          const SizedBox(height: NiuSpacing.xl),
          const AppCard(child: Text('目前沒有符合的項目')),
        ],
        if (_visible(model.credits)) ...[
          const SectionHeader(title: '畢業學分'),
          AppCard(
            child: _QuantityRow(requirement: model.credits, unit: '學分'),
          ),
        ],
        if (hours.isNotEmpty) ...[
          const SectionHeader(title: '多元學習時數', subtitle: '已修時數與應修門檻'),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < hours.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: NiuSpacing.lg,
                      ),
                      child: Divider(
                        height: 1,
                        color: NiuColors.of(context).separator,
                      ),
                    ),
                  _QuantityRow(requirement: hours[i], unit: '小時'),
                ],
              ],
            ),
          ),
        ],
        if (qualifications.isNotEmpty) ...[
          const SectionHeader(title: '能力資格與學程'),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final twoColumns = constraints.maxWidth >= 300 * scale;
              final width = twoColumns
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
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
        ],
        const SizedBox(height: NiuSpacing.xl),
        ExpansionTile(
          expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
              ? AnimationStyle.noAnimation
              : null,
          tilePadding: EdgeInsets.zero,
          title: const Text('計算方式與資料說明'),
          children: const [
            Padding(
              padding: EdgeInsets.only(bottom: NiuSpacing.lg),
              child: Text(
                '完成項目依已修數量達到應修門檻，或校方標示已通過計算。環形圖顯示已完成項目占適用項目的數量；資料待確認仍保留在總數中，不視為零進度。不計入項目排除。尚差數量僅於已修與應修皆已知時顯示，最低為 0。此為整理參考，非校方畢業資格審核結果。',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.model});
  final GraduationPresentation model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onPrimaryContainer;
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '畢業門檻',
          style: theme.textTheme.titleLarge?.copyWith(color: foreground),
        ),
        const SizedBox(height: NiuSpacing.sm),
        Text(
          '已完成 ${model.completedCount} 項',
          key: const ValueKey('graduation-overall'),
          style: theme.textTheme.titleMedium?.copyWith(color: foreground),
        ),
        const SizedBox(height: NiuSpacing.xs),
        Text('尚未完成 ${model.remainingCount} 項'),
        Text('資料待確認 ${model.missingCount} 項'),
      ],
    );
    final ring = Semantics(
      excludeSemantics: true,
      label:
          '${model.applicableCount} 項適用門檻，已完成 ${model.completedCount} 項，資料待確認 ${model.missingCount} 項',
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (model.measuredCount > 0)
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: model.completedCount / model.applicableCount,
                  strokeWidth: 5,
                  color: foreground,
                  backgroundColor: foreground.withValues(alpha: .16),
                ),
              )
            else
              SizedBox.expand(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: foreground.withValues(alpha: .16),
                      width: 5,
                    ),
                  ),
                ),
              ),
            Icon(Icons.school_outlined, color: foreground, size: 26),
          ],
        ),
      ),
    );
    return HeroCard(
      color: theme.colorScheme.primaryContainer,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            if (constraints.maxWidth < 210 * scale) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  const SizedBox(height: NiuSpacing.lg),
                  ring,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: summary),
                const SizedBox(width: NiuSpacing.lg),
                ring,
              ],
            );
          },
        ),
      ),
    );
  }
}

String _quantity(double? value) => value == null
    ? '—'
    : value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

class _QuantityRow extends StatelessWidget {
  const _QuantityRow({required this.requirement, required this.unit});
  final GraduationRequirement requirement;
  final String unit;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    final progress = requirement.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(requirement.label, style: text.titleMedium),
        const SizedBox(height: 6),
        Text(
          requirement.nonApplicable
              ? '${_quantity(requirement.earned)} $unit・不計入'
              : '${_quantity(requirement.earned)} / ${_quantity(requirement.required)} $unit',
          style: text.bodyMedium?.copyWith(color: colors.secondary),
        ),
        const SizedBox(height: 10),
        if (progress != null) ...[
          LinearProgressIndicator(
            value: progress,
            color: requirement.isComplete ? colors.success : colors.accent,
            backgroundColor: colors.elevated,
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            semanticsLabel: '${requirement.label}完成比例',
          ),
          const SizedBox(height: NiuSpacing.sm),
          Text(
            requirement.isComplete
                ? '已完成'
                : '尚差 ${_quantity(requirement.remaining)} $unit',
            style: text.bodyMedium,
          ),
        ] else
          Text(
            requirement.nonApplicable ? '此項不列入門檻' : '資料待確認，尚差數量未知',
            style: text.bodySmall?.copyWith(color: colors.secondary),
          ),
      ],
    );
  }
}

class _QualificationCard extends StatelessWidget {
  const _QualificationCard({required this.requirement});
  final GraduationRequirement requirement;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final text = Theme.of(context).textTheme;
    final (color, icon, label) = switch (requirement.status) {
      GraduationStatus.notTested => (
        colors.warning,
        Icons.schedule_outlined,
        '尚未檢測',
      ),
      GraduationStatus.passed => (
        colors.success,
        Icons.check_circle_outline,
        '已通過',
      ),
      GraduationStatus.failed => (colors.error, Icons.cancel_outlined, '未通過'),
      _ => (colors.secondary, Icons.help_outline, '資料待確認'),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              Text(requirement.label, style: text.titleMedium),
            ],
          ),
          const SizedBox(height: NiuSpacing.sm),
          Text(label, style: text.titleMedium?.copyWith(color: color)),
          if (requirement.source.isNotEmpty && requirement.source != label) ...[
            const SizedBox(height: NiuSpacing.sm),
            Text(
              requirement.source,
              style: text.bodySmall?.copyWith(color: colors.secondary),
            ),
          ],
          if (requirement.source.isEmpty) ...[
            const SizedBox(height: NiuSpacing.sm),
            Text('-', style: text.bodySmall?.copyWith(color: colors.secondary)),
          ],
        ],
      ),
    );
  }
}
