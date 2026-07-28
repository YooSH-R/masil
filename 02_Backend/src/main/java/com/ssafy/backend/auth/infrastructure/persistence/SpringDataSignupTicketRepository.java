package com.ssafy.backend.auth.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface SpringDataSignupTicketRepository
        extends JpaRepository<SignupTicketJpaEntity, Long> {

    Optional<SignupTicketJpaEntity> findByTokenHash(String tokenHash);
}
