package com.ssafy.backend.auth.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Optional;

public interface SpringDataAuthSessionRepository extends JpaRepository<AuthSessionJpaEntity, Long> {

    Optional<AuthSessionJpaEntity> findByRefreshTokenHash(String refreshTokenHash);

    Optional<AuthSessionJpaEntity>
    findFirstByUserIdAndDeviceIdAndRevokedAtIsNullOrderByCreatedAtDesc(
            Long userId,
            String deviceId
    );

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update AuthSessionJpaEntity session
            set session.revokedAt = :revokedAt
            where session.userId = :userId
              and session.revokedAt is null
            """)
    int revokeAllByUserId(
            @Param("userId") Long userId,
            @Param("revokedAt") Instant revokedAt
    );

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update AuthSessionJpaEntity session
            set session.revokedAt = :revokedAt
            where session.userId = :userId
              and session.id <> :sessionId
              and session.revokedAt is null
            """)
    int revokeAllByUserIdExceptSessionId(
            @Param("userId") Long userId,
            @Param("sessionId") Long sessionId,
            @Param("revokedAt") Instant revokedAt
    );
}
