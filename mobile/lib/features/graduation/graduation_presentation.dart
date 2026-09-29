enum GraduationStatus { available, unknown, notTested, passed, failed }

class GraduationRequirement {
  const GraduationRequirement({
    required this.label,
    required this.status,
    this.source = '',
    this.earned,
    this.required,
    this.nonApplicable = false,
  });
  final String label, source;
  final GraduationStatus status;
  final double? earned, required;
  final bool nonApplicable;

  double? get remaining {
    if (nonApplicable || earned == null || required == null) return null;
    return (required! - earned!).clamp(0.0, double.infinity);
  }

  bool get isComplete => !nonApplicable && progress == 1;
  bool get isUnknown => !nonApplicable && progress == null;
  bool get needsAttention => !nonApplicable && !isComplete;

  double? get progress {
    if (nonApplicable) return null;
    if (earned != null && required != null && required! > 0) {
      return (earned! / required!).clamp(0.0, 1.0);
    }
    return switch (status) {
      GraduationStatus.passed => 1,
      GraduationStatus.failed || GraduationStatus.notTested => 0,
      _ => null,
    };
  }

  static double? number(String value) {
    final parsed = double.tryParse(value.trim());
    return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
  }

  factory GraduationRequirement.quantity(
    String label,
    String earned,
    String required,
  ) {
    final actual = number(earned);
    final target = number(required);
    final nonApplicable = required.trim() == '不計入' || target == 0;
    return GraduationRequirement(
      label: label,
      status: nonApplicable || (actual != null && target != null)
          ? GraduationStatus.available
          : GraduationStatus.unknown,
      earned: actual,
      required: target,
      nonApplicable: nonApplicable,
    );
  }

  factory GraduationRequirement.qualification(String label, String source) {
    final value = source.trim();
    // Unfamiliar school prose must not imply approval.
    final status = switch (value) {
      '未檢測' || '尚未檢測' || '未測驗' || '尚未測驗' || '未測試' => GraduationStatus.notTested,
      '通過' || '已通過' || '合格' || '已達成' || '符合' || '達成' => GraduationStatus.passed,
      '未通過' || '不通過' || '不合格' || '未達成' || '不符合' => GraduationStatus.failed,
      _ => GraduationStatus.unknown,
    };
    return GraduationRequirement(label: label, status: status, source: value);
  }
}

class GraduationPresentation {
  GraduationPresentation({
    required List<String> hours,
    required List<String> credits,
    required String english,
    required String fitness,
    required String program,
  }) : hours = [
         for (var i = 0; i < 4; i++)
           GraduationRequirement.quantity(
             const ['服務學習', '多元學習', '專業學習', '綜合學習'][i],
             i * 2 < hours.length ? hours[i * 2] : '',
             i * 2 + 1 < hours.length ? hours[i * 2 + 1] : '',
           ),
       ],
       credits = GraduationRequirement.quantity(
         '畢業學分',
         credits.length > 1 ? credits[1] : '',
         credits.isNotEmpty ? credits[0] : '',
       ),
       qualifications = [
         GraduationRequirement.qualification('外語能力', english),
         GraduationRequirement.qualification('體適能', fitness),
       ],
       program = GraduationRequirement.qualification('學分學程', program);
  final List<GraduationRequirement> hours, qualifications;
  final GraduationRequirement credits, program;
  List<GraduationRequirement> get requirements => [
    ...hours,
    ...qualifications,
    credits,
    program,
  ];
  int get measuredCount => requirements.where((r) => r.progress != null).length;
  int get completedCount => requirements.where((r) => r.isComplete).length;
  int get remainingCount =>
      requirements.where((r) => r.needsAttention && !r.isUnknown).length;
  int get applicableCount => requirements.where((r) => !r.nonApplicable).length;
  int get missingCount =>
      requirements.where((r) => !r.nonApplicable && r.progress == null).length;
  double? get progress {
    final known = requirements
        .map((r) => r.progress)
        .whereType<double>()
        .toList();
    return known.isEmpty ? null : known.reduce((a, b) => a + b) / known.length;
  }
}
