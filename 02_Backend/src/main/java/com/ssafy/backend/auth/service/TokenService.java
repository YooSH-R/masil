package com.ssafy.backend.auth.service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;

@Component
public class TokenService {

    private final SecretKey secretKey;
    private final long accessValiditySeconds;
    private final long refreshValiditySeconds;
    private final SecureRandom secureRandom = new SecureRandom();

    public TokenService(
            @Value("${auth.jwt.secret}") String secret,
            @Value("${auth.access-token-validity-seconds}") long accessValiditySeconds,
            @Value("${auth.refresh-token-validity-seconds}") long refreshValiditySeconds
    ) {
        this.secretKey = Keys.hmacShaKeyFor(
                secret.getBytes(StandardCharsets.UTF_8)
        );
        this.accessValiditySeconds = accessValiditySeconds;
        this.refreshValiditySeconds = refreshValiditySeconds;
    }

    public AccessToken createAccessToken(Long userId) {
        Instant issuedAt = Instant.now();
        Instant expiresAt = issuedAt.plusSeconds(accessValiditySeconds);

        String value = Jwts.builder()
                .subject(userId.toString())
                .claim("tokenType", "ACCESS")
                .issuedAt(Date.from(issuedAt))
                .expiration(Date.from(expiresAt))
                .signWith(secretKey)
                .compact();

        return new AccessToken(value, expiresAt);
    }

    public RefreshToken createRefreshToken() {
        byte[] bytes = new byte[32];
        secureRandom.nextBytes(bytes);

        return new RefreshToken(
                Base64.getUrlEncoder().withoutPadding().encodeToString(bytes),
                Instant.now().plusSeconds(refreshValiditySeconds)
        );
    }

    public Long parseAccessToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();

        String tokenType = claims.get("tokenType", String.class);
        if (tokenType != null && !"ACCESS".equals(tokenType)) {
            throw new IllegalArgumentException("Access Token이 아닙니다.");
        }

        return Long.valueOf(claims.getSubject());
    }

    public record AccessToken(String value, Instant expiresAt) {
    }

    public record RefreshToken(String value, Instant expiresAt) {
    }
}
