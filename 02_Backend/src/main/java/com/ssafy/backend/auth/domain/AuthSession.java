package com.ssafy.backend.auth.domain;

import com.ssafy.backend.user.domain.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "auth_sessions")
public class AuthSession {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(name = "device_id", nullable = false, length = 255)
    private String deviceId;

    @Column(name = "refresh_token_hash", nullable = false, unique = true, length = 255)
    private String refreshTokenHash;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected AuthSession() {
    }

    private AuthSession(
            User user,
            String deviceId,
            String refreshTokenHash,
            Instant expiresAt
    ) {
        this.user = user;
        this.deviceId = deviceId;
        this.refreshTokenHash = refreshTokenHash;
        this.expiresAt = expiresAt;
    }

    public static AuthSession create(
            User user,
            String deviceId,
            String refreshTokenHash,
            Instant expiresAt
    ) {
        return new AuthSession(user, deviceId, refreshTokenHash, expiresAt);
    }

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
    }

    public void rotate(String refreshTokenHash, Instant expiresAt) {
        this.refreshTokenHash = refreshTokenHash;
        this.expiresAt = expiresAt;
    }

    public void revoke() {
        this.revokedAt = Instant.now();
    }

    public boolean isUsableAt(Instant now) {
        return revokedAt == null && expiresAt.isAfter(now);
    }

    public User getUser() {
        return user;
    }

    public String getDeviceId() {
        return deviceId;
    }
}
