/// Account-bound school snapshot. Empty school values remain unknown in the UI.
class CachedGraduation {
  CachedGraduation({
    required this.account,
    required DateTime fetchedAt,
    required Map<String, dynamic> data,
  }) : fetchedAt = fetchedAt.toUtc(),
       data = _validate(data) {
    if (account.isEmpty || account != account.trim().toLowerCase()) {
      throw const FormatException('Invalid graduation cache account');
    }
  }

  final String account;
  final DateTime fetchedAt;
  final Map<String, dynamic> data;

  factory CachedGraduation.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['account'] is! String ||
        json['fetchedAt'] is! String ||
        json['data'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid graduation cache');
    }
    return CachedGraduation(
      account: json['account'] as String,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      data: json['data'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'account': account,
    'fetchedAt': fetchedAt.toIso8601String(),
    'data': data,
  };

  static Map<String, dynamic> _validate(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final key in ['diverseHours', 'creditRequired']) {
      final value = data[key];
      if (value is! List || value.any((element) => element is! String)) {
        throw const FormatException('Invalid graduation quantities');
      }
      result[key] = List<String>.unmodifiable(value);
    }
    for (final key in ['englishAbility', 'physicalFitness', 'creditCourse']) {
      if (data[key] is! String) {
        throw const FormatException('Invalid graduation qualification');
      }
      result[key] = data[key];
    }
    return Map.unmodifiable(result);
  }
}
