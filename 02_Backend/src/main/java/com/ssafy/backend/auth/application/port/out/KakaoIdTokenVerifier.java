package com.ssafy.backend.auth.application.port.out;

import com.ssafy.backend.auth.domain.SocialPrincipal;

public interface KakaoIdTokenVerifier {

    SocialPrincipal verify(String idToken);
}
