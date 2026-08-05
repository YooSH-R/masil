package com.ssafy.backend.robot.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "robot_current_states")
public class RobotCurrentStateJpaEntity {

    @Id
    @Column(name = "robot_id")
    private Long robotId;

    @Column(nullable = false)
    private boolean online;

    @Column(nullable = false, length = 30)
    private String mode;

    @Column(name = "battery_level", nullable = false)
    private int batteryLevel;

    @Column(nullable = false)
    private boolean docked;

    @Column(name = "last_seen_at")
    private Instant lastSeenAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected RobotCurrentStateJpaEntity() {
    }
}
