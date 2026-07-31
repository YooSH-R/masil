package com.ssafy.backend.robot.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "robots")
public class RobotJpaEntity {

    @Id
    private Long id;

    @Column(name = "serial_number", nullable = false, unique = true, length = 100)
    private String serialNumber;

    @Column(name = "model_name", nullable = false, length = 100)
    private String modelName;

    @Column(name = "firmware_version", length = 50)
    private String firmwareVersion;

    @Column(name = "owner_user_id")
    private Long ownerUserId;

    @Column(name = "ownership_claimed_at")
    private Instant ownershipClaimedAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected RobotJpaEntity() {
    }

    public Long getId() {
        return id;
    }

    public String getSerialNumber() {
        return serialNumber;
    }

    public String getModelName() {
        return modelName;
    }

    public String getFirmwareVersion() {
        return firmwareVersion;
    }

    public boolean isOwnedByAnotherUser(Long userId) {
        return ownerUserId != null && !ownerUserId.equals(userId);
    }

    public void claimOwnershipIfUnowned(Long userId, Instant now) {
        if (ownerUserId == null) {
            ownerUserId = userId;
            ownershipClaimedAt = now;
            updatedAt = now;
        }
    }

}
