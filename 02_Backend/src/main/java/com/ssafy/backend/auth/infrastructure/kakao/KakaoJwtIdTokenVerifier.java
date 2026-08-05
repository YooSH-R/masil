package com.ssafy.backend.auth.infrastructure.kakao;

import com.ssafy.backend.auth.application.port.out.KakaoIdTokenVerifier;
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
public class KakaoJwtIdTokenVerifier implements KakaoIdTokenVerifier {

    private final JwtDecoder kakaoJwtDecoder;

    public KakaoJwtIdTokenVerifier(
            @Qualifier("kakaoJwtDecoder") JwtDecoder kakaoJwtDecoder
    ) {
        this.kakaoJwtDecoder = kakaoJwtDecoder;
    }

    @Override
    public SocialPrincipal verify(String idToken) {
        try {
            Jwt jwt = kakaoJwtDecoder.decode(idToken);
            String subject = jwt.getSubject();
            if (!StringUtils.hasText(subject)) {
                throw new BusinessException(ErrorCode.INVALID_OAUTH_TOKEN);
            }

            return new SocialPrincipal(
                    SocialProvider.KAKAO,
                    subject,
                    jwt.getClaimAsString("email"),
                    jwt.getClaimAsString("nickname")
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
}
