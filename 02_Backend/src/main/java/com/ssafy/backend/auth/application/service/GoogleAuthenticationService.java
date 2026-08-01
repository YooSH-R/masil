package com.ssafy.backend.auth.application.service;

import com.ssafy.backend.auth.application.port.out.GoogleIdTokenVerifier;
import com.ssafy.backend.auth.application.result.SocialAuthenticationResult;
import com.ssafy.backend.auth.domain.SocialPrincipal;
import org.springframework.stereotype.Service;

@Service
public class GoogleAuthenticationService {

    private final GoogleIdTokenVerifier idTokenVerifier;
    private final SocialAuthenticationProcessor authenticationProcessor;

    public GoogleAuthenticationService(
            GoogleIdTokenVerifier idTokenVerifier,
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
