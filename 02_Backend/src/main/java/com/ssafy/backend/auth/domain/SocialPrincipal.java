package com.ssafy.backend.auth.domain;

public record SocialPrincipal(
        SocialProvider provider,
        String providerUserId,
        String email,
        String suggestedNickname
) {
}
