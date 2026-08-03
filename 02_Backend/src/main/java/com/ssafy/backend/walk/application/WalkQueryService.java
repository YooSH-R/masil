package com.ssafy.backend.walk.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.robot.infrastructure.persistence.RobotPairingJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotPairingRepository;
import com.ssafy.backend.walk.infrastructure.persistence.SpringDataWalkProposalRepository;
import com.ssafy.backend.walk.infrastructure.persistence.SpringDataWalkRepository;
import com.ssafy.backend.walk.infrastructure.persistence.WalkJpaEntity;
import com.ssafy.backend.walk.infrastructure.persistence.WalkProposalJpaEntity;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

@Service
public class WalkQueryService {

    private final SpringDataWalkProposalRepository proposalRepository;
    private final SpringDataWalkRepository walkRepository;
    private final SpringDataRobotPairingRepository pairingRepository;
    private final WalkDistanceCalculator distanceCalculator;
    private final WalkSummaryReadService summaryReadService;
    private final WalkCursorCodec cursorCodec;
    private final Clock clock;

    public WalkQueryService(
            SpringDataWalkProposalRepository proposalRepository,
            SpringDataWalkRepository walkRepository,
            SpringDataRobotPairingRepository pairingRepository,
            WalkDistanceCalculator distanceCalculator,
            WalkSummaryReadService summaryReadService,
            WalkCursorCodec cursorCodec,
            Clock clock
    ) {
        this.proposalRepository = proposalRepository;
        this.walkRepository = walkRepository;
        this.pairingRepository = pairingRepository;
        this.distanceCalculator = distanceCalculator;
        this.summaryReadService = summaryReadService;
        this.cursorCodec = cursorCodec;
        this.clock = clock;
    }

    @Transactional
    public Optional<WalkProposalResult> getCurrentProposal(Long userId) {
        Instant now = clock.instant();
        proposalRepository.expireOwnedPendingProposals(userId, now);
        List<WalkProposalJpaEntity> proposals = proposalRepository
                .findCurrentOwnedByUser(
                        userId,
                        now,
                        PageRequest.of(0, 1)
                );
        if (proposals.isEmpty()) {
            return Optional.empty();
        }

        WalkProposalJpaEntity proposal = proposals.get(0);
        RobotPairingJpaEntity pairing = pairingRepository
                .findById(proposal.getRobotPairingId())
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.WALK_PROPOSAL_NOT_FOUND
                ));
        return Optional.of(new WalkProposalResult(
                proposal.getId(),
                pairing.getPetId(),
                pairing.getRobotId(),
                proposal.getMessage(),
                null,
                proposal.getStatus(),
                proposal.getProposedAt(),
                proposal.getExpiresAt(),
                proposal.getRespondedAt()
        ));
    }

    @Transactional(readOnly = true)
    public WalkResult getWalk(Long userId, Long walkId) {
        return WalkResult.from(findOwnedWalk(userId, walkId));
    }

    @Transactional(readOnly = true)
    public WalkPageResult getWalks(
            Long userId,
            String cursorValue,
            int limit
    ) {
        WalkCursorCodec.Cursor cursor = cursorCodec.decode(cursorValue);
        PageRequest page = PageRequest.of(0, limit + 1);
        List<WalkJpaEntity> fetched = cursor.createdAt() == null
                ? walkRepository.findOwnedFirstPage(userId, page)
                : walkRepository.findOwnedPageAfter(
                        userId,
                        cursor.createdAt(),
                        cursor.walkId(),
                        page
                );
        boolean hasNext = fetched.size() > limit;
        List<WalkJpaEntity> pageItems = hasNext
                ? fetched.subList(0, limit)
                : fetched;
        List<WalkResult> items = pageItems.stream()
                .map(WalkResult::from)
                .toList();
        String nextCursor = hasNext
                ? cursorCodec.encode(
                        pageItems.get(pageItems.size() - 1).getCreatedAt(),
                        pageItems.get(pageItems.size() - 1).getId()
                )
                : null;
        return new WalkPageResult(items, nextCursor, hasNext);
    }

    public WalkSummaryResult getSummary(Long userId, Long walkId) {
        WalkSummaryReadService.SummarySnapshot snapshot =
                summaryReadService.load(userId, walkId);
        Integer distance = roundedDistance(snapshot);
        Integer duration = duration(snapshot);
        List<WalkLocationResult> route = snapshot.points().stream()
                .map(point -> new WalkLocationResult(
                        point.latitude(),
                        point.longitude(),
                        point.accuracy(),
                        point.sequence(),
                        point.recordedAt()
                ))
                .toList();
        return new WalkSummaryResult(
                snapshot.walkId(),
                duration,
                distance,
                route,
                snapshot.startedAt(),
                snapshot.endedAt()
        );
    }

    private WalkJpaEntity findOwnedWalk(Long userId, Long walkId) {
        return walkRepository.findOwnedByUser(walkId, userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));
    }

    private Integer roundedDistance(WalkSummaryReadService.SummarySnapshot snapshot) {
        BigDecimal distance = snapshot.distanceMeters() == null
                ? distanceCalculator.calculate(snapshot.points())
                : snapshot.distanceMeters();
        return distance.setScale(0, RoundingMode.HALF_UP).intValue();
    }

    private Integer duration(WalkSummaryReadService.SummarySnapshot snapshot) {
        if (snapshot.durationSeconds() != null) {
            return snapshot.durationSeconds();
        }
        if (snapshot.startedAt() == null) {
            return null;
        }
        Instant end = snapshot.endedAt() == null ? clock.instant() : snapshot.endedAt();
        long seconds = Duration.between(snapshot.startedAt(), end).getSeconds();
        if (seconds < 0 || seconds > Integer.MAX_VALUE) {
            return null;
        }
        return (int) seconds;
    }
}
