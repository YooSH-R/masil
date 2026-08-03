package com.ssafy.backend.walk.infrastructure.persistence;

import com.ssafy.backend.walk.domain.WalkProposalStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

public interface SpringDataWalkProposalRepository
        extends JpaRepository<WalkProposalJpaEntity, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select proposal from WalkProposalJpaEntity proposal where proposal.id = :id")
    Optional<WalkProposalJpaEntity> findByIdForUpdate(@Param("id") Long id);

    Optional<WalkProposalJpaEntity> findFirstByRobotPairingIdAndStatusOrderByProposedAtDescIdDesc(
            Long robotPairingId,
            WalkProposalStatus status
    );

    @Query("""
            select case when count(proposal) > 0 then true else false end
            from WalkProposalJpaEntity proposal
            where proposal.robotPairingId = :robotPairingId
              and proposal.status = com.ssafy.backend.walk.domain.WalkProposalStatus.ACCEPTED
              and (proposal.expiresAt is null or proposal.expiresAt > :now)
              and not exists (
                select walk.id
                from WalkJpaEntity walk
                where walk.proposalId = proposal.id
              )
            """)
    boolean existsAcceptedWithoutWalk(
            @Param("robotPairingId") Long robotPairingId,
            @Param("now") Instant now
    );

    @Query("""
            select proposal
            from WalkProposalJpaEntity proposal
            where proposal.status = com.ssafy.backend.walk.domain.WalkProposalStatus.PENDING
              and (proposal.expiresAt is null or proposal.expiresAt > :now)
              and proposal.robotPairingId in (
                select pairing.id
                from RobotPairingJpaEntity pairing
                where pairing.unpairedAt is null
                  and pairing.petId in (
                    select pet.id
                    from PetJpaEntity pet
                    where pet.userId = :userId
                      and pet.deletedAt is null
                  )
              )
            order by proposal.proposedAt desc, proposal.id desc
            """)
    List<WalkProposalJpaEntity> findCurrentOwnedByUser(
            @Param("userId") Long userId,
            @Param("now") Instant now,
            Pageable pageable
    );

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update WalkProposalJpaEntity proposal
            set proposal.status = com.ssafy.backend.walk.domain.WalkProposalStatus.EXPIRED
            where proposal.status = com.ssafy.backend.walk.domain.WalkProposalStatus.PENDING
              and proposal.expiresAt is not null
              and proposal.expiresAt <= :now
              and proposal.robotPairingId in (
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
    int expireOwnedPendingProposals(
            @Param("userId") Long userId,
            @Param("now") Instant now
    );

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update WalkProposalJpaEntity proposal
            set proposal.status = com.ssafy.backend.walk.domain.WalkProposalStatus.EXPIRED
            where proposal.status = com.ssafy.backend.walk.domain.WalkProposalStatus.PENDING
              and proposal.expiresAt is not null
              and proposal.expiresAt <= :now
            """)
    int expireAllPendingProposals(@Param("now") Instant now);
}
