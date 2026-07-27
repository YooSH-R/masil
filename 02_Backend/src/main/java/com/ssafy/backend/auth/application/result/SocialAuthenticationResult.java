package com.ssafy.backend.auth.application.result;

import com.ssafy.backend.auth.domain.SocialProvider;
import com.ssafy.backend.user.domain.User;

import java.time.Instant;

public sealed interface SocialAuthenticationResult {

    record Authenticated(IssuedTokens tokens, User user) implements SocialAuthenticationResult {
    }

    record SignupRequired(
            String signupToken,
            Instant signupTokenExpiresAt,
            SocialProvider provider,
            String email,
            String suggestedNickname
    ) implements SocialAuthenticationResult {
    }
}
