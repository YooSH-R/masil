import 'package:flutter_test/flutter_test.dart';
import 'package:mysil_project_new/core/utils/walk_log_markdown.dart';

/// 실제 `walk_log.md` 와 같은 형태. 05_AI/outputs 의 산출물에서 가져왔다.
const _realDiary = '''
## 2026-07-31 산책 일지

**한 줄 요약**: 차분한 실내 공간 속 집중의 온기

바깥 날씨나 하루의 시간대를 가늠할 수 없는 차분한 실내 공간을 걸었다.
넓은 공동 작업 공간에는 많은 사람들이 저마다 책상에 앉아 있었다.
''';

void main() {
  group('summaryLine', () {
    test('한 줄 요약이 있으면 콜론 뒤를 쓴다', () {
      expect(
        WalkLogMarkdown.summaryLine(_realDiary),
        '차분한 실내 공간 속 집중의 온기',
      );
    });

    test('마크다운 기호가 남지 않는다', () {
      final summary = WalkLogMarkdown.summaryLine(_realDiary)!;

      expect(summary.contains('#'), isFalse);
      expect(summary.contains('**'), isFalse);
    });

    test('한 줄 요약이 없으면 제목이 아닌 첫 문장을 쓴다', () {
      const markdown = '''
# 산책 일지

오늘은 공원을 한 바퀴 돌았다.
''';

      expect(WalkLogMarkdown.summaryLine(markdown), '오늘은 공원을 한 바퀴 돌았다.');
    });

    test('제목만 있으면 null 이다', () {
      expect(WalkLogMarkdown.summaryLine('## 2026-08-07 산책 일지'), isNull);
    });

    test('비어 있거나 null 이면 null 이다', () {
      expect(WalkLogMarkdown.summaryLine(null), isNull);
      expect(WalkLogMarkdown.summaryLine('   \n  '), isNull);
    });

    test('글머리표 기호도 걷어낸다', () {
      const markdown = '- 오늘 만난 것: 고양이, 은행나무, 자전거';

      expect(
        WalkLogMarkdown.summaryLine(markdown),
        '오늘 만난 것: 고양이, 은행나무, 자전거',
      );
    });
  });

  group('toPlainText', () {
    test('모든 마크다운 기호를 걷어내고 한 덩어리로 합친다', () {
      final plain = WalkLogMarkdown.toPlainText(_realDiary);

      expect(plain.contains('##'), isFalse);
      expect(plain.contains('**'), isFalse);
      expect(plain.contains('\n'), isFalse);
      expect(plain, startsWith('2026-07-31 산책 일지'));
      expect(plain, contains('한 줄 요약'));
    });

    test('null 이면 빈 문자열이다', () {
      expect(WalkLogMarkdown.toPlainText(null), '');
    });
  });

  group('stripMarkers', () {
    test('제목·글머리표·굵게 기호를 지우고 글자는 남긴다', () {
      expect(WalkLogMarkdown.stripMarkers('### **오늘의 산책**'), '오늘의 산책');
      expect(WalkLogMarkdown.stripMarkers('* 첫째'), '첫째');
      expect(WalkLogMarkdown.stripMarkers('- 둘째'), '둘째');
      expect(WalkLogMarkdown.stripMarkers('`코드`'), '코드');
    });

    test('기호가 없는 줄은 그대로 둔다', () {
      expect(WalkLogMarkdown.stripMarkers('평범한 문장이다.'), '평범한 문장이다.');
    });
  });
}
