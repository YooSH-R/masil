import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/session_cache.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/json_parse.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/auth_model.dart';
import '../models/social_auth_model.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required ApiClient client,
    required TokenStorage tokenStorage,
    required SessionCache sessionCache,
  })  : _client = client,
        _tokenStorage = tokenStorage,
        _cache = sessionCache;

  final ApiClient _client;
  final TokenStorage _tokenStorage;
  final SessionCache _cache;

  @override
  Future<VerificationRequestResult> requestVerification({
    required String phoneNumber,
  }) async {
    final data = await _client.post(
      ApiEndpoints.verifications,
      // 서버는 하이픈 없는 번호만 받는다(pattern: ^01[016789][0-9]{7,8}$).
      data: {'phoneNumber': phoneNumber.replaceAll(RegExp(r'[^0-9]'), '')},
    );
    return VerificationRequestResult.fromJson(Json.asMap(data));
  }

  @override
  Future<NicknameAvailability> checkNicknameAvailability(String nickname) async {
    final data = await _client.get(
      ApiEndpoints.nicknameAvailability,
      query: {'nickname': nickname},
    );
    return NicknameAvailability.fromJson(Json.asMap(data));
  }

  @override
  Future<VerificationConfirmResult> confirmVerification({
    required String verificationId,
    required String code,
  }) async {
    final data = await _client.post(
      ApiEndpoints.verificationConfirm(verificationId),
      data: {'code': code},
    );
    return VerificationConfirmResult.fromJson(Json.asMap(data));
  }

  @override
  Future<User> signup({
    required String email,
    required String password,
    required String nickname,
    String? phoneNumber,
    String? verificationToken,
  }) async {
    final deviceId = await _tokenStorage.deviceId();
    final data = await _client.post(
      ApiEndpoints.signup,
      data: {
        'email': email,
        'password': password,
        'nickname': nickname,
        'deviceId': deviceId,
        if (phoneNumber != null)
          'phoneNumber': phoneNumber.replaceAll(RegExp(r'[^0-9]'), ''),
        if (verificationToken != null) 'verificationToken': verificationToken,
      },
      idempotencyKey: 'signup-$email',
    );

    // 회원가입 응답은 로그인과 같은 AuthResponse라서 토큰까지 함께 온다.
    final session = AuthSession.fromJson(Json.asMap(data));
    if (session.accessToken.isNotEmpty) {
      await _tokenStorage.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAt: session.accessTokenExpiresAt,
      );
    }

    final member = session.user;
    final user = UserModel(
      id: member?.id ?? 0,
      nickname: member?.nickname ?? nickname,
      email: member?.email ?? email,
    );
    await _cache.saveUser(user.toJson());
    return user;
  }

  @override
  Future<SocialAuthResult> signInWithGoogle({required String idToken}) =>
      _socialSignIn(ApiEndpoints.googleOAuth, idToken);

  @override
  Future<SocialAuthResult> signInWithKakao({required String idToken}) =>
      _socialSignIn(ApiEndpoints.kakaoOAuth, idToken);

  /// 구글·카카오 공통. 두 엔드포인트 모두 {idToken, deviceId}를 받고
  /// SocialAuthenticationResponse를 돌려준다.
  Future<SocialAuthResult> _socialSignIn(String path, String idToken) async {
    final deviceId = await _tokenStorage.deviceId();
    final data = await _client.post(
      path,
      data: {'idToken': idToken, 'deviceId': deviceId},
    );

    final result = SocialAuthResult.fromJson(Json.asMap(data));

    // 기존 회원이면 이 단계에서 바로 로그인이 끝난다.
    if (result.isAuthenticated) {
      await _tokenStorage.saveTokens(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken,
        accessTokenExpiresAt: result.accessTokenExpiresAt,
      );
      final user = result.user;
      if (user != null) {
        await _cache.saveUser(UserModel(
          id: user.id,
          nickname: user.nickname,
          email: user.email ?? result.profile?.email,
        ).toJson());
      }
    }
    return result;
  }

  @override
  Future<User> completeSocialSignup({
    required String signupToken,
    required String nickname,
  }) async {
    final deviceId = await _tokenStorage.deviceId();
    final data = await _client.post(
      ApiEndpoints.oauthSignup,
      data: {
        'signupToken': signupToken,
        'nickname': nickname,
        'deviceId': deviceId,
      },
      idempotencyKey: 'oauth-signup-$nickname',
    );

    final session = AuthSession.fromJson(Json.asMap(data));
    if (session.accessToken.isNotEmpty) {
      await _tokenStorage.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAt: session.accessTokenExpiresAt,
      );
    }

    final member = session.user;
    final user = UserModel(
      id: member?.id ?? 0,
      nickname: member?.nickname ?? nickname,
      email: member?.email,
    );
    await _cache.saveUser(user.toJson());
    return user;
  }

  @override
  Future<User> login({
    required String email,
    required String password,
  }) async {
    final deviceId = await _tokenStorage.deviceId();
    final data = await _client.post(
      ApiEndpoints.login,
      data: {'email': email, 'password': password, 'deviceId': deviceId},
    );

    final session = AuthSession.fromJson(Json.asMap(data));
    await _tokenStorage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      accessTokenExpiresAt: session.accessTokenExpiresAt,
    );

    final user = session.user;
    if (user == null) {
      // 명세서 3.4는 user를 함께 주지만, 없더라도 세션은 살아있으므로
      // 캐시에 남아있는 정보로 대체한다.
      final cached = await currentUser();
      if (cached != null) return cached;
      throw ApiException(
        code: ApiErrorCode.unknown,
        message: '로그인 응답에 사용자 정보가 없습니다.',
      );
    }

    // 로그인 응답의 user에는 email이 없어 입력값으로 보완한다.
    final merged = UserModel(
      id: user.id,
      nickname: user.nickname,
      email: user.email ?? email,
      profileImageUrl: user.profileImageUrl,
    );
    await _cache.saveUser(merged.toJson());
    return merged;
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    final deviceId = await _tokenStorage.deviceId();
    try {
      if (refreshToken != null) {
        await _client.post(
          ApiEndpoints.logout,
          data: {'refreshToken': refreshToken, 'deviceId': deviceId},
        );
      }
    } on ApiException {
      // 서버 로그아웃이 실패해도 기기에서는 세션을 끊는다.
    } finally {
      await _tokenStorage.clearTokens();
      await _cache.clear();
    }
  }

  @override
  Future<User?> restoreSession() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) return null;

    try {
      final deviceId = await _tokenStorage.deviceId();
      final data = await _client.post(
        ApiEndpoints.refresh,
        data: {'refreshToken': refreshToken, 'deviceId': deviceId},
      );
      final session = AuthSession.fromJson(Json.asMap(data));
      await _tokenStorage.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAt: session.accessTokenExpiresAt,
      );
      // 재발급 응답에는 user가 없어(명세서 3.5) 캐시된 사용자를 쓴다.
      return session.user ?? await currentUser();
    } on ApiException {
      await _tokenStorage.clearTokens();
      return null;
    }
  }

  @override
  Future<User?> currentUser() async {
    final json = await _cache.readUser();
    if (json == null) return null;
    return UserModel.fromJson(json);
  }
}
