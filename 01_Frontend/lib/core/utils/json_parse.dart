/// 서버 응답을 안전하게 읽기 위한 헬퍼.
/// 명세서와 실제 구현이 어긋나도(문자열/숫자 혼용, 필드 누락) 앱이 죽지 않게 한다.
class Json {
  Json._();

  static Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static Map<String, dynamic>? asMapOrNull(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<Map<String, dynamic>> asMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(asMapOrNull)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  static int asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int? asIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double asDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static double? asDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String asString(dynamic value, {String fallback = ''}) =>
      value?.toString() ?? fallback;

  static String? asStringOrNull(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static bool asBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return fallback;
  }

  /// ISO 8601 UTC 문자열 → DateTime (로컬 변환은 화면에서 처리).
  static DateTime? asDateTime(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  /// 문자열 상태값을 enum으로. 매칭 실패 시 fallback.
  static T asEnum<T>(
    dynamic value,
    Map<String, T> mapping,
    T fallback,
  ) {
    final key = value?.toString().toUpperCase();
    if (key == null) return fallback;
    return mapping[key] ?? fallback;
  }
}
