package com.ssafy.backend.walk.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.math.BigDecimal;
import java.time.Instant;

@Entity
@Table(
        name = "walk_locations",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_walk_locations_sequence",
                columnNames = {"walk_id", "sequence_no"}
        )
)
public class WalkLocationJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "walk_id", nullable = false)
    private Long walkId;

    @Column(name = "sequence_no", nullable = false)
    private Integer sequence;

    @Column(nullable = false, precision = 10, scale = 7)
    private BigDecimal latitude;

    @Column(nullable = false, precision = 10, scale = 7)
    private BigDecimal longitude;

    @Column(name = "accuracy_meters", precision = 8, scale = 2)
    private BigDecimal accuracy;

    @Column(name = "recorded_at", nullable = false)
    private Instant recordedAt;

    protected WalkLocationJpaEntity() {
    }
}
