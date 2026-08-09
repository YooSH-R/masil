import 'package:google_sign_in/google_sign_in.dart';

import '../config/oauth_config.dart';
import '../network/api_exception.dart';

/// google_sign_in 7.x 래퍼. 서버로 보낼 idToken만 뽑아서 돌려준다.
class GoogleSignInService {
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    if (!OAuthConfig.isGoogleConfigured) {
      throw ApiException(
        code: ApiErrorCode.unknown,
        message: '구글 로그인 설정(GOOGLE_SERVER_CLIENT_ID)이 없어요.',
      );
    }

    await GoogleSignIn.instance.initialize(
      serverClientId: OAuthConfig.googleServerClientId,
    );
    _initialized = true;
  }

  /// 구글 계정 선택 → idToken 반환. 사용자가 취소하면 null.
  Future<String?> getIdToken() async {
    await _ensureInitialized();

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null) {
        throw ApiException(
          code: ApiErrorCode.unknown,
          message: '구글 인증 토큰을 받지 못했어요. 클라이언트 ID 설정을 확인해 주세요.',
        );
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      // 사용자가 창을 닫은 경우는 오류로 취급하지 않는다.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      // description에 설정 문제의 원인이 담겨 오므로 함께 보여준다.
      // (예: SHA-1 미등록 → clientConfigurationError)
      final detail = e.description == null ? '' : ' ${e.description}';
      throw ApiException(
        code: ApiErrorCode.unknown,
        message: '구글 로그인에 실패했어요. (${e.code.name})$detail',
      );
    }
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    await GoogleSignIn.instance.signOut();
  }
}
