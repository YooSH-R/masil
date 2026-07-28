package com.ssafy.backend.auth.dto;

import com.ssafy.backend.user.domain.User;

import java.time.Instant;

public record AuthResponse(
        String accessToken,
        String refreshToken,
        String tokenType,
        Instant accessTokenExpiresAt,
        Instant refreshTokenExpiresAt,
        MemberResponse member
) {
    public static AuthResponse of(
            String accessToken,
            String refreshToken,
            Instant accessTokenExpiresAt,
            Instant refreshTokenExpiresAt,
            User user
    ) {
        return new AuthResponse(
                accessToken,
                refreshToken,
                "Bearer",
                accessTokenExpiresAt,
                refreshTokenExpiresAt,
                new MemberResponse(
                        user.id(),
                        user.email(),
                        user.nickname()
                )
        );
    }

    public record MemberResponse(
            Long memberId,
            String email,
            String nickname
    ) {
    }
}
