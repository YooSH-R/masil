package com.ssafy.backend.pet.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface SpringDataPetRepository extends JpaRepository<PetJpaEntity, Long> {

    Optional<PetJpaEntity> findByIdAndUserIdAndDeletedAtIsNull(
            Long id,
            Long userId
    );

    @Query("""
            select pet
            from PetJpaEntity pet
            left join fetch pet.affinityState
            where pet.id = :petId
              and pet.userId = :userId
              and pet.deletedAt is null
            """)
    Optional<PetJpaEntity> findOwnedWithAffinity(
            @Param("petId") Long petId,
            @Param("userId") Long userId
    );

    @Query("""
            select pet
            from PetJpaEntity pet
            left join fetch pet.affinityState
            where pet.userId = :userId
              and pet.deletedAt is null
            order by pet.id
            """)
    List<PetJpaEntity> findAllOwnedWithAffinity(
            @Param("userId") Long userId
    );

    @Query(
            value = """
                    SELECT
                        pairing.robot_id AS robotId,
                        COALESCE(state.online, FALSE) AS online,
                        COALESCE(state.battery_level, 0) AS batteryLevel
                    FROM robot_pairings pairing
                    LEFT JOIN robot_current_states state
                      ON state.robot_id = pairing.robot_id
                    WHERE pairing.pet_id = :petId
                      AND pairing.unpaired_at IS NULL
                    """,
            nativeQuery = true
    )
    Optional<PetRobotStatusProjection> findActiveRobotStatus(
            @Param("petId") Long petId
    );
}
