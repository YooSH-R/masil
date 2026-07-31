package com.ssafy.backend.auth.application.port.out;

import com.ssafy.backend.auth.application.result.IssuedTokens;
import com.ssafy.backend.user.domain.User;

public interface AuthTokenIssuer {

    IssuedTokens issue(User user, String deviceId);
}
