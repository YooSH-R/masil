package com.ssafy.backend.pet.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.time.Instant;

@Entity
@Table(
        name = "pet_creation_requests",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_pet_creation_requests_user_key",
                columnNames = {"user_id", "idempotency_key"}
        )
)
public class PetCreationRequestJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "idempotency_key", nullable = false, length = 100)
    private String idempotencyKey;

    @Column(name = "request_hash", nullable = false, length = 64)
    private String requestHash;

    @Column(name = "pet_id", nullable = false)
    private Long petId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected PetCreationRequestJpaEntity() {
    }

    public PetCreationRequestJpaEntity(
            Long userId,
            String idempotencyKey,
            String requestHash,
            Long petId
    ) {
        this.userId = userId;
        this.idempotencyKey = idempotencyKey;
        this.requestHash = requestHash;
        this.petId = petId;
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
    }

    public String getRequestHash() {
        return requestHash;
    }

    public Long getPetId() {
        return petId;
    }
}
