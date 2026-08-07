import 'package:flutter/material.dart';

/// 마크다운 원문을 서식을 살려 그린다.
///
/// **왜 직접 만들었나**: `walk_log.md` 가 쓰는 문법은 제목(`#`~`######`),
/// 굵게(`**`), 글머리표(`-`, `*`), 빈 줄로 나뉜 단락뿐이다. 이 정도에 마크다운
/// 패키지를 넣으면 앱 크기와 의존성이 늘고, 서식이 앱 톤과 어긋나 다시
/// 덮어써야 한다. `flutter_markdown` 은 Flutter 팀이 지원을 중단하기도 했다.
///
/// 지원하지 않는 문법(표, 링크, 이미지, 코드 블록)은 **기호를 남기지 않고
/// 글자만** 보여준다. 사용자에게 `##` 이 노출되는 것보다는 낫다.
class MarkdownView extends StatelessWidget {
  const MarkdownView(
    this.markdown, {
    super.key,
    this.baseStyle,
    this.maxLines,
  });

  final String markdown;

  /// 본문 단락 기준 스타일. 제목·글머리표가 여기서 파생된다.
  final TextStyle? baseStyle;

  /// 지정하면 이 줄 수까지만 그리고 넘치는 부분은 `...` 으로 자른다.
  /// 목록 카드처럼 높이가 제한된 자리에 쓴다.
  final int? maxLines;

  static final RegExp _heading = RegExp(r'^(#{1,6})\s*(.*)$');
  static final RegExp _bullet = RegExp(r'^[-*]\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final base = baseStyle ??
        const TextStyle(
            fontSize: 14, height: 1.6, color: Color(0xFF5D4037));
    final blocks = _parse(markdown, base);

    if (blocks.isEmpty) return const SizedBox.shrink();

    // 줄 수를 제한한 자리에서는 블록을 쌓을 수 없다. 단락 사이 여백 때문에
    // maxLines 가 뜻대로 동작하지 않기 때문이다. 한 덩어리로 합쳐 그린다.
    if (maxLines != null) {
      return Text.rich(
        TextSpan(children: _flatten(blocks)),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: blocks[i].spacingBefore),
          blocks[i].build(),
        ],
      ],
    );
  }

  List<InlineSpan> _flatten(List<_Block> blocks) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      spans.addAll(blocks[i].spans);
    }
    return spans;
  }

  List<_Block> _parse(String source, TextStyle base) {
    final blocks = <_Block>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_Block(
        spans: _inline(paragraph.join(' '), base),
        spacingBefore: 12,
      ));
      paragraph.clear();
    }

    for (final raw in source.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        flushParagraph();
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        flushParagraph();
        final level = heading.group(1)!.length;
        final text = heading.group(2)!.trim();
        if (text.isEmpty) continue;
        blocks.add(_Block(
          spans: _inline(text, _headingStyle(level, base)),
          spacingBefore: blocks.isEmpty ? 0 : 20,
        ));
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        blocks.add(_Block(
          spans: [
            TextSpan(text: '• ', style: base),
            ..._inline(bullet.group(1)!, base),
          ],
          spacingBefore: 6,
        ));
        continue;
      }

      // 단락은 여러 줄이 이어질 수 있다. 빈 줄이 나올 때까지 모은다.
      paragraph.add(line);
    }
    flushParagraph();
    return blocks;
  }

  TextStyle _headingStyle(int level, TextStyle base) {
    final size = switch (level) {
      1 => (base.fontSize ?? 14) + 6,
      2 => (base.fontSize ?? 14) + 3,
      3 => (base.fontSize ?? 14) + 1,
      _ => base.fontSize ?? 14,
    };
    return base.copyWith(
      fontSize: size,
      fontWeight: FontWeight.bold,
      height: 1.35,
    );
  }

  /// `**굵게**` 만 처리한다. 짝이 맞지 않으면 나머지가 굵어질 뿐 글자는
  /// 잃지 않는다.
  List<TextSpan> _inline(String text, TextStyle style) {
    final parts = text.split('**');
    final spans = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(
        text: parts[i],
        style: i.isOdd ? style.copyWith(fontWeight: FontWeight.bold) : style,
      ));
    }
    return spans.isEmpty ? [TextSpan(text: text, style: style)] : spans;
  }
}

class _Block {
  const _Block({required this.spans, required this.spacingBefore});

  final List<TextSpan> spans;
  final double spacingBefore;

  Widget build() => Text.rich(TextSpan(children: spans));
}
