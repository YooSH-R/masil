package com.ssafy.backend.robot.infrastructure.persistence;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import java.util.Optional;

public interface SpringDataPetReferenceRepository
        extends JpaRepository<PetReferenceJpaEntity, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<PetReferenceJpaEntity> findByIdAndUserIdAndDeletedAtIsNull(
            Long id,
            Long userId
    );
}
