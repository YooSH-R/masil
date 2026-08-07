/// 한국어 조사 선택.
///
/// 펫 이름은 사용자가 직접 정하므로 받침 유무가 매번 다르다. 조사를 하나로
/// 고정하면 "코코이 산책 가고 싶어 해요" 처럼 어색한 문장이 나온다.
class Korean {
  Korean._();

  /// 주격 조사(이/가).
  static String subject(String word) => _hasFinalConsonant(word) ? '이' : '가';

  /// 보조사(은/는).
  static String topic(String word) => _hasFinalConsonant(word) ? '은' : '는';

  /// 목적격 조사(을/를).
  static String object(String word) => _hasFinalConsonant(word) ? '을' : '를';

  static bool _hasFinalConsonant(String word) {
    if (word.isEmpty) return false;
    final code = word.codeUnitAt(word.length - 1);
    // 한글 음절이 아니면 받침을 알 수 없으니 없는 쪽으로 본다.
    if (code < 0xAC00 || code > 0xD7A3) return false;
    // 한글 음절은 (초성, 중성, 종성) 조합이고 종성이 28가지다.
    return (code - 0xAC00) % 28 != 0;
  }
}
