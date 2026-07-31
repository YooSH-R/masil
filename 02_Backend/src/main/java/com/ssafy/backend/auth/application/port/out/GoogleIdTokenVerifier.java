package com.ssafy.backend.auth.application.port.out;

import com.ssafy.backend.auth.domain.SocialPrincipal;

public interface GoogleIdTokenVerifier {

    SocialPrincipal verify(String idToken);
}
