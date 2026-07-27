package com.ssafy.backend.auth.domain;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;

import java.time.Instant;

public record SignupTicket(
        Long id,
        SocialPrincipal principal,
        String deviceId,
        Instant expiresAt,
        Instant usedAt
) {

    public void validateUsableAt(Instant now) {
        if (usedAt != null) {
            throw new BusinessException(ErrorCode.INVALID_SIGNUP_TOKEN);
        }
        if (!expiresAt.isAfter(now)) {
            throw new BusinessException(ErrorCode.SIGNUP_TOKEN_EXPIRED);
        }
    }
}
