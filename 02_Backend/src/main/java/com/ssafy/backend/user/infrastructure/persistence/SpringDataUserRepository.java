package com.ssafy.backend.user.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

public interface SpringDataUserRepository extends JpaRepository<UserJpaEntity, Long> {

    boolean existsByNicknameAndDeletedAtIsNull(String nickname);
}
