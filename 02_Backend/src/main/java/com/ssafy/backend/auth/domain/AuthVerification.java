package com.ssafy.backend.auth.domain;

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
import java.util.UUID;

@Entity
@Table(name = "auth_verifications")
public class AuthVerification {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "verification_id", nullable = false, unique = true)
    private UUID verificationId;

    @Column(name = "phone_number", nullable = false, length = 20)
    private String phoneNumber;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private VerificationPurpose purpose;

    @Column(name = "code_hash", nullable = false, length = 255)
    private String codeHash;

    @Column(name = "attempt_count", nullable = false)
    private int attemptCount;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "verified_at")
    private Instant verifiedAt;

    @Column(name = "token_hash", unique = true, length = 64)
    private String tokenHash;

    @Column(name = "token_expires_at")
    private Instant tokenExpiresAt;

    @Column(name = "used_at")
    private Instant usedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected AuthVerification() {
    }

    public static AuthVerification create(
            UUID verificationId,
            String phoneNumber,
            VerificationPurpose purpose,
            String codeHash,
            Instant expiresAt
    ) {
        AuthVerification verification = new AuthVerification();
        verification.verificationId = verificationId;
        verification.phoneNumber = phoneNumber;
        verification.purpose = purpose;
        verification.codeHash = codeHash;
        verification.expiresAt = expiresAt;
        return verification;
    }

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
    }

    public boolean canConfirmAt(Instant now, int maxAttempts) {
        return verifiedAt == null
                && usedAt == null
                && expiresAt.isAfter(now)
                && attemptCount < maxAttempts;
    }

    public void recordFailure() {
        attemptCount++;
    }

    public void confirm(String tokenHash, Instant tokenExpiresAt, Instant now) {
        this.verifiedAt = now;
        this.tokenHash = tokenHash;
        this.tokenExpiresAt = tokenExpiresAt;
    }

    public boolean canUseTokenAt(Instant now) {
        return verifiedAt != null
                && usedAt == null
                && tokenExpiresAt != null
                && tokenExpiresAt.isAfter(now);
    }

    public void markUsed(Instant now) {
        usedAt = now;
    }

    public UUID getVerificationId() {
        return verificationId;
    }

    public String getPhoneNumber() {
        return phoneNumber;
    }

    public String getCodeHash() {
        return codeHash;
    }

    public VerificationPurpose getPurpose() {
        return purpose;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }
}
