package com.ssafy.backend.auth.infrastructure.kakao;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

@Configuration
public class KakaoJwtConfiguration {

    private static final String KAKAO_ISSUER = "https://kauth.kakao.com";

    @Bean
    public JwtDecoder kakaoJwtDecoder(
            @Value("${auth.kakao.jwk-set-uri}") String jwkSetUri,
            @Value("${auth.kakao.app-key}") String appKey
    ) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder
                .withJwkSetUri(jwkSetUri)
                .jwsAlgorithm(SignatureAlgorithm.RS256)
                .build();
        OAuth2TokenValidator<Jwt> timestamp = new JwtTimestampValidator();
        OAuth2TokenValidator<Jwt> issuer = jwt ->
                jwt.getIssuer() != null && KAKAO_ISSUER.equals(jwt.getIssuer().toString())
                        ? OAuth2TokenValidatorResult.success()
                        : OAuth2TokenValidatorResult.failure(
                                new OAuth2Error(
                                        "invalid_token",
                                        "Invalid Kakao token issuer.",
                                        null
                                )
                        );
        OAuth2TokenValidator<Jwt> audience = jwt -> jwt.getAudience().contains(appKey)
                ? OAuth2TokenValidatorResult.success()
                : OAuth2TokenValidatorResult.failure(
                        new OAuth2Error("invalid_token", "Invalid Kakao token audience.", null)
                );
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                timestamp,
                issuer,
                audience
        ));
        return decoder;
    }
}
