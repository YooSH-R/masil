package com.ssafy.backend.auth.application.service;

import com.ssafy.backend.auth.application.port.out.AuthTokenIssuer;
import com.ssafy.backend.auth.application.port.out.OpaqueTokenCodec;
import com.ssafy.backend.auth.application.port.out.SignupTicketRepository;
import com.ssafy.backend.auth.application.port.out.SocialAccountRepository;
import com.ssafy.backend.auth.application.result.IssuedTokens;
import com.ssafy.backend.auth.application.result.SocialAuthenticationResult;
import com.ssafy.backend.auth.domain.SocialPrincipal;
import com.ssafy.backend.user.domain.User;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;

@Service
public class SocialAuthenticationProcessor {

    private final SocialAccountRepository socialAccountRepository;
    private final SignupTicketRepository signupTicketRepository;
    private final AuthTokenIssuer authTokenIssuer;
    private final OpaqueTokenCodec opaqueTokenCodec;
    private final Clock clock;
    private final Duration signupTokenTtl;

    public SocialAuthenticationProcessor(
            SocialAccountRepository socialAccountRepository,
            SignupTicketRepository signupTicketRepository,
            AuthTokenIssuer authTokenIssuer,
            OpaqueTokenCodec opaqueTokenCodec,
            Clock clock,
            @Value("${auth.signup-token-ttl}") Duration signupTokenTtl
    ) {
        this.socialAccountRepository = socialAccountRepository;
        this.signupTicketRepository = signupTicketRepository;
        this.authTokenIssuer = authTokenIssuer;
        this.opaqueTokenCodec = opaqueTokenCodec;
        this.clock = clock;
        this.signupTokenTtl = signupTokenTtl;
    }

    @Transactional
    public SocialAuthenticationResult process(SocialPrincipal principal, String deviceId) {
        return socialAccountRepository.findUser(principal.provider(), principal.providerUserId())
                .<SocialAuthenticationResult>map(user -> authenticated(user, deviceId))
                .orElseGet(() -> signupRequired(principal, deviceId));
    }

    private SocialAuthenticationResult.Authenticated authenticated(User user, String deviceId) {
        IssuedTokens tokens = authTokenIssuer.issue(user, deviceId);
        return new SocialAuthenticationResult.Authenticated(tokens, user);
    }

    private SocialAuthenticationResult.SignupRequired signupRequired(
            SocialPrincipal principal,
            String deviceId
    ) {
        String signupToken = opaqueTokenCodec.generate();
        Instant expiresAt = clock.instant().plus(signupTokenTtl);
        signupTicketRepository.save(
                opaqueTokenCodec.hash(signupToken),
                principal,
                deviceId,
                expiresAt
        );
        return new SocialAuthenticationResult.SignupRequired(
                signupToken,
                expiresAt,
                principal.provider(),
                principal.email(),
                principal.suggestedNickname()
        );
    }
}
