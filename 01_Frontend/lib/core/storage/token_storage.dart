import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 토큰과 deviceId 보관소.
/// 명세서의 로그인·재발급·로그아웃 요청이 모두 deviceId를 요구하므로 함께 관리한다.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kAccessExpiresAt = 'access_token_expires_at';
  static const _kDeviceId = 'device_id';
  static const _kDeviceAccessToken = 'device_access_token';

  String? _cachedDeviceId;

  Future<String?> readAccessToken() => _storage.read(key: _kAccessToken);
  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  /// 로봇 페어링 시 발급되는 Jetson 전용 토큰.
  Future<String?> readDeviceAccessToken() =>
      _storage.read(key: _kDeviceAccessToken);

  Future<DateTime?> readAccessTokenExpiresAt() async {
    final raw = await _storage.read(key: _kAccessExpiresAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    String? accessTokenExpiresAt,
  }) async {
    await _storage.write(key: _kAccessToken, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _kRefreshToken, value: refreshToken);
    }
    if (accessTokenExpiresAt != null) {
      await _storage.write(key: _kAccessExpiresAt, value: accessTokenExpiresAt);
    }
  }

  Future<void> saveDeviceAccessToken(String token) =>
      _storage.write(key: _kDeviceAccessToken, value: token);

  Future<void> clearTokens() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kAccessExpiresAt);
    // deviceId는 기기 식별값이므로 로그아웃 후에도 유지한다.
  }

  Future<bool> get hasSession async =>
      (await readAccessToken()) != null || (await readRefreshToken()) != null;

  /// 기기마다 한 번 만들어 계속 재사용하는 식별자.
  Future<String> deviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final stored = await _storage.read(key: _kDeviceId);
    if (stored != null && stored.isNotEmpty) {
      _cachedDeviceId = stored;
      return stored;
    }

    final generated = _generateDeviceId();
    await _storage.write(key: _kDeviceId, value: generated);
    _cachedDeviceId = generated;
    return generated;
  }

  String _generateDeviceId() {
    final random = Random.secure();
    final suffix = List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
    return 'mobile-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }
}
