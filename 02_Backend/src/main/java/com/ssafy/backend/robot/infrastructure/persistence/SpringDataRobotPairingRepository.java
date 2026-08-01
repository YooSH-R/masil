package com.ssafy.backend.robot.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface SpringDataRobotPairingRepository
        extends JpaRepository<RobotPairingJpaEntity, Long> {

    boolean existsByRobotIdAndUnpairedAtIsNull(Long robotId);

    boolean existsByPetIdAndUnpairedAtIsNull(Long petId);

    Optional<RobotPairingJpaEntity> findByPetIdAndRobotIdAndUnpairedAtIsNull(
            Long petId,
            Long robotId
    );
}
