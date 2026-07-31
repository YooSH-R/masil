package com.ssafy.backend.auth.infrastructure.token;

import com.ssafy.backend.auth.application.port.out.AuthTokenIssuer;
import com.ssafy.backend.auth.application.result.IssuedTokens;
import com.ssafy.backend.auth.infrastructure.persistence.AuthSessionJpaEntity;
import com.ssafy.backend.auth.infrastructure.persistence.SpringDataAuthSessionRepository;
import com.ssafy.backend.auth.service.TokenHashService;
import com.ssafy.backend.auth.service.TokenService;
import com.ssafy.backend.user.domain.User;
import org.springframework.stereotype.Component;

@Component
public class StandardAuthTokenIssuer implements AuthTokenIssuer {

    private final SpringDataAuthSessionRepository authSessionRepository;
    private final TokenService tokenService;
    private final TokenHashService tokenHashService;

    public StandardAuthTokenIssuer(
            SpringDataAuthSessionRepository authSessionRepository,
            TokenService tokenService,
            TokenHashService tokenHashService
    ) {
        this.authSessionRepository = authSessionRepository;
        this.tokenService = tokenService;
        this.tokenHashService = tokenHashService;
    }

    @Override
    public IssuedTokens issue(User user, String deviceId) {
        authSessionRepository
                .findFirstByUserIdAndDeviceIdAndRevokedAtIsNullOrderByCreatedAtDesc(
                        user.id(),
                        deviceId
                )
                .ifPresent(AuthSessionJpaEntity::revoke);

        TokenService.AccessToken accessToken =
                tokenService.createAccessToken(user.id(), deviceId);
        TokenService.RefreshToken refreshToken =
                tokenService.createRefreshToken();

        authSessionRepository.save(
                new AuthSessionJpaEntity(
                        user.id(),
                        deviceId,
                        tokenHashService.hash(refreshToken.value()),
                        refreshToken.expiresAt()
                )
        );

        return new IssuedTokens(
                accessToken.value(),
                refreshToken.value(),
                accessToken.expiresAt(),
                refreshToken.expiresAt()
        );
    }
}
