package com.ssafy.backend.pet.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.MapsId;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "pet_affinity_states")
public class PetAffinityStateJpaEntity {

    @Id
    @Column(name = "pet_id")
    private Long petId;

    @MapsId
    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "pet_id")
    private PetJpaEntity pet;

    @Column(name = "affinity_score", nullable = false)
    private int affinityScore;

    @Column(name = "affinity_level", nullable = false)
    private int affinityLevel;

    @Column(nullable = false, length = 30)
    private String mood;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected PetAffinityStateJpaEntity() {
    }

    private PetAffinityStateJpaEntity(
            PetJpaEntity pet,
            int affinityScore,
            int affinityLevel,
            String mood
    ) {
        this.pet = pet;
        this.affinityScore = affinityScore;
        this.affinityLevel = affinityLevel;
        this.mood = mood;
    }

    static PetAffinityStateJpaEntity initial(PetJpaEntity pet) {
        return new PetAffinityStateJpaEntity(pet, 0, 1, "NEUTRAL");
    }

    @PrePersist
    @PreUpdate
    void updateTimestamp() {
        updatedAt = Instant.now();
    }

    public int getAffinityScore() {
        return affinityScore;
    }

    public int getAffinityLevel() {
        return affinityLevel;
    }

    public String getMood() {
        return mood;
    }
}
