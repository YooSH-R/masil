/// 산책 날짜와 통계의 기준 시간대.
///
/// 한국은 일광 절약 시간이 없으므로 UTC+9 고정 오프셋으로 안전하게 변환할 수
/// 있다. 기기 시간대가 해외로 설정되어 있어도 산책 날짜는 한국 기준으로 유지한다.
class KoreaTime {
  KoreaTime._();

  static const Duration offset = Duration(hours: 9);

  static DateTime now() => fromInstant(DateTime.now());

  /// 절대 시각을 한국의 벽시계 시각으로 바꾼다.
  ///
  /// 반환값은 날짜·달력 계산용이므로 로컬 DateTime으로 만든다. 모든 입력을 먼저
  /// UTC로 정규화해 실행 기기의 시간대가 결과에 영향을 주지 않게 한다.
  static DateTime fromInstant(DateTime value) {
    final shifted = value.toUtc().add(offset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
      shifted.microsecond,
    );
  }

  static DateTime? fromNullableInstant(DateTime? value) =>
      value == null ? null : fromInstant(value);
}
