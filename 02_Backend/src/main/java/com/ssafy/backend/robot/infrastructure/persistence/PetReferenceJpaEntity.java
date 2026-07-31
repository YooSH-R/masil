package com.ssafy.backend.robot.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "pets")
public class PetReferenceJpaEntity {

    @Id
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "deleted_at")
    private Instant deletedAt;

    protected PetReferenceJpaEntity() {
    }

    public Long getId() {
        return id;
    }
}
