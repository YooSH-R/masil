import 'package:flutter_test/flutter_test.dart';

import 'package:mysil_project_new/core/utils/korea_time.dart';

void main() {
  test('UTC 오후 시각이 한국 기준 다음 날짜로 넘어간다', () {
    final korea = KoreaTime.fromInstant(DateTime.utc(2026, 8, 5, 15, 30));

    expect(korea, DateTime(2026, 8, 6, 0, 30));
  });
}
