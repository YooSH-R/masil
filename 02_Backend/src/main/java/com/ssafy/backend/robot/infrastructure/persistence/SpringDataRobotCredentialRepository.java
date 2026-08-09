package com.ssafy.backend.robot.infrastructure.persistence;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import java.util.Optional;

public interface SpringDataRobotCredentialRepository
        extends JpaRepository<RobotCredentialJpaEntity, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<RobotCredentialJpaEntity> findByQrTokenHash(String qrTokenHash);

    Optional<RobotCredentialJpaEntity> findFirstByQrTokenHash(String qrTokenHash);
}
