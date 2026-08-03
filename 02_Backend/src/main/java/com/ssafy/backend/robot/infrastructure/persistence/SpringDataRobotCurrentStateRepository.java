package com.ssafy.backend.robot.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface SpringDataRobotCurrentStateRepository
        extends JpaRepository<RobotCurrentStateJpaEntity, Long> {

    @Query("""
            select state.mode
            from RobotCurrentStateJpaEntity state
            where state.robotId = :robotId
            """)
    Optional<String> findModeByRobotId(@Param("robotId") Long robotId);
}
