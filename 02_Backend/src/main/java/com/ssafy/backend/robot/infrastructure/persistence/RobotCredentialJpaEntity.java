package com.ssafy.backend.robot.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "robot_credentials")
public class RobotCredentialJpaEntity {

    @Id
    @Column(name = "robot_id")
    private Long robotId;

    @Column(name = "qr_token_hash", nullable = false, unique = true, length = 64)
    private String qrTokenHash;

    @Column(name = "qr_token_expires_at")
    private Instant qrTokenExpiresAt;

    @Column(name = "qr_token_last_used_at")
    private Instant qrTokenLastUsedAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected RobotCredentialJpaEntity() {
    }

    public Long getRobotId() {
        return robotId;
    }

    public boolean isQrTokenExpiredAt(Instant now) {
        return qrTokenExpiresAt != null && !qrTokenExpiresAt.isAfter(now);
    }

    public void markQrTokenUsed(Instant now) {
        qrTokenLastUsedAt = now;
        updatedAt = now;
    }
}
