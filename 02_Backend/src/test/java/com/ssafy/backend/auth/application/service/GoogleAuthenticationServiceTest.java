package com.ssafy.backend.auth.application.service;

import com.ssafy.backend.auth.application.port.out.GoogleIdTokenVerifier;
import com.ssafy.backend.auth.application.result.SocialAuthenticationResult;
import com.ssafy.backend.auth.domain.SocialPrincipal;
import com.ssafy.backend.auth.domain.SocialProvider;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class GoogleAuthenticationServiceTest {

    @Test
    void verifiesIdTokenBeforeProcessingAuthentication() {
        GoogleIdTokenVerifier idTokenVerifier = mock(GoogleIdTokenVerifier.class);
        SocialAuthenticationProcessor authenticationProcessor =
                mock(SocialAuthenticationProcessor.class);
        GoogleAuthenticationService service = new GoogleAuthenticationService(
                idTokenVerifier,
                authenticationProcessor
        );
        SocialPrincipal principal = new SocialPrincipal(
                SocialProvider.GOOGLE,
                "google-user-id",
                "user@example.com",
                "Google User"
        );
        SocialAuthenticationResult expected = new SocialAuthenticationResult.SignupRequired(
                "signup-token",
                Instant.parse("2026-07-28T03:10:00Z"),
                SocialProvider.GOOGLE,
                "user@example.com",
                "Google User"
        );
        when(idTokenVerifier.verify("id-token")).thenReturn(principal);
        when(authenticationProcessor.process(principal, "device-id")).thenReturn(expected);

        SocialAuthenticationResult result = service.authenticate("id-token", "device-id");

        assertSame(expected, result);
        InOrder inOrder = inOrder(idTokenVerifier, authenticationProcessor);
        inOrder.verify(idTokenVerifier).verify("id-token");
        inOrder.verify(authenticationProcessor).process(principal, "device-id");
    }
}
