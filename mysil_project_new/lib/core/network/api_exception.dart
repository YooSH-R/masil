import 'package:dio/dio.dart';

/// 명세서 v1.0 "10. 주요 오류 코드".
/// 서버가 표에 없는 코드를 보낼 수도 있으므로 문자열 비교로만 쓴다.
class ApiErrorCode {
  ApiErrorCode._();

  static const String invalidRequest = 'INVALID_REQUEST';
  static const String tokenExpired = 'TOKEN_EXPIRED';
  static const String deviceTokenExpired = 'DEVICE_TOKEN_EXPIRED';
  static const String resourceForbidden = 'RESOURCE_FORBIDDEN';
  static const String petNotFound = 'PET_NOT_FOUND';
  static const String walkNotFound = 'WALK_NOT_FOUND';
  static const String emailDuplicated = 'EMAIL_DUPLICATED';
  static const String robotAlreadyPaired = 'ROBOT_ALREADY_PAIRED';
  static const String walkAlreadyActive = 'WALK_ALREADY_ACTIVE';
  static const String photoTooLarge = 'PHOTO_TOO_LARGE';
  static const String unsupportedPhotoType = 'UNSUPPORTED_PHOTO_TYPE';
  static const String invalidWalkState = 'INVALID_WALK_STATE';
  static const String rateLimitExceeded = 'RATE_LIMIT_EXCEEDED';
  static const String gptProcessingFailed = 'GPT_PROCESSING_FAILED';
  static const String gptProcessingTimeout = 'GPT_PROCESSING_TIMEOUT';

  /// 서버 구현에서 확인된, 명세서 표에는 없는 코드.
  static const String invalidCredentials = 'INVALID_CREDENTIALS';

  /// 통신 자체가 실패했을 때 앱이 붙이는 코드.
  static const String networkError = 'NETWORK_ERROR';
  static const String unknown = 'UNKNOWN';
}

/// 공통 오류 응답을 그대로 담는 예외.
/// {"success": false, "error": {code, message, details}, "traceId", "timestamp"}
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
    this.traceId,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;
  final String? traceId;

  /// 오류 응답 본문에서 생성.
  factory ApiException.fromBody(Map<String, dynamic> body, {int? statusCode}) {
    final error = body['error'];
    if (error is Map) {
      return ApiException(
        code: error['code']?.toString() ?? ApiErrorCode.unknown,
        message: error['message']?.toString() ?? '알 수 없는 오류가 발생했습니다.',
        statusCode: statusCode,
        details: error['details'] is Map
            ? Map<String, dynamic>.from(error['details'] as Map)
            : null,
        traceId: body['traceId']?.toString(),
      );
    }
    return ApiException(
      code: ApiErrorCode.unknown,
      message: '알 수 없는 오류가 발생했습니다.',
      statusCode: statusCode,
      traceId: body['traceId']?.toString(),
    );
  }

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data['error'] != null) {
      return ApiException.fromBody(data, statusCode: e.response?.statusCode);
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          code: ApiErrorCode.networkError,
          message: '서버 응답이 지연되고 있어요. 잠시 후 다시 시도해 주세요.',
          statusCode: e.response?.statusCode,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          code: ApiErrorCode.networkError,
          message: '네트워크에 연결할 수 없어요. 연결 상태를 확인해 주세요.',
        );
      case DioExceptionType.cancel:
        return ApiException(
          code: ApiErrorCode.unknown,
          message: '요청이 취소되었습니다.',
        );
      default:
        return ApiException(
          code: ApiErrorCode.unknown,
          message: e.message ?? '알 수 없는 오류가 발생했습니다.',
          statusCode: e.response?.statusCode,
        );
    }
  }

  bool get isTokenExpired =>
      code == ApiErrorCode.tokenExpired || statusCode == 401;
  bool get isForbidden => code == ApiErrorCode.resourceForbidden;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => code == ApiErrorCode.rateLimitExceeded;

  /// 사용자에게 재시도 버튼을 보여줄 만한 오류인지.
  bool get isRetriable =>
      code == ApiErrorCode.networkError ||
      code == ApiErrorCode.gptProcessingFailed ||
      code == ApiErrorCode.gptProcessingTimeout ||
      (statusCode != null && statusCode! >= 500);

  @override
  String toString() =>
      'ApiException($statusCode $code): $message${traceId == null ? '' : ' [trace: $traceId]'}';
}
