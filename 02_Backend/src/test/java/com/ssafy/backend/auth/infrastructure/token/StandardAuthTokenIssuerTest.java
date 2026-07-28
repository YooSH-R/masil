package com.ssafy.backend.auth.infrastructure.token;

import com.ssafy.backend.auth.application.result.IssuedTokens;
import com.ssafy.backend.auth.infrastructure.persistence.AuthSessionJpaEntity;
import com.ssafy.backend.auth.infrastructure.persistence.SpringDataAuthSessionRepository;
import com.ssafy.backend.auth.service.TokenHashService;
import com.ssafy.backend.auth.service.TokenService;
import com.ssafy.backend.user.domain.User;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StandardAuthTokenIssuerTest {

    private static final String JWT_SECRET =
            "test-secret-key-with-at-least-thirty-two-bytes";

    @Test
    void issuesStandardTokensAndRevokesExistingDeviceSession() {
        SpringDataAuthSessionRepository repository =
                mock(SpringDataAuthSessionRepository.class);
        TokenService tokenService = new TokenService(JWT_SECRET, 1800, 2592000);
        TokenHashService tokenHashService = new TokenHashService();
        StandardAuthTokenIssuer issuer = new StandardAuthTokenIssuer(
                repository,
                tokenService,
                tokenHashService
        );
        User user = new User(
                1L,
                "user@example.com",
                "산책좋아",
                null,
                Instant.now()
        );
        AuthSessionJpaEntity existingSession = new AuthSessionJpaEntity(
                user.id(),
                "device-id",
                tokenHashService.hash("old-refresh-token"),
                Instant.now().plusSeconds(3600)
        );
        when(repository
                .findFirstByUserIdAndDeviceIdAndRevokedAtIsNullOrderByCreatedAtDesc(
                        user.id(),
                        "device-id"
                ))
                .thenReturn(Optional.of(existingSession));

        IssuedTokens tokens = issuer.issue(user, "device-id");

        assertEquals(user.id(), tokenService.parseAccessToken(tokens.accessToken()));
        assertFalse(existingSession.isUsableAt(Instant.now()));
        verify(repository).save(any(AuthSessionJpaEntity.class));
    }
}
