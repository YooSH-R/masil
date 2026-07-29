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
