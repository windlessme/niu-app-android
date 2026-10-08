import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import 'moodle_questions.dart';

/// Splits Moodle numbering (「a. 」「1. 」) from an option so it can sit in
/// the answer mark, as on iOS.
({String? marker, String text}) optionText(String label) {
  final match = RegExp(r'^([A-Za-z]|\d{1,2})[.)．、]\s*').firstMatch(label);
  if (match == null) return (marker: null, text: label);
  return (
    marker: match.group(1)!.toUpperCase(),
    text: label.substring(match.end),
  );
}

/// The answer-card mark: hollow when empty, filled like a pencilled bubble
/// when chosen.
class AnswerMark extends StatelessWidget {
  const AnswerMark({
    super.key,
    required this.filled,
    this.square = false,
    this.marker,
    this.width = 34,
    this.height = 22,
  });
  final bool filled, square;
  final String? marker;
  final double width, height;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? colors.ink : null,
          borderRadius: BorderRadius.circular(square ? 5 : height / 2),
          border: filled
              ? null
              : Border.all(
                  color: colors.ink.withValues(alpha: .45),
                  width: 1.5,
                ),
        ),
        child: marker != null
            ? Text(
                marker!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: filled ? colors.surface : colors.inkSecondary,
                ),
              )
            : filled && square
            ? Icon(Icons.check_rounded, size: 14, color: colors.surface)
            : null,
      ),
    );
  }
}

/// A question number on the answer card; [current] marks this page.
class AnswerBubble extends StatelessWidget {
  const AnswerBubble({
    super.key,
    required this.number,
    required this.filled,
    this.invalid = false,
    this.current = false,
  });
  final String number;
  final bool filled, invalid, current;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: filled ? colors.ink : null,
              borderRadius: BorderRadius.circular(NiuRadius.pill),
              border: invalid
                  ? Border.all(color: colors.error, width: 2)
                  : filled
                  ? null
                  : Border.all(
                      color: colors.ink.withValues(alpha: .45),
                      width: 1.5,
                    ),
            ),
            // Shrink-wraps the number, also as a ListTile leading.
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                number,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                  color: filled ? colors.surface : colors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 14,
            height: 3,
            decoration: BoxDecoration(
              color: current ? colors.accent : null,
              borderRadius: BorderRadius.circular(NiuRadius.pill),
            ),
          ),
        ],
      ),
    );
  }
}

/// The school's countdown; red in the last minute.
class TimerChip extends StatelessWidget {
  const TimerChip({super.key, required this.seconds});
  final int seconds;

  static String format(int seconds) {
    String two(int v) => v.toString().padLeft(2, '0');
    return seconds >= 3600
        ? '${seconds ~/ 3600}:${two(seconds % 3600 ~/ 60)}:${two(seconds % 60)}'
        : '${two(seconds ~/ 60)}:${two(seconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final tone = seconds <= 60
        ? NiuTone.error
        : seconds <= 300
        ? NiuTone.warning
        : NiuTone.neutral;
    final fg = tone == NiuTone.neutral
        ? NiuColors.of(context).ink
        : tone.foreground(context);
    return Semantics(
      label: '剩餘時間 ${seconds ~/ 60} 分 ${seconds % 60} 秒；時間到會由校方自動交卷',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: tone.background(context),
          borderRadius: BorderRadius.circular(NiuRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: fg),
            const SizedBox(width: 4),
            Text(
              format(seconds),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Changes a field from its answer at the time of the change, not as it was
/// at build: two quick taps must both count.
typedef AnswerUpdate = void Function(List<String> Function(List<String> now));

/// One answerable field: options, a compact picker for blanks and matching
/// stems, an order list or a text box.
class QuestionFieldView extends StatelessWidget {
  const QuestionFieldView({
    super.key,
    required this.field,
    required this.values,
    required this.enabled,
    required this.onChanged,
    required this.controller,
  });
  final MoodleQuestionField field;
  final List<String> values;
  final bool enabled;
  final AnswerUpdate onChanged;

  /// Only used by text fields.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = field.questionId == null
        ? field.label
        : field.kind != 'order'
        ? field.part
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (field.context case final context? when context.isNotEmpty) ...[
          SelectableText(
            context,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: NiuSpacing.md),
        ],
        if (heading != null && heading.isNotEmpty) ...[
          Text(
            heading + (field.required ? '（必填）' : ''),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: NiuSpacing.sm),
        ],
        switch (field.kind) {
          'order' => _OrderList(
            field: field,
            order: values,
            enabled: enabled,
            onChanged: onChanged,
          ),
          // Blanks and matching stems share one option set; a picker keeps
          // each row short.
          'single' when field.part != null => _CompactPicker(
            field: field,
            values: values,
            enabled: enabled,
            onChanged: onChanged,
          ),
          'single' || 'multiple' => _OptionList(
            field: field,
            values: values,
            enabled: enabled,
            onChanged: onChanged,
          ),
          _ => TextField(
            controller: controller,
            enabled: enabled,
            minLines: field.kind == 'longText' ? 5 : 1,
            maxLines: field.kind == 'longText' ? 12 : 1,
            decoration: InputDecoration(
              hintText: '輸入答案',
              labelText: field.questionId == null ? null : field.part,
            ),
            onChanged: (v) => onChanged((_) => [v]),
          ),
        },
      ],
    );
  }
}

class _OptionList extends StatelessWidget {
  const _OptionList({
    required this.field,
    required this.values,
    required this.enabled,
    required this.onChanged,
  });
  final MoodleQuestionField field;
  final List<String> values;
  final bool enabled;
  final AnswerUpdate onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final choices = [
      for (final o in field.options)
        if (!o.blank) o,
    ];
    final multiple = field.kind == 'multiple';
    final blank = field.options.where((o) => o.blank).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
            child: Builder(
              builder: (context) {
                final selected = values.contains(option.id);
                final parts = optionText(option.label);
                final active = enabled && !option.disabled;
                return Semantics(
                  label: option.label,
                  button: true,
                  selected: selected,
                  enabled: active,
                  excludeSemantics: true,
                  child: Material(
                    color: selected
                        ? colors.ink.withValues(alpha: .07)
                        : colors.fill,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(NiuRadius.md),
                      side: BorderSide(
                        color: selected
                            ? colors.ink.withValues(alpha: .5)
                            : Colors.transparent,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: active
                          ? () => onChanged(
                              (now) => !multiple
                                  ? [option.id]
                                  : now.contains(option.id)
                                  ? [
                                      for (final v in now)
                                        if (v != option.id) v,
                                    ]
                                  : [...now, option.id],
                            )
                          : null,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: NiuSize.touchTarget,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: NiuSpacing.md,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              AnswerMark(
                                filled: selected,
                                square: multiple,
                                marker: parts.marker,
                              ),
                              const SizedBox(width: NiuSpacing.md),
                              Expanded(
                                child: Text(
                                  parts.text,
                                  style: TextStyle(
                                    color: active ? null : colors.inkTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        // A placeholder entry means Moodle lets the student clear this blank.
        if (blank != null && values.any((v) => choices.any((c) => c.id == v)))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: enabled ? () => onChanged((_) => [blank.id]) : null,
              child: const Text('清除這格的選擇'),
            ),
          ),
      ],
    );
  }
}

/// Blanks and matching stems: one short row that expands its options in
/// place.
class _CompactPicker extends StatefulWidget {
  const _CompactPicker({
    required this.field,
    required this.values,
    required this.enabled,
    required this.onChanged,
  });
  final MoodleQuestionField field;
  final List<String> values;
  final bool enabled;
  final AnswerUpdate onChanged;
  @override
  State<_CompactPicker> createState() => _CompactPickerState();
}

class _CompactPickerState extends State<_CompactPicker> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final field = widget.field;
    final choices = [
      for (final o in field.options)
        if (!o.blank) o,
    ];
    final selected = choices
        .where((c) => widget.values.contains(c.id))
        .firstOrNull;
    final blank = field.options.where((o) => o.blank).firstOrNull;
    void choose(String id) {
      widget.onChanged((_) => [id]);
      setState(() => open = false);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: field.part ?? field.label,
          value: selected?.label ?? '未作答',
          hint: open ? '收合選項' : '展開選項',
          button: true,
          excludeSemantics: true,
          child: Material(
            color: colors.fill,
            borderRadius: BorderRadius.circular(NiuRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.enabled ? () => setState(() => open = !open) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: NiuSize.touchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.md,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      AnswerMark(
                        filled: selected != null,
                        width: 22,
                        height: 14,
                      ),
                      const SizedBox(width: NiuSpacing.md),
                      Expanded(
                        child: Text(
                          selected?.label ?? '選擇答案',
                          style: TextStyle(
                            color: selected == null
                                ? colors.inkSecondary
                                : null,
                          ),
                        ),
                      ),
                      Icon(
                        open
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: colors.inkSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (open) ...[
          for (final option in choices)
            Semantics(
              label: option.label,
              button: true,
              selected: option.id == selected?.id,
              excludeSemantics: true,
              child: InkWell(
                onTap: option.disabled ? null : () => choose(option.id),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NiuSpacing.xxl,
                      NiuSpacing.sm,
                      NiuSpacing.md,
                      NiuSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        AnswerMark(
                          filled: option.id == selected?.id,
                          width: 22,
                          height: 14,
                        ),
                        const SizedBox(width: NiuSpacing.md),
                        Expanded(child: Text(option.label)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (selected != null && blank != null)
            Padding(
              padding: const EdgeInsets.only(left: NiuSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => choose(blank.id),
                  child: const Text('清除這格'),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.field,
    required this.order,
    required this.enabled,
    required this.onChanged,
  });
  final MoodleQuestionField field;
  final List<String> order;
  final bool enabled;
  final AnswerUpdate onChanged;

  /// Moves [id] one place; taps in a row each start from the latest order.
  void move(String id, int by) => onChanged((now) {
    final from = now.indexOf(id), to = from + by;
    if (from < 0 || to < 0 || to >= now.length) return now;
    return [...now]
      ..[from] = now[to]
      ..[to] = id;
  });

  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (index, id) in order.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
            child: Builder(
              builder: (context) {
                final label =
                    field.options.where((o) => o.id == id).firstOrNull?.label ??
                    '';
                return Semantics(
                  value: '第 ${index + 1} 項，共 ${order.length} 項',
                  child: NiuWell(
                    padding: const EdgeInsets.only(left: NiuSpacing.sm),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.inkSecondary,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ),
                        const SizedBox(width: NiuSpacing.sm),
                        Expanded(child: Text(label)),
                        IconButton(
                          tooltip: '上移「$label」',
                          icon: const Icon(Icons.arrow_upward_rounded),
                          onPressed: enabled && index > 0
                              ? () => move(id, -1)
                              : null,
                        ),
                        IconButton(
                          tooltip: '下移「$label」',
                          icon: const Icon(Icons.arrow_downward_rounded),
                          onPressed: enabled && index < order.length - 1
                              ? () => move(id, 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Grade, attempts, notices and quiz dates from an overview or review page.
class QuestionResultView extends StatelessWidget {
  const QuestionResultView({super.key, required this.result});
  final MoodleQuestionResult result;

  static bool isStatus(MoodleQuestionDetail d) =>
      const {'作答狀態', '狀態', 'status', 'state'}.contains(d.label.toLowerCase());

  static String infoLabel(String label) => switch (label) {
    '開始' || 'Opened' || 'Opens' => '開放時間',
    '結束' || 'Closed' || 'Closes' => '截止時間',
    _ => label,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    Widget rows(List<MoodleQuestionDetail> details, {bool info = false}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, d) in details.indexed) ...[
              if (i > 0) Divider(height: NiuSpacing.lg, color: colors.hairline),
              Text(
                info ? infoLabel(d.label) : d.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.inkSecondary,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                d.value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.grade case final grade?)
          NiuCard(
            color: colors.accentSoft,
            padding: const EdgeInsets.all(NiuSpacing.xl),
            child: NiuStat(
              label: result.gradeLabel ?? '成績',
              value: grade,
              color: colors.accent,
              large: true,
            ),
          ),
        if (result.attempts.isNotEmpty) ...[
          const SizedBox(height: NiuSpacing.lg),
          Text('作答紀錄', style: theme.textTheme.titleMedium),
          for (final attempt in result.attempts) ...[
            const SizedBox(height: NiuSpacing.md),
            NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(attempt.title, style: theme.textTheme.titleSmall),
                  if (attempt.details.where(isStatus).firstOrNull
                      case final status?) ...[
                    const SizedBox(height: NiuSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NiuBadge(
                        label: status.value,
                        tone: NiuTone.accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: NiuSpacing.md),
                  rows([
                    for (final d in attempt.details)
                      if (!isStatus(d)) d,
                  ]),
                ],
              ),
            ),
          ],
        ],
        for (final notice in result.notices) ...[
          const SizedBox(height: NiuSpacing.md),
          NiuBanner(tone: NiuTone.neutral, message: notice),
        ],
        if (result.information.isNotEmpty) ...[
          const SizedBox(height: NiuSpacing.md),
          NiuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('測驗資訊', style: theme.textTheme.titleSmall),
                const SizedBox(height: NiuSpacing.md),
                rows(result.information, info: true),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One reviewed question, read-only.
class QuestionReviewCard extends StatelessWidget {
  const QuestionReviewCard({
    super.key,
    required this.question,
    required this.onOpen,
  });
  final MoodleReviewQuestion question;
  final VoidCallback onOpen;

  static (String, NiuTone)? verdict(String? value) => switch (value) {
    'correct' => ('正確', NiuTone.success),
    'partiallycorrect' => ('部分正確', NiuTone.warning),
    'incorrect' => ('錯誤', NiuTone.error),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    Widget block(String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: NiuSpacing.sm),
            child: NiuWell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  SelectableText(value),
                ],
              ),
            ),
          );
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(question.title, style: theme.textTheme.titleMedium),
              ),
              if (verdict(question.verdict) case (final label, final tone))
                NiuBadge(label: label, tone: tone),
            ],
          ),
          if ([question.status, question.mark].any((s) => s.isNotEmpty))
            Text(
              [
                question.status,
                question.mark,
              ].where((s) => s.isNotEmpty).join('・'),
              style: theme.textTheme.bodySmall,
            ),
          if (question.text.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.sm),
            SelectableText(question.text),
          ],
          if (question.prompt.isNotEmpty)
            Text(question.prompt, style: theme.textTheme.bodySmall),
          for (final choice in question.choices)
            Padding(
              padding: const EdgeInsets.only(top: NiuSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    choice.selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: switch (choice.verdict) {
                      'correct' => colors.success,
                      'incorrect' => colors.error,
                      'partiallycorrect' => colors.warning,
                      _ => colors.inkTertiary,
                    },
                  ),
                  const SizedBox(width: NiuSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(choice.text),
                        if (choice.feedback.isNotEmpty)
                          Text(
                            choice.feedback,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          block(
            '你的作答',
            question.responses.map((r) => r.isEmpty ? '未填答' : r).join('\n'),
          ),
          block('正確答案', question.correctAnswer),
          block('作答回饋', question.feedback),
          block('題目解析', question.generalFeedback),
          block('教師評語', question.comment),
          if (question.webReason case final reason?) ...[
            const SizedBox(height: NiuSpacing.sm),
            Text(reason, style: theme.textTheme.bodySmall),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onOpen, child: const Text('查看本題完整內容')),
          ),
        ],
      ),
    );
  }
}
