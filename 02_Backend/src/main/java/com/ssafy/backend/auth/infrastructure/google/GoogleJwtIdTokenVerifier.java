package com.ssafy.backend.auth.infrastructure.google;

import com.ssafy.backend.auth.application.port.out.GoogleIdTokenVerifier;
import com.ssafy.backend.auth.domain.SocialPrincipal;
import com.ssafy.backend.auth.domain.SocialProvider;
import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtValidationException;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

@Component
public class GoogleJwtIdTokenVerifier implements GoogleIdTokenVerifier {

    private final JwtDecoder googleJwtDecoder;

    public GoogleJwtIdTokenVerifier(
            @Qualifier("googleJwtDecoder") JwtDecoder googleJwtDecoder
    ) {
        this.googleJwtDecoder = googleJwtDecoder;
    }

    @Override
    public SocialPrincipal verify(String idToken) {
        try {
            Jwt jwt = googleJwtDecoder.decode(idToken);
            String subject = jwt.getSubject();
            if (!StringUtils.hasText(subject)) {
                throw new BusinessException(ErrorCode.INVALID_OAUTH_TOKEN);
            }

            return new SocialPrincipal(
                    SocialProvider.GOOGLE,
                    subject,
                    verifiedEmail(jwt),
                    jwt.getClaimAsString("name")
            );
        } catch (JwtValidationException exception) {
            boolean expired = exception.getErrors().stream()
                    .map(error -> error.getDescription().toLowerCase())
                    .anyMatch(description -> description.contains("expired"));
            throw new BusinessException(
                    expired ? ErrorCode.OAUTH_TOKEN_EXPIRED : ErrorCode.INVALID_OAUTH_TOKEN
            );
        } catch (JwtException exception) {
            throw new BusinessException(ErrorCode.INVALID_OAUTH_TOKEN);
        }
    }

    private String verifiedEmail(Jwt jwt) {
        Boolean emailVerified = jwt.getClaim("email_verified");
        return Boolean.TRUE.equals(emailVerified) ? jwt.getClaimAsString("email") : null;
    }
}
