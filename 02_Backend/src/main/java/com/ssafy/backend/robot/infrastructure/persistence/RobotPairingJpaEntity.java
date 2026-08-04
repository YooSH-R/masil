package com.ssafy.backend.robot.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "robot_pairings")
public class RobotPairingJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "pet_id", nullable = false)
    private Long petId;

    @Column(name = "robot_id", nullable = false)
    private Long robotId;

    @Column(name = "paired_at", nullable = false)
    private Instant pairedAt;

    @Column(name = "unpaired_at")
    private Instant unpairedAt;

    protected RobotPairingJpaEntity() {
    }

    public RobotPairingJpaEntity(Long petId, Long robotId, Instant pairedAt) {
        this.petId = petId;
        this.robotId = robotId;
        this.pairedAt = pairedAt;
    }

    public Long getId() {
        return id;
    }

    public Instant getPairedAt() {
        return pairedAt;
    }

    public Long getPetId() {
        return petId;
    }

    public Long getRobotId() {
        return robotId;
    }

    public Instant getUnpairedAt() {
        return unpairedAt;
    }
}
