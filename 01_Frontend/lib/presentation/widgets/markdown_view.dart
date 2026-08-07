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
///
/// **왜 StatefulWidget 인가**: 문자열 분할과 정규식 매칭을 build 마다 다시
/// 하지 않기 위해서다. 이 위젯은 스크롤되는 목록 안에 놓이고, 일지 생성을
/// 기다리는 동안 뷰모델이 주기적으로 알림을 보내 재빌드된다. 파싱 결과는
/// 원문이 바뀔 때만 다시 만든다([didUpdateWidget]).
class MarkdownView extends StatefulWidget {
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

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  /// 스타일이 섞이지 않은 파싱 결과.
  ///
  /// **스타일을 여기 담지 않는 것이 중요하다.** 스타일까지 캐시하면
  /// `baseStyle` 이 바뀌었을 때 낡은 서식이 그대로 남는다. 무거운 쪽(문자열
  /// 분할·정규식)만 캐시하고, 스타일 적용은 build 에서 매번 한다 — 그건
  /// 값 복사 수준이라 부담이 없다.
  late List<_Block> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = _parse(widget.markdown);
  }

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) {
      _blocks = _parse(widget.markdown);
    }
  }

  static final RegExp _heading = RegExp(r'^(#{1,6})\s*(.*)$');
  static final RegExp _bullet = RegExp(r'^[-*]\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) return const SizedBox.shrink();

    final base = widget.baseStyle ??
        const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF5D4037));

    // 줄 수를 제한한 자리에서는 블록을 쌓을 수 없다. 단락 사이 여백 때문에
    // maxLines 가 뜻대로 동작하지 않기 때문이다. 한 덩어리로 합쳐 그린다.
    if (widget.maxLines != null) {
      final spans = <InlineSpan>[];
      for (var i = 0; i < _blocks.length; i++) {
        if (i > 0) spans.add(const TextSpan(text: '\n'));
        spans.addAll(_spansOf(_blocks[i], base));
      }
      return Text.rich(
        TextSpan(children: spans),
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _blocks.length; i++) ...[
          if (i > 0) SizedBox(height: _spacingBefore(_blocks[i])),
          Text.rich(TextSpan(children: _spansOf(_blocks[i], base))),
        ],
      ],
    );
  }

  double _spacingBefore(_Block block) => switch (block.kind) {
        _BlockKind.heading => 20,
        _BlockKind.bullet => 6,
        _BlockKind.paragraph => 12,
      };

  List<InlineSpan> _spansOf(_Block block, TextStyle base) {
    final style = block.kind == _BlockKind.heading
        ? _headingStyle(block.headingLevel, base)
        : base;

    return [
      if (block.kind == _BlockKind.bullet)
        TextSpan(text: '• ', style: base),
      for (final segment in block.segments)
        TextSpan(
          text: segment.text,
          style: segment.bold
              ? style.copyWith(fontWeight: FontWeight.bold)
              : style,
        ),
    ];
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

  static List<_Block> _parse(String source) {
    final blocks = <_Block>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_Block(
        kind: _BlockKind.paragraph,
        segments: _segmentsOf(paragraph.join(' ')),
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
        final text = heading.group(2)!.trim();
        if (text.isEmpty) continue;
        blocks.add(_Block(
          kind: _BlockKind.heading,
          headingLevel: heading.group(1)!.length,
          segments: _segmentsOf(text),
        ));
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        blocks.add(_Block(
          kind: _BlockKind.bullet,
          segments: _segmentsOf(bullet.group(1)!),
        ));
        continue;
      }

      // 단락은 여러 줄이 이어질 수 있다. 빈 줄이 나올 때까지 모은다.
      paragraph.add(line);
    }
    flushParagraph();
    return blocks;
  }

  /// `**굵게**` 만 처리한다. 짝이 맞지 않으면 나머지가 굵어질 뿐 글자는
  /// 잃지 않는다.
  static List<_Segment> _segmentsOf(String text) {
    final parts = text.split('**');
    final segments = <_Segment>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      segments.add(_Segment(parts[i], bold: i.isOdd));
    }
    return segments.isEmpty ? [_Segment(text)] : segments;
  }
}

enum _BlockKind { heading, bullet, paragraph }

/// 스타일이 없는 한 조각. 굵게인지만 들고 있고 실제 [TextStyle] 은 build 에서
/// 붙인다.
class _Segment {
  const _Segment(this.text, {this.bold = false});

  final String text;
  final bool bold;
}

class _Block {
  const _Block({
    required this.kind,
    required this.segments,
    this.headingLevel = 0,
  });

  final _BlockKind kind;
  final List<_Segment> segments;
  final int headingLevel;
}
