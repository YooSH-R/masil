package com.ssafy.backend.auth.infrastructure.persistence;

import com.ssafy.backend.auth.domain.SocialProvider;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "social_signup_tickets")
public class SignupTicketJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "token_hash", nullable = false, unique = true, length = 64)
    private String tokenHash;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private SocialProvider provider;

    @Column(name = "provider_user_id", nullable = false, length = 255)
    private String providerUserId;

    @Column(length = 255)
    private String email;

    @Column(name = "suggested_nickname", length = 100)
    private String suggestedNickname;

    @Column(name = "device_id", nullable = false, length = 255)
    private String deviceId;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "used_at")
    private Instant usedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected SignupTicketJpaEntity() {
    }

    public SignupTicketJpaEntity(
            String tokenHash,
            SocialProvider provider,
            String providerUserId,
            String email,
            String suggestedNickname,
            String deviceId,
            Instant expiresAt
    ) {
        this.tokenHash = tokenHash;
        this.provider = provider;
        this.providerUserId = providerUserId;
        this.email = email;
        this.suggestedNickname = suggestedNickname;
        this.deviceId = deviceId;
        this.expiresAt = expiresAt;
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
    }

    public void markUsed(Instant usedAt) {
        this.usedAt = usedAt;
    }

    public Long getId() {
        return id;
    }

    public SocialProvider getProvider() {
        return provider;
    }

    public String getProviderUserId() {
        return providerUserId;
    }

    public String getEmail() {
        return email;
    }

    public String getSuggestedNickname() {
        return suggestedNickname;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public Instant getUsedAt() {
        return usedAt;
    }
}
