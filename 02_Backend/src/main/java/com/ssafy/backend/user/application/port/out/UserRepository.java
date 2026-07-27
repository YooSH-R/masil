package com.ssafy.backend.user.application.port.out;

import com.ssafy.backend.user.domain.User;

public interface UserRepository {

    boolean existsByNickname(String nickname);

    User save(User user);
}
