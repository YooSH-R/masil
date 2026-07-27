package com.ssafy.backend.auth.infrastructure.token;

import com.ssafy.backend.auth.application.port.out.AuthSessionStore;
import com.ssafy.backend.auth.application.port.out.AuthTokenIssuer;
import com.ssafy.backend.auth.application.port.out.OpaqueTokenCodec;
import com.ssafy.backend.auth.application.result.IssuedTokens;
import com.ssafy.backend.user.domain.User;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

@Component
public class HmacJwtAuthTokenIssuer implements AuthTokenIssuer {

    private static final String HMAC_ALGORITHM = "HmacSHA256";
    private static final String JWT_HEADER = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";

    private final AuthSessionStore authSessionStore;
    private final OpaqueTokenCodec opaqueTokenCodec;
    private final ObjectMapper objectMapper;
    private final Clock clock;
    private final Duration accessTokenTtl;
    private final Duration refreshTokenTtl;
    private final String issuer;
    private final byte[] secret;

    public HmacJwtAuthTokenIssuer(
            AuthSessionStore authSessionStore,
            OpaqueTokenCodec opaqueTokenCodec,
            ObjectMapper objectMapper,
            Clock clock,
            @Value("${auth.access-token-ttl}") Duration accessTokenTtl,
            @Value("${auth.refresh-token-ttl}") Duration refreshTokenTtl,
            @Value("${auth.jwt.issuer}") String issuer,
            @Value("${auth.jwt.secret}") String secret
    ) {
        this.authSessionStore = authSessionStore;
        this.opaqueTokenCodec = opaqueTokenCodec;
        this.objectMapper = objectMapper;
        this.clock = clock;
        this.accessTokenTtl = accessTokenTtl;
        this.refreshTokenTtl = refreshTokenTtl;
        this.issuer = issuer;
        this.secret = validateSecret(secret);
    }

    @Override
    public IssuedTokens issue(User user, String deviceId) {
        Instant issuedAt = clock.instant();
        Instant accessTokenExpiresAt = issuedAt.plus(accessTokenTtl);
        Instant refreshTokenExpiresAt = issuedAt.plus(refreshTokenTtl);
        String refreshToken = opaqueTokenCodec.generate();

        authSessionStore.save(
                user.id(),
                deviceId,
                opaqueTokenCodec.hash(refreshToken),
                refreshTokenExpiresAt
        );

        return new IssuedTokens(
                createAccessToken(user, issuedAt, accessTokenExpiresAt),
                refreshToken,
                accessTokenExpiresAt,
                refreshTokenExpiresAt
        );
    }

    private String createAccessToken(User user, Instant issuedAt, Instant expiresAt) {
        Map<String, Object> claims = new LinkedHashMap<>();
        claims.put("iss", issuer);
        claims.put("sub", user.id().toString());
        claims.put("nickname", user.nickname());
        claims.put("iat", issuedAt.getEpochSecond());
        claims.put("exp", expiresAt.getEpochSecond());

        String header = encode(JWT_HEADER.getBytes(StandardCharsets.UTF_8));
        String payload = encode(writeJson(claims));
        String unsignedToken = header + "." + payload;
        return unsignedToken + "." + encode(sign(unsignedToken));
    }

    private byte[] writeJson(Map<String, Object> claims) {
        try {
            return objectMapper.writeValueAsBytes(claims);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Access token claims could not be serialized.", exception);
        }
    }

    private byte[] sign(String value) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(new SecretKeySpec(secret, HMAC_ALGORITHM));
            return mac.doFinal(value.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("Access token could not be signed.", exception);
        }
    }

    private String encode(byte[] bytes) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private byte[] validateSecret(String secret) {
        byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
        if (bytes.length < 32) {
            throw new IllegalStateException("JWT secret must contain at least 32 bytes.");
        }
        return bytes;
    }
}
