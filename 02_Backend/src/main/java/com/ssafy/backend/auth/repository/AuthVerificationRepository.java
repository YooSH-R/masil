package com.ssafy.backend.auth.repository;

import com.ssafy.backend.auth.domain.AuthVerification;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public interface AuthVerificationRepository
        extends JpaRepository<AuthVerification, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<AuthVerification> findByVerificationId(UUID verificationId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<AuthVerification> findByTokenHash(String tokenHash);

    long deleteByVerificationId(UUID verificationId);

    boolean existsByPhoneNumberAndCreatedAtAfter(
            String phoneNumber,
            Instant createdAfter
    );
}
