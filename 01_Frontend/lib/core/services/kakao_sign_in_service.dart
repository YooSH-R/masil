import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../config/oauth_config.dart';
import '../network/api_exception.dart';

/// kakao_flutter_sdk_user 래퍼. 서버로 보낼 idToken만 뽑아서 돌려준다.
///
/// 서버는 POST /auth/oauth/kakao 에서 accessToken이 아니라 **idToken**을 받는다.
/// (OpenAPI: KakaoAuthenticationRequest.required = [deviceId, idToken])
/// 카카오는 개발자 콘솔에서 [카카오 로그인] > [고급] > **OpenID Connect 활성화**를
/// 켜 둔 앱에만 idToken을 내려준다. 꺼져 있으면 idToken이 null로 온다.
class KakaoSignInService {
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    if (!OAuthConfig.isKakaoConfigured) {
      throw ApiException(
        code: ApiErrorCode.unknown,
        message: '카카오 로그인 설정(KAKAO_NATIVE_APP_KEY)이 없어요.',
      );
    }

    await KakaoSdk.init(nativeAppKey: OAuthConfig.kakaoNativeAppKey);
    _initialized = true;
  }

  /// 카카오 로그인 → idToken 반환. 사용자가 취소하면 null.
  ///
  /// 카카오톡이 깔려 있으면 앱으로, 없으면 카카오계정(웹)으로 로그인한다.
  Future<String?> getIdToken() async {
    await _ensureInitialized();

    try {
      final token = await (await isKakaoTalkInstalled()
          ? _loginWithTalkOrFallback()
          : UserApi.instance.loginWithKakaoAccount());
      if (token == null) return null;

      final idToken = token.idToken;
      if (idToken == null) {
        throw ApiException(
          code: ApiErrorCode.unknown,
          message: '카카오 ID 토큰을 받지 못했어요. '
              '개발자 콘솔에서 OpenID Connect를 활성화해 주세요.',
        );
      }
      return idToken;
    } on KakaoClientException catch (e) {
      // 사용자가 창을 닫은 경우는 오류로 취급하지 않는다.
      if (e.reason == ClientErrorCause.cancelled) return null;
      throw ApiException(
        code: ApiErrorCode.unknown,
        message: '카카오 로그인에 실패했어요. (${e.reason.name})',
      );
    } on KakaoAuthException catch (e) {
      throw ApiException(
        code: ApiErrorCode.unknown,
        message: '카카오 로그인에 실패했어요. (${e.error.name})',
      );
    }
  }

  /// 카카오톡으로 로그인. 카카오톡이 깔려 있어도 실패할 수 있어
  /// (미로그인 상태, 앱 전환 실패 등) 카카오계정 로그인으로 한 번 더 시도한다.
  Future<OAuthToken?> _loginWithTalkOrFallback() async {
    try {
      return await UserApi.instance.loginWithKakaoTalk();
    } on KakaoClientException catch (e) {
      // 취소는 사용자 의사이므로 폴백하지 않는다.
      if (e.reason == ClientErrorCause.cancelled) return null;
      return await UserApi.instance.loginWithKakaoAccount();
    } catch (_) {
      return await UserApi.instance.loginWithKakaoAccount();
    }
  }

  /// 다음 로그인 때 계정을 다시 고를 수 있도록 카카오 세션도 끊는다.
  Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await UserApi.instance.logout();
    } catch (_) {
      // 카카오 세션 정리 실패는 앱 로그아웃을 막지 않는다.
    }
  }
}
