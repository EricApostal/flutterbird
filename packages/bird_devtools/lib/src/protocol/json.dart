/// Reading a server's JSON without trusting its shape: a field that is missing
/// or of another type reads as the empty value of the type asked for.
extension JsonRead on Map<String, Object?> {
  String str(String key, [String fallback = '']) {
    final value = this[key];
    return value is String ? value : fallback;
  }

  String? strOrNull(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  int integer(String key, [int fallback = 0]) {
    final value = this[key];
    if (value is num) return value.isFinite ? value.toInt() : fallback;
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  int? integerOrNull(String key) {
    final value = this[key];
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double number(String key, [double fallback = 0]) {
    final value = this[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  bool flag(String key) => this[key] == true;

  Map<String, Object?> obj(String key) {
    final value = this[key];
    return value is Map<String, Object?> ? value : const {};
  }

  Map<String, Object?>? mapOrNull(String key) {
    final value = this[key];
    return value is Map<String, Object?> ? value : null;
  }

  List<Object?> list(String key) {
    final value = this[key];
    return value is List<Object?> ? value : const [];
  }

  List<Map<String, Object?>> maps(String key) => [
    for (final entry in list(key))
      if (entry is Map<String, Object?>) entry,
  ];

  List<String> strings(String key) => [
    for (final entry in list(key))
      if (entry is String) entry,
  ];
}
