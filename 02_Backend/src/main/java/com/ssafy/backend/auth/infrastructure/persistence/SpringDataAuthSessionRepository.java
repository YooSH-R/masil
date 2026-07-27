package com.ssafy.backend.auth.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

public interface SpringDataAuthSessionRepository extends JpaRepository<AuthSessionJpaEntity, Long> {
}
