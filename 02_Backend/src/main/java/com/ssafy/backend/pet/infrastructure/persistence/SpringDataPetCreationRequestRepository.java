package com.ssafy.backend.pet.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface SpringDataPetCreationRequestRepository
        extends JpaRepository<PetCreationRequestJpaEntity, Long> {

    Optional<PetCreationRequestJpaEntity> findByUserIdAndIdempotencyKey(
            Long userId,
            String idempotencyKey
    );
}
