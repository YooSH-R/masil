package com.ssafy.backend.auth.infrastructure.persistence;

import com.ssafy.backend.auth.application.port.out.AuthSessionStore;
import org.springframework.stereotype.Repository;

import java.time.Instant;

@Repository
public class JpaAuthSessionStore implements AuthSessionStore {

    private final SpringDataAuthSessionRepository repository;

    public JpaAuthSessionStore(SpringDataAuthSessionRepository repository) {
        this.repository = repository;
    }

    @Override
    public void save(
            Long userId,
            String deviceId,
            String refreshTokenHash,
            Instant expiresAt
    ) {
        repository.save(new AuthSessionJpaEntity(
                userId,
                deviceId,
                refreshTokenHash,
                expiresAt
        ));
    }
}
