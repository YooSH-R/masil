package com.ssafy.backend.walk.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.time.Instant;

@Entity
@Table(
        name = "walk_location_batch_requests",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_walk_location_batch_request",
                columnNames = {"walk_id", "idempotency_key"}
        )
)
public class WalkLocationBatchRequestJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "walk_id", nullable = false)
    private Long walkId;

    @Column(name = "idempotency_key", nullable = false, length = 100)
    private String idempotencyKey;

    @Column(name = "request_hash", nullable = false, length = 64)
    private String requestHash;

    @Column(name = "received_count", nullable = false)
    private Integer receivedCount;

    @Column(name = "saved_count", nullable = false)
    private Integer savedCount;

    @Column(name = "rejected_count", nullable = false)
    private Integer rejectedCount;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected WalkLocationBatchRequestJpaEntity() {
    }
}
