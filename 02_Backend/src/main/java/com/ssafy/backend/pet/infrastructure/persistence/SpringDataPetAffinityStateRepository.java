package com.ssafy.backend.pet.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

public interface SpringDataPetAffinityStateRepository
        extends JpaRepository<PetAffinityStateJpaEntity, Long> {
}
