package com.ssafy.backend.walk.application;

import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetRepository;
import com.ssafy.backend.robot.infrastructure.persistence.RobotPairingJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotCurrentStateRepository;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotPairingRepository;
import com.ssafy.backend.walk.domain.WalkProposalStatus;
import com.ssafy.backend.walk.domain.WalkStatus;
import com.ssafy.backend.walk.infrastructure.persistence.SpringDataWalkProposalRepository;
import com.ssafy.backend.walk.infrastructure.persistence.SpringDataWalkRepository;
import com.ssafy.backend.walk.infrastructure.persistence.WalkProposalJpaEntity;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.Objects;
import java.util.Set;

@Service
public class WalkProposalCreationService {

    private static final String WALK_PROPOSAL_MESSAGE =
            "산책 가고 싶어요! 같이 나가요.";
    private static final Set<WalkStatus> OPEN_WALK_STATUSES = Set.of(
            WalkStatus.READY,
            WalkStatus.ACTIVE,
            WalkStatus.PROCESSING
    );

    private final SpringDataRobotPairingRepository pairingRepository;
    private final SpringDataRobotCurrentStateRepository currentStateRepository;
    private final SpringDataWalkProposalRepository proposalRepository;
    private final SpringDataWalkRepository walkRepository;
    private final SpringDataPetRepository petRepository;
    private final WalkProposalProducerProperties properties;

    public WalkProposalCreationService(
            SpringDataRobotPairingRepository pairingRepository,
            SpringDataRobotCurrentStateRepository currentStateRepository,
            SpringDataWalkProposalRepository proposalRepository,
            SpringDataWalkRepository walkRepository,
            SpringDataPetRepository petRepository,
            WalkProposalProducerProperties properties
    ) {
        this.pairingRepository = pairingRepository;
        this.currentStateRepository = currentStateRepository;
        this.proposalRepository = proposalRepository;
        this.walkRepository = walkRepository;
        this.petRepository = petRepository;
        this.properties = properties;
    }

    /**
     * Creates the proposal in the caller's transaction. The behavior-request
     * scheduler can therefore persist its WALK_REQUEST and this proposal
     * atomically without performing network I/O in the transaction.
     */
    @Transactional
    public WalkProposalCreationOutcome createIfDueForRobot(
            Long robotId,
            Instant now
    ) {
        Objects.requireNonNull(robotId, "robotId must not be null");
        Objects.requireNonNull(now, "now must not be null");

        RobotPairingJpaEntity observedPairing = pairingRepository
                .findByRobotIdAndUnpairedAtIsNull(robotId)
                .orElse(null);
        if (observedPairing == null) {
            return WalkProposalCreationOutcome.ACTIVE_PAIRING_NOT_FOUND;
        }

        var observedPending = proposalRepository
                .findFirstByRobotPairingIdAndStatusOrderByProposedAtDescIdDesc(
                        observedPairing.getId(),
                        WalkProposalStatus.PENDING
                );
        RobotPairingJpaEntity pairing = observedPending.isPresent()
                ? expirePendingWithConsistentLockOrder(
                        observedPending.get(),
                        observedPairing,
                        robotId,
                        now
                )
                : pairingRepository.findActiveByRobotIdForUpdate(robotId)
                .orElse(null);
        if (pairing == null) {
            return WalkProposalCreationOutcome.ACTIVE_PAIRING_NOT_FOUND;
        }

        String mode = currentStateRepository.findModeByRobotId(robotId)
                .orElse(null);
        if (properties.isSleeping(mode)) {
            return WalkProposalCreationOutcome.ROBOT_SLEEPING;
        }
        // 새벽에 조르지 않는다. 앱의 산책 주기 안내 문구가 이 시간대를 그대로
        // 설명하므로, 여기서 막지 않으면 화면 설명과 실제 알림이 어긋난다.
        if (!properties.isWithinActiveHours(now)) {
            return WalkProposalCreationOutcome.OUTSIDE_ACTIVE_HOURS;
        }

        Long pairingId = pairing.getId();
        var pendingProposalAfterLock = proposalRepository
                .findFirstByRobotPairingIdAndStatusOrderByProposedAtDescIdDesc(
                        pairingId,
                        WalkProposalStatus.PENDING
        );
        if (pendingProposalAfterLock.isPresent()) {
            return pendingProposalAfterLock.get().isExpiredAt(now)
                    ? WalkProposalCreationOutcome.EXPIRED_PENDING_AWAITING_CLEANUP
                    : WalkProposalCreationOutcome.ALREADY_PENDING;
        }
        if (proposalRepository.existsAcceptedWithoutWalk(pairingId, now)) {
            return WalkProposalCreationOutcome.ACCEPTED_PROPOSAL_AWAITING_WALK;
        }
        if (walkRepository.existsByRobotPairingIdAndStatusIn(
                pairingId,
                OPEN_WALK_STATUSES
        )) {
            return WalkProposalCreationOutcome.WALK_IN_PROGRESS;
        }

        // 제안 간격은 펫의 "하루 산책 횟수" 설정에서 나온다. 펫을 못 찾으면
        // 기본값(due-after)으로 떨어져, 설정 조회 실패가 제안을 막지 않게 한다.
        Duration proposalInterval = petRepository
                .findById(pairing.getPetId())
                .map(pet -> properties.intervalFor(pet.getDailyWalkCount()))
                .orElseGet(properties::getDueAfter);

        Instant recentWalkCutoff = now.minus(proposalInterval);
        if (walkRepository
                .existsByRobotPairingIdAndStatusAndEndedAtGreaterThan(
                        pairingId,
                        WalkStatus.COMPLETED,
                        recentWalkCutoff
                )) {
            return WalkProposalCreationOutcome.RECENT_WALK;
        }

        proposalRepository.saveAndFlush(new WalkProposalJpaEntity(
                pairingId,
                WALK_PROPOSAL_MESSAGE,
                now,
                now.plus(properties.getProposalTtl())
        ));
        return WalkProposalCreationOutcome.CREATED;
    }

    private RobotPairingJpaEntity expirePendingWithConsistentLockOrder(
            WalkProposalJpaEntity observedPending,
            RobotPairingJpaEntity observedPairing,
            Long robotId,
            Instant now
    ) {
        WalkProposalJpaEntity lockedProposal = proposalRepository
                .findByIdForUpdate(observedPending.getId())
                .orElse(null);
        RobotPairingJpaEntity lockedPairing = pairingRepository
                .findByIdForUpdate(observedPairing.getId())
                .orElse(null);
        if (lockedProposal == null
                || lockedPairing == null
                || lockedPairing.getUnpairedAt() != null
                || !lockedPairing.getRobotId().equals(robotId)) {
            return null;
        }
        if (lockedProposal.getStatus() == WalkProposalStatus.PENDING
                && lockedProposal.isExpiredAt(now)) {
            lockedProposal.expire();
            proposalRepository.flush();
        }
        return lockedPairing;
    }
}
