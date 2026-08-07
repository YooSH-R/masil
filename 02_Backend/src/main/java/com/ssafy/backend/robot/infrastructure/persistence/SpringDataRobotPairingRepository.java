package com.ssafy.backend.robot.infrastructure.persistence;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface SpringDataRobotPairingRepository
        extends JpaRepository<RobotPairingJpaEntity, Long> {

    boolean existsByRobotIdAndUnpairedAtIsNull(Long robotId);

    boolean existsByPetIdAndUnpairedAtIsNull(Long petId);

    Optional<RobotPairingJpaEntity> findByPetIdAndRobotIdAndUnpairedAtIsNull(
            Long petId,
            Long robotId
    );

    Optional<RobotPairingJpaEntity> findByRobotIdAndUnpairedAtIsNull(
            Long robotId
    );

    Optional<RobotPairingJpaEntity> findByPetIdAndUnpairedAtIsNull(Long petId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select pairing from RobotPairingJpaEntity pairing where pairing.id = :id")
    Optional<RobotPairingJpaEntity> findByIdForUpdate(@Param("id") Long id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            select pairing
            from RobotPairingJpaEntity pairing
            where pairing.robotId = :robotId
              and pairing.unpairedAt is null
            """)
    Optional<RobotPairingJpaEntity> findActiveByRobotIdForUpdate(
            @Param("robotId") Long robotId
    );

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            select pairing
            from RobotPairingJpaEntity pairing
            where pairing.petId = :petId
              and pairing.unpairedAt is null
            """)
    Optional<RobotPairingJpaEntity> findActiveByPetIdForUpdate(
            @Param("petId") Long petId
    );
}
