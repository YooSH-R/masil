package com.ssafy.backend.auth.application.result;

import java.time.Instant;

public record IssuedTokens(
        String accessToken,
        String refreshToken,
        Instant accessTokenExpiresAt,
        Instant refreshTokenExpiresAt
) {
}
