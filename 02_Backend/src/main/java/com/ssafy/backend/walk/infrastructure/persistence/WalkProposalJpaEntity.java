package com.ssafy.backend.walk.infrastructure.persistence;

import com.ssafy.backend.walk.domain.WalkProposalStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "walk_proposals")
public class WalkProposalJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "robot_pairing_id", nullable = false)
    private Long robotPairingId;

    @Column(nullable = false, length = 500)
    private String message;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private WalkProposalStatus status;

    @Column(name = "proposed_at", nullable = false)
    private Instant proposedAt;

    @Column(name = "expires_at")
    private Instant expiresAt;

    @Column(name = "responded_at")
    private Instant respondedAt;

    protected WalkProposalJpaEntity() {
    }

    public WalkProposalJpaEntity(
            Long robotPairingId,
            String message,
            Instant proposedAt,
            Instant expiresAt
    ) {
        this.robotPairingId = robotPairingId;
        this.message = message;
        this.status = WalkProposalStatus.PENDING;
        this.proposedAt = proposedAt;
        this.expiresAt = expiresAt;
    }

    public Long getId() {
        return id;
    }

    public Long getRobotPairingId() {
        return robotPairingId;
    }

    public String getMessage() {
        return message;
    }

    public WalkProposalStatus getStatus() {
        return status;
    }

    public Instant getProposedAt() {
        return proposedAt;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public Instant getRespondedAt() {
        return respondedAt;
    }

    public boolean isExpiredAt(Instant now) {
        return expiresAt != null && !expiresAt.isAfter(now);
    }

    public void respond(WalkProposalStatus response, Instant now) {
        status = response;
        respondedAt = now;
    }

    public void expire() {
        status = WalkProposalStatus.EXPIRED;
        respondedAt = null;
    }
}
