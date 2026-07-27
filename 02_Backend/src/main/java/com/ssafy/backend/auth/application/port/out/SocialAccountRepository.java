package com.ssafy.backend.auth.application.port.out;

import com.ssafy.backend.auth.domain.SocialPrincipal;
import com.ssafy.backend.auth.domain.SocialProvider;
import com.ssafy.backend.user.domain.User;

import java.util.Optional;

public interface SocialAccountRepository {

    Optional<User> findUser(SocialProvider provider, String providerUserId);

    boolean exists(SocialProvider provider, String providerUserId);

    void save(Long userId, SocialPrincipal principal);
}
