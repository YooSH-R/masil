package com.ssafy.backend.common.error;

import org.springframework.http.HttpStatus;

public enum ErrorCode {
    INVALID_REQUEST(HttpStatus.BAD_REQUEST, "요청값이 올바르지 않습니다."),
    INVALID_OAUTH_TOKEN(HttpStatus.UNAUTHORIZED, "소셜 인증 정보가 올바르지 않습니다."),
    OAUTH_TOKEN_EXPIRED(HttpStatus.UNAUTHORIZED, "소셜 인증 정보가 만료되었습니다."),
    INVALID_SIGNUP_TOKEN(HttpStatus.UNAUTHORIZED, "회원가입 토큰이 올바르지 않습니다."),
    SIGNUP_TOKEN_EXPIRED(HttpStatus.UNAUTHORIZED, "회원가입 토큰이 만료되었습니다."),
    NICKNAME_DUPLICATED(HttpStatus.CONFLICT, "이미 사용 중인 닉네임입니다."),
    SOCIAL_ACCOUNT_ALREADY_LINKED(HttpStatus.CONFLICT, "이미 연결된 소셜 계정입니다."),
    PET_NOT_FOUND(HttpStatus.NOT_FOUND, "반려봇 정보를 찾을 수 없습니다."),
    PET_AFFINITY_STATE_NOT_FOUND(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "반려봇 친밀도 정보를 불러올 수 없습니다."
    ),
    INVALID_QR_TOKEN(HttpStatus.BAD_REQUEST, "QR 등록 토큰이 올바르지 않습니다."),
    QR_TOKEN_EXPIRED(HttpStatus.GONE, "QR 등록 토큰이 만료되었습니다."),
    ROBOT_ALREADY_PAIRED(HttpStatus.CONFLICT, "이미 등록된 로봇입니다."),
    PET_ALREADY_PAIRED(HttpStatus.CONFLICT, "반려봇에 이미 등록된 로봇이 있습니다."),
    ROBOT_OWNERSHIP_MISMATCH(HttpStatus.FORBIDDEN, "다른 사용자가 소유한 로봇입니다."),
    WALK_DIARY_NOT_FOUND(HttpStatus.NOT_FOUND, "산책일지를 찾을 수 없습니다."),
    WALK_DIARY_STORAGE_UNAVAILABLE(
            HttpStatus.BAD_GATEWAY,
            "산책일지 저장소에 일시적으로 연결할 수 없습니다."
    ),
    WALK_DIARY_CONTENT_INVALID(
            HttpStatus.BAD_GATEWAY,
            "산책일지 파일이 올바르지 않습니다."
    ),
    RATE_LIMIT_EXCEEDED(HttpStatus.TOO_MANY_REQUESTS, "요청이 너무 많습니다. 잠시 후 다시 시도해 주세요."),
    OAUTH_PROVIDER_UNAVAILABLE(HttpStatus.BAD_GATEWAY, "소셜 인증 서버와 통신할 수 없습니다.");

    private final HttpStatus status;
    private final String message;

    ErrorCode(HttpStatus status, String message) {
        this.status = status;
        this.message = message;
    }

    public HttpStatus status() {
        return status;
    }

    public String message() {
        return message;
    }
}
