import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysil_project_new/presentation/widgets/markdown_view.dart';

Future<void> _pump(
  WidgetTester tester,
  String markdown, {
  TextStyle? style,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(body: MarkdownView(markdown, baseStyle: style)),
  ));
}

/// 그려진 모든 조각의 스타일을 모은다.
List<TextStyle?> _renderedStyles(WidgetTester tester) {
  final styles = <TextStyle?>[];
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    text.textSpan?.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').isNotEmpty) {
        styles.add(span.style);
      }
      return true;
    });
  }
  return styles;
}

void main() {
  testWidgets('마크다운 기호가 화면에 보이지 않는다', (tester) async {
    await _pump(
      tester,
      '## 2026-08-07 산책 일지\n\n**한 줄 요약**: 바람이 좋았다\n\n- 고양이를 만났다',
    );

    expect(find.textContaining('#'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    // 글자는 남는다.
    expect(find.textContaining('산책 일지'), findsOneWidget);
    expect(find.textContaining('바람이 좋았다'), findsOneWidget);
    expect(find.textContaining('고양이를 만났다'), findsOneWidget);
  });

  testWidgets('굵게 표시한 부분만 굵게 그린다', (tester) async {
    await _pump(tester, '평범한 **강조** 문장');

    final bold = _renderedStyles(tester)
        .where((style) => style?.fontWeight == FontWeight.bold);
    final normal = _renderedStyles(tester)
        .where((style) => style?.fontWeight != FontWeight.bold);

    expect(bold, hasLength(1));
    expect(normal, isNotEmpty);
  });

  // 파싱 결과를 캐시하면서 스타일까지 함께 담아두면, 원문이 그대로인 채
  // baseStyle 만 바뀔 때 낡은 서식이 남는다. 그래서 캐시에는 스타일을 담지
  // 않는다. 이 테스트가 그 계약을 지킨다.
  testWidgets('원문이 그대로여도 baseStyle 이 바뀌면 서식이 따라 바뀐다',
      (tester) async {
    const markdown = '같은 본문입니다';

    await _pump(tester, markdown,
        style: const TextStyle(fontSize: 14, color: Color(0xFFFF0000)));
    expect(_renderedStyles(tester).first?.color, const Color(0xFFFF0000));

    await _pump(tester, markdown,
        style: const TextStyle(fontSize: 20, color: Color(0xFF0000FF)));

    final updated = _renderedStyles(tester).first;
    expect(updated?.color, const Color(0xFF0000FF));
    expect(updated?.fontSize, 20);
  });

  testWidgets('원문이 바뀌면 다시 파싱한다', (tester) async {
    await _pump(tester, '첫 번째 일지');
    expect(find.textContaining('첫 번째'), findsOneWidget);

    await _pump(tester, '두 번째 일지');
    expect(find.textContaining('두 번째'), findsOneWidget);
    expect(find.textContaining('첫 번째'), findsNothing);
  });

  testWidgets('제목은 본문보다 크고 굵다', (tester) async {
    await _pump(tester, '## 제목\n\n본문',
        style: const TextStyle(fontSize: 14));

    final styles = _renderedStyles(tester);
    final heading = styles.first;
    final body = styles.last;

    expect(heading?.fontWeight, FontWeight.bold);
    expect(heading!.fontSize!, greaterThan(body!.fontSize!));
  });

  testWidgets('빈 원문이면 아무것도 그리지 않는다', (tester) async {
    await _pump(tester, '   \n  ');

    expect(find.byType(Text), findsNothing);
  });
}
