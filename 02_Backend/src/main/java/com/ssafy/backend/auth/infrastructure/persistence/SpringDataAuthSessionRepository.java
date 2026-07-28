package com.ssafy.backend.auth.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface SpringDataAuthSessionRepository extends JpaRepository<AuthSessionJpaEntity, Long> {

    Optional<AuthSessionJpaEntity> findByRefreshTokenHash(String refreshTokenHash);

    Optional<AuthSessionJpaEntity>
    findFirstByUserIdAndDeviceIdAndRevokedAtIsNullOrderByCreatedAtDesc(
            Long userId,
            String deviceId
    );
}
