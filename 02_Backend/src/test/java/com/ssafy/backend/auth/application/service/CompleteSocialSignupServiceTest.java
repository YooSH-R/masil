package com.ssafy.backend.auth.application.service;

import com.ssafy.backend.auth.application.port.out.AuthTokenIssuer;
import com.ssafy.backend.auth.application.port.out.OpaqueTokenCodec;
import com.ssafy.backend.auth.application.port.out.SignupTicketRepository;
import com.ssafy.backend.auth.application.port.out.SocialAccountRepository;
import com.ssafy.backend.auth.application.result.IssuedTokens;
import com.ssafy.backend.auth.application.result.SocialAuthenticationResult;
import com.ssafy.backend.auth.domain.SignupTicket;
import com.ssafy.backend.auth.domain.SocialPrincipal;
import com.ssafy.backend.auth.domain.SocialProvider;
import com.ssafy.backend.user.application.port.out.UserRepository;
import com.ssafy.backend.user.domain.User;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CompleteSocialSignupServiceTest {

    private static final Instant NOW = Instant.parse("2026-07-23T03:00:00Z");
    private static final String DEVICE_ID = "device-id";

    private SignupTicketRepository signupTicketRepository;
    private SocialAccountRepository socialAccountRepository;
    private UserRepository userRepository;
    private AuthTokenIssuer authTokenIssuer;
    private OpaqueTokenCodec tokenCodec;
    private CompleteSocialSignupService service;

    @BeforeEach
    void setUp() {
        signupTicketRepository = mock(SignupTicketRepository.class);
        socialAccountRepository = mock(SocialAccountRepository.class);
        userRepository = mock(UserRepository.class);
        authTokenIssuer = mock(AuthTokenIssuer.class);
        tokenCodec = mock(OpaqueTokenCodec.class);
        service = new CompleteSocialSignupService(
                signupTicketRepository,
                socialAccountRepository,
                userRepository,
                authTokenIssuer,
                tokenCodec,
                Clock.fixed(NOW, ZoneOffset.UTC)
        );
    }

    @Test
    void createsUserAndLinksGoogleAccountWithUsableTicket() {
        SignupTicket ticket = usableTicket();
        User savedUser = new User(
                1L,
                "user@example.com",
                "산책좋아",
                null,
                NOW
        );
        IssuedTokens tokens = new IssuedTokens(
                "access",
                "refresh",
                NOW.plusSeconds(3600),
                NOW.plusSeconds(86400)
        );
        when(tokenCodec.hash("signup-token")).thenReturn("token-hash");
        when(signupTicketRepository.findByTokenHash("token-hash"))
                .thenReturn(Optional.of(ticket));
        when(userRepository.save(any(User.class))).thenReturn(savedUser);
        when(authTokenIssuer.issue(savedUser, DEVICE_ID)).thenReturn(tokens);

        SocialAuthenticationResult.Authenticated result =
                service.complete("signup-token", "산책좋아", DEVICE_ID);

        assertEquals(savedUser, result.user());
        assertEquals(tokens, result.tokens());
        verify(socialAccountRepository).save(savedUser.id(), ticket.principal());
        verify(signupTicketRepository).markUsed(ticket.id(), NOW);
    }

    @Test
    void allowsANameAlreadyUsedByAnotherUser() {
        User savedUser = new User(
                2L,
                "another@example.com",
                "산책좋아",
                null,
                NOW
        );
        IssuedTokens tokens = new IssuedTokens(
                "access-2",
                "refresh-2",
                NOW.plusSeconds(3600),
                NOW.plusSeconds(86400)
        );
        when(tokenCodec.hash("signup-token")).thenReturn("token-hash");
        when(signupTicketRepository.findByTokenHash("token-hash"))
                .thenReturn(Optional.of(usableTicket()));
        when(userRepository.save(any(User.class))).thenReturn(savedUser);
        when(authTokenIssuer.issue(savedUser, DEVICE_ID)).thenReturn(tokens);

        SocialAuthenticationResult.Authenticated result =
                service.complete("signup-token", "산책좋아", DEVICE_ID);

        assertEquals("산책좋아", result.user().nickname());
        verify(userRepository).save(any(User.class));
    }

    private SignupTicket usableTicket() {
        return new SignupTicket(
                10L,
                new SocialPrincipal(
                        SocialProvider.GOOGLE,
                        "google-user-id",
                        "user@example.com",
                        "Google User"
                ),
                DEVICE_ID,
                NOW.plusSeconds(600),
                null
        );
    }
}
