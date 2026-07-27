package com.ssafy.backend.user.domain;

import java.time.Instant;

public record User(
        Long id,
        String email,
        String nickname,
        String phoneNumber,
        Instant createdAt
) {

    public static User newSocialUser(String email, String nickname) {
        return new User(null, email, nickname, null, null);
    }
}
