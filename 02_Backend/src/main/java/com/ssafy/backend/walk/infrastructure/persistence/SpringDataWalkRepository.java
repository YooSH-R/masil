package com.ssafy.backend.walk.infrastructure.persistence;

import com.ssafy.backend.walk.domain.WalkStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface SpringDataWalkRepository extends JpaRepository<WalkJpaEntity, Long> {

    Optional<WalkJpaEntity> findByProposalId(Long proposalId);

    boolean existsByRobotPairingIdAndStatusIn(
            Long robotPairingId,
            Collection<WalkStatus> statuses
    );

    boolean existsByRobotPairingIdAndStatusAndEndedAtGreaterThan(
            Long robotPairingId,
            WalkStatus status,
            Instant endedAt
    );

    Optional<WalkJpaEntity> findFirstByRobotPairingIdAndStatusIn(
            Long robotPairingId,
            Collection<WalkStatus> statuses
    );

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select walk from WalkJpaEntity walk where walk.id = :id")
    Optional<WalkJpaEntity> findByIdForUpdate(@Param("id") Long id);

    @Query("""
            select walk
            from WalkJpaEntity walk
            where walk.id = :walkId
              and walk.robotPairingId in (
                select pairing.id
                from RobotPairingJpaEntity pairing
                where pairing.petId in (
                    select pet.id
                    from PetJpaEntity pet
                    where pet.userId = :userId
                      and pet.deletedAt is null
                )
              )
            """)
    Optional<WalkJpaEntity> findOwnedByUser(
            @Param("walkId") Long walkId,
            @Param("userId") Long userId
    );

    @Query("""
            select walk
            from WalkJpaEntity walk
            where walk.robotPairingId in (
                select pairing.id
                from RobotPairingJpaEntity pairing
                where pairing.petId in (
                    select pet.id
                    from PetJpaEntity pet
                    where pet.userId = :userId
                      and pet.deletedAt is null
                )
              )
            order by walk.createdAt desc, walk.id desc
            """)
    List<WalkJpaEntity> findOwnedFirstPage(
            @Param("userId") Long userId,
            Pageable pageable
    );

    @Query("""
            select walk
            from WalkJpaEntity walk
            where walk.robotPairingId in (
                select pairing.id
                from RobotPairingJpaEntity pairing
                where pairing.petId in (
                    select pet.id
                    from PetJpaEntity pet
                    where pet.userId = :userId
                      and pet.deletedAt is null
                )
              )
              and (
                walk.createdAt < :cursorCreatedAt
                or (walk.createdAt = :cursorCreatedAt and walk.id < :cursorId)
              )
            order by walk.createdAt desc, walk.id desc
            """)
    List<WalkJpaEntity> findOwnedPageAfter(
            @Param("userId") Long userId,
            @Param("cursorCreatedAt") Instant cursorCreatedAt,
            @Param("cursorId") Long cursorId,
            Pageable pageable
    );
}
