package com.ssafy.backend.auth.application.service;

import com.ssafy.backend.auth.application.port.out.AuthTokenIssuer;
import com.ssafy.backend.auth.application.port.out.KakaoIdTokenVerifier;
import com.ssafy.backend.auth.application.port.out.OpaqueTokenCodec;
import com.ssafy.backend.auth.application.port.out.SignupTicketRepository;
import com.ssafy.backend.auth.application.port.out.SocialAccountRepository;
import com.ssafy.backend.auth.application.result.IssuedTokens;
import com.ssafy.backend.auth.application.result.SocialAuthenticationResult;
import com.ssafy.backend.auth.domain.SocialPrincipal;
import com.ssafy.backend.auth.domain.SocialProvider;
import com.ssafy.backend.user.domain.User;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KakaoAuthenticationServiceTest {

    private static final Instant NOW = Instant.parse("2026-07-28T03:00:00Z");
    private static final String DEVICE_ID = "device-id";

    private KakaoIdTokenVerifier idTokenVerifier;
    private SocialAccountRepository socialAccountRepository;
    private SignupTicketRepository signupTicketRepository;
    private AuthTokenIssuer authTokenIssuer;
    private OpaqueTokenCodec tokenCodec;
    private KakaoAuthenticationService service;

    @BeforeEach
    void setUp() {
        idTokenVerifier = mock(KakaoIdTokenVerifier.class);
        socialAccountRepository = mock(SocialAccountRepository.class);
        signupTicketRepository = mock(SignupTicketRepository.class);
        authTokenIssuer = mock(AuthTokenIssuer.class);
        tokenCodec = mock(OpaqueTokenCodec.class);
        service = new KakaoAuthenticationService(
                idTokenVerifier,
                socialAccountRepository,
                signupTicketRepository,
                authTokenIssuer,
                tokenCodec,
                Clock.fixed(NOW, ZoneOffset.UTC),
                Duration.ofMinutes(10)
        );
    }

    @Test
    void returnsAuthenticatedResultWhenKakaoAccountIsAlreadyLinked() {
        SocialPrincipal principal = kakaoPrincipal();
        User user = new User(1L, "user@example.com", "산책좋아", null, NOW);
        IssuedTokens tokens = new IssuedTokens(
                "access",
                "refresh",
                NOW.plusSeconds(3600),
                NOW.plusSeconds(86400)
        );
        when(idTokenVerifier.verify("id-token")).thenReturn(principal);
        when(socialAccountRepository.findUser(
                SocialProvider.KAKAO,
                "kakao-user-id"
        )).thenReturn(Optional.of(user));
        when(authTokenIssuer.issue(user, DEVICE_ID)).thenReturn(tokens);

        SocialAuthenticationResult result = service.authenticate("id-token", DEVICE_ID);

        SocialAuthenticationResult.Authenticated authenticated =
                assertInstanceOf(SocialAuthenticationResult.Authenticated.class, result);
        assertEquals(user, authenticated.user());
        assertEquals(tokens, authenticated.tokens());
    }

    @Test
    void issuesSignupTicketWhenKakaoAccountIsNew() {
        SocialPrincipal principal = kakaoPrincipal();
        when(idTokenVerifier.verify("id-token")).thenReturn(principal);
        when(socialAccountRepository.findUser(
                SocialProvider.KAKAO,
                "kakao-user-id"
        )).thenReturn(Optional.empty());
        when(tokenCodec.generate()).thenReturn("signup-token");
        when(tokenCodec.hash("signup-token")).thenReturn("signup-token-hash");

        SocialAuthenticationResult result = service.authenticate("id-token", DEVICE_ID);

        SocialAuthenticationResult.SignupRequired signupRequired =
                assertInstanceOf(SocialAuthenticationResult.SignupRequired.class, result);
        assertEquals("signup-token", signupRequired.signupToken());
        assertEquals(NOW.plusSeconds(600), signupRequired.signupTokenExpiresAt());
        verify(signupTicketRepository).save(
                "signup-token-hash",
                principal,
                DEVICE_ID,
                NOW.plusSeconds(600)
        );
    }

    private SocialPrincipal kakaoPrincipal() {
        return new SocialPrincipal(
                SocialProvider.KAKAO,
                "kakao-user-id",
                "user@example.com",
                "Kakao User"
        );
    }
}
