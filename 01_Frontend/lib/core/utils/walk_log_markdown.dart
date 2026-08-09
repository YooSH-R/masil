/// `walk_log.md` 텍스트를 다루는 도우미.
///
/// 서버는 일지를 마크다운 원문으로 준다. 그대로 화면에 뿌리면 `##` 이나 `**`
/// 같은 기호가 사용자에게 그대로 보인다. 목록 미리보기에는 [summaryLine] 으로
/// 기호를 걷어낸 한 줄을 쓰고, 본문에는 `MarkdownView` 로 서식을 살려 그린다.
class WalkLogMarkdown {
  WalkLogMarkdown._();

  /// AI 일지가 첫 단락에 넣는 요약 표시. 이 줄이 있으면 미리보기로 가장 좋다.
  static const String _summaryLabel = '한 줄 요약';

  static final RegExp _heading = RegExp(r'^(#{1,6})\s*');
  static final RegExp _bullet = RegExp(r'^[-*]\s+');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// 목록에 보여줄 한 줄.
  ///
  /// `**한 줄 요약**: ...` 이 있으면 콜론 뒤를 쓰고, 없으면 제목이 아닌 첫
  /// 문장을 쓴다. 제목(`## 2026-08-07 산책 일지`)은 날짜만 반복해서 미리보기로
  /// 쓸모가 없다.
  static String? summaryLine(String? markdown) {
    if (markdown == null || markdown.trim().isEmpty) return null;

    String? firstBody;
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final stripped = stripMarkers(line);
      if (stripped.isEmpty) continue;

      if (stripped.contains(_summaryLabel)) {
        final colon = stripped.indexOf(':');
        final tail =
            colon == -1 ? stripped : stripped.substring(colon + 1).trim();
        if (tail.isNotEmpty) return tail;
      }

      if (_heading.hasMatch(line)) continue;
      firstBody ??= stripped;
    }
    return firstBody;
  }

  /// 마크다운 전체를 한 덩어리 평문으로. 검색이나 한 줄 표시에 쓴다.
  static String toPlainText(String? markdown) {
    if (markdown == null) return '';
    final lines = <String>[];
    for (final raw in markdown.split('\n')) {
      final stripped = stripMarkers(raw.trim());
      if (stripped.isNotEmpty) lines.add(stripped);
    }
    return lines.join(' ').replaceAll(_whitespace, ' ').trim();
  }

  /// 한 줄에서 마크다운 기호만 걷어낸다. 글자는 남긴다.
  static String stripMarkers(String line) {
    return line
        .replaceFirst(_heading, '')
        .replaceFirst(_bullet, '')
        .replaceAll('**', '')
        .replaceAll('`', '')
        .trim();
  }
}
