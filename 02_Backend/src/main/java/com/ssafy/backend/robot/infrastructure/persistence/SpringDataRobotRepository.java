package com.ssafy.backend.robot.infrastructure.persistence;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface SpringDataRobotRepository extends JpaRepository<RobotJpaEntity, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select robot from RobotJpaEntity robot where robot.id = :id")
    Optional<RobotJpaEntity> findByIdForUpdate(@Param("id") Long id);
}
