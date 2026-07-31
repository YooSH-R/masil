package com.ssafy.backend.auth.infrastructure.kakao;

import com.ssafy.backend.auth.domain.SocialPrincipal;
import com.ssafy.backend.auth.domain.SocialProvider;
import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class KakaoJwtIdTokenVerifierTest {

    @Test
    void mapsVerifiedIdTokenClaimsToKakaoPrincipal() {
        JwtDecoder decoder = mock(JwtDecoder.class);
        KakaoJwtIdTokenVerifier verifier = new KakaoJwtIdTokenVerifier(decoder);
        Jwt jwt = Jwt.withTokenValue("id-token")
                .header("alg", "RS256")
                .subject("kakao-user-id")
                .claim("email", "user@example.com")
                .claim("nickname", "Kakao User")
                .issuedAt(Instant.parse("2026-07-28T03:00:00Z"))
                .expiresAt(Instant.parse("2026-07-28T04:00:00Z"))
                .build();
        when(decoder.decode("id-token")).thenReturn(jwt);

        SocialPrincipal principal = verifier.verify("id-token");

        assertEquals(SocialProvider.KAKAO, principal.provider());
        assertEquals("kakao-user-id", principal.providerUserId());
        assertEquals("user@example.com", principal.email());
        assertEquals("Kakao User", principal.suggestedNickname());
    }

    @Test
    void rejectsMalformedIdToken() {
        JwtDecoder decoder = mock(JwtDecoder.class);
        KakaoJwtIdTokenVerifier verifier = new KakaoJwtIdTokenVerifier(decoder);
        when(decoder.decode("invalid-token")).thenThrow(new JwtException("invalid"));

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> verifier.verify("invalid-token")
        );

        assertEquals(ErrorCode.INVALID_OAUTH_TOKEN, exception.errorCode());
    }
}
