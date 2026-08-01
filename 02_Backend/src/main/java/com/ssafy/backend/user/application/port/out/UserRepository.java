package com.ssafy.backend.user.application.port.out;

import com.ssafy.backend.user.domain.User;

import java.util.Optional;

public interface UserRepository {

    boolean existsByNickname(String nickname);

    boolean existsByEmail(String email);

    boolean existsByPhoneNumber(String phoneNumber);

    Optional<User> findByEmail(String email);

    Optional<User> findById(Long id);

    User save(User user);
}
