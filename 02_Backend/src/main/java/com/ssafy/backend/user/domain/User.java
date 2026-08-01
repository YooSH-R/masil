package com.ssafy.backend.user.domain;

import java.time.Instant;

public record User(
        Long id,
        String email,
        String passwordHash,
        String nickname,
        String phoneNumber,
        Instant phoneVerifiedAt,
        Instant createdAt
) {

    public User(
            Long id,
            String email,
            String nickname,
            String phoneNumber,
            Instant createdAt
    ) {
        this(id, email, null, nickname, phoneNumber, null, createdAt);
    }

    public static User newSocialUser(String email, String nickname) {
        return new User(null, email, null, nickname, null, null, null);
    }

    public static User newLocalUser(
            String email,
            String passwordHash,
            String nickname,
            String phoneNumber
    ) {
        return new User(
                null,
                email.toLowerCase(),
                passwordHash,
                nickname,
                phoneNumber,
                Instant.now(),
                null
        );
    }
}
