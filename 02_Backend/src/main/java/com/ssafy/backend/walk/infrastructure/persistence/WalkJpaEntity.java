package com.ssafy.backend.walk.infrastructure.persistence;

import com.ssafy.backend.walk.domain.WalkStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.Instant;

@Entity
@Table(name = "walks")
public class WalkJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "robot_pairing_id", nullable = false)
    private Long robotPairingId;

    @Column(name = "proposal_id", unique = true)
    private Long proposalId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private WalkStatus status;

    @Column(name = "started_at")
    private Instant startedAt;

    @Column(name = "ended_at")
    private Instant endedAt;

    @Column(name = "distance_meters", precision = 10, scale = 2)
    private BigDecimal distanceMeters;

    @Column(name = "duration_seconds")
    private Integer durationSeconds;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected WalkJpaEntity() {
    }

    public WalkJpaEntity(Long robotPairingId, Long proposalId, Instant now) {
        this.robotPairingId = robotPairingId;
        this.proposalId = proposalId;
        this.status = WalkStatus.READY;
        this.createdAt = now;
        this.updatedAt = now;
    }

    public Long getId() {
        return id;
    }

    public Long getRobotPairingId() {
        return robotPairingId;
    }

    public Long getProposalId() {
        return proposalId;
    }

    public WalkStatus getStatus() {
        return status;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public Instant getEndedAt() {
        return endedAt;
    }

    public BigDecimal getDistanceMeters() {
        return distanceMeters;
    }

    public Integer getDurationSeconds() {
        return durationSeconds;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void start(Instant now) {
        status = WalkStatus.ACTIVE;
        startedAt = now;
        updatedAt = now;
    }

    public void beginProcessing(Instant now) {
        status = WalkStatus.PROCESSING;
        endedAt = now;
        updatedAt = now;
    }

    public void complete(BigDecimal distance, int duration, Instant now) {
        status = WalkStatus.COMPLETED;
        distanceMeters = distance;
        durationSeconds = duration;
        updatedAt = now;
    }

    public void refreshDistance(BigDecimal distance) {
        distanceMeters = distance;
    }
}
