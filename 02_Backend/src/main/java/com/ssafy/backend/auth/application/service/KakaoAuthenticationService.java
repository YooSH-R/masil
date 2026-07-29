package com.ssafy.backend.auth.application.service;

import com.ssafy.backend.auth.application.port.out.KakaoIdTokenVerifier;
import com.ssafy.backend.auth.application.result.SocialAuthenticationResult;
import com.ssafy.backend.auth.domain.SocialPrincipal;
import org.springframework.stereotype.Service;

@Service
public class KakaoAuthenticationService {

    private final KakaoIdTokenVerifier idTokenVerifier;
    private final SocialAuthenticationProcessor authenticationProcessor;

    public KakaoAuthenticationService(
            KakaoIdTokenVerifier idTokenVerifier,
            SocialAuthenticationProcessor authenticationProcessor
    ) {
        this.idTokenVerifier = idTokenVerifier;
        this.authenticationProcessor = authenticationProcessor;
    }

    public SocialAuthenticationResult authenticate(String idToken, String deviceId) {
        SocialPrincipal principal = idTokenVerifier.verify(idToken);
        return authenticationProcessor.process(principal, deviceId);
    }
}
