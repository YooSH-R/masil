/// 마실이 기기 QR 토큰 규칙.
///
/// 서버 `RobotPairingController.RobotPairingRequest` 의 검증 애너테이션과
/// 같은 규칙을 둔다. 서버가 규칙을 바꾸면 여기도 함께 고쳐야 한다.
///
/// ```java
/// @NotBlank
/// @Size(min = 43, max = 512)
/// @Pattern(regexp = "^[A-Za-z0-9_-]+$")
/// String qrToken
/// ```
///
/// 앱에서 미리 걸러내면 형식이 틀린 QR(다른 앱의 QR, 광고 QR 등)을 스캔했을 때
/// 굳이 서버까지 요청을 보내지 않고 바로 안내할 수 있다.
class RobotQr {
  RobotQr._();

  static const int minLength = 43;
  static const int maxLength = 512;

  static final RegExp _allowed = RegExp(r'^[A-Za-z0-9_-]+$');

  /// 스캔한 문자열이 기기 등록용 토큰 형식인지.
  static bool isValidToken(String? raw) {
    if (raw == null) return false;
    final token = raw.trim();
    if (token.length < minLength || token.length > maxLength) return false;
    return _allowed.hasMatch(token);
  }

  /// QR 값에서 토큰만 뽑아낸다.
  ///
  /// 기기 QR 이 토큰만 담고 있을 수도 있고, `mysil://pair?token=...` 처럼
  /// URL 형태일 수도 있어 두 경우를 모두 받아준다.
  static String? extractToken(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    if (isValidToken(text)) return text;

    // URL 형태면 token / qrToken 쿼리 파라미터를 찾아본다.
    final uri = Uri.tryParse(text);
    if (uri != null) {
      for (final key in ['token', 'qrToken', 'qr_token']) {
        final value = uri.queryParameters[key];
        if (isValidToken(value)) return value!.trim();
      }
    }
    return null;
  }
}
