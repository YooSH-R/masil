package com.ssafy.backend.walk.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetRepository;
import com.ssafy.backend.robot.infrastructure.persistence.RobotPairingJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotPairingRepository;
import com.ssafy.backend.walk.domain.WalkProposalStatus;
import com.ssafy.backend.walk.domain.WalkStatus;
import com.ssafy.backend.walk.infrastructure.persistence.SpringDataWalkProposalRepository;
import com.ssafy.backend.walk.infrastructure.persistence.SpringDataWalkRepository;
import com.ssafy.backend.walk.infrastructure.persistence.WalkJpaEntity;
import com.ssafy.backend.walk.infrastructure.persistence.WalkLocationBatchRequestStore;
import com.ssafy.backend.walk.infrastructure.persistence.WalkLocationStore;
import com.ssafy.backend.walk.infrastructure.persistence.WalkProposalJpaEntity;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class WalkCommandService {

    public static final BigDecimal MAX_ACCURACY_METERS = new BigDecimal("50");
    private static final Duration MAX_CLOCK_SKEW = Duration.ofMinutes(5);
    private static final EnumSet<WalkStatus> OPEN_WALK_STATUSES = EnumSet.of(
            WalkStatus.READY,
            WalkStatus.ACTIVE,
            WalkStatus.PROCESSING
    );

    private final SpringDataWalkProposalRepository proposalRepository;
    private final SpringDataWalkRepository walkRepository;
    private final SpringDataRobotPairingRepository pairingRepository;
    private final SpringDataPetRepository petRepository;
    private final WalkLocationStore locationStore;
    private final WalkLocationBatchRequestStore batchRequestStore;
    private final WalkLocationRequestHasher locationRequestHasher;
    private final WalkDistanceCalculator distanceCalculator;
    private final ApplicationEventPublisher eventPublisher;
    private final Duration lateLocationGrace;
    private final Clock clock;

    public WalkCommandService(
            SpringDataWalkProposalRepository proposalRepository,
            SpringDataWalkRepository walkRepository,
            SpringDataRobotPairingRepository pairingRepository,
            SpringDataPetRepository petRepository,
            WalkLocationStore locationStore,
            WalkLocationBatchRequestStore batchRequestStore,
            WalkLocationRequestHasher locationRequestHasher,
            WalkDistanceCalculator distanceCalculator,
            ApplicationEventPublisher eventPublisher,
            @Value("${walk.location-late-grace-seconds:120}")
            long lateLocationGraceSeconds,
            Clock clock
    ) {
        if (lateLocationGraceSeconds < 0) {
            throw new IllegalArgumentException(
                    "walk.location-late-grace-seconds는 0 이상이어야 합니다."
            );
        }
        this.proposalRepository = proposalRepository;
        this.walkRepository = walkRepository;
        this.pairingRepository = pairingRepository;
        this.petRepository = petRepository;
        this.locationStore = locationStore;
        this.batchRequestStore = batchRequestStore;
        this.locationRequestHasher = locationRequestHasher;
        this.distanceCalculator = distanceCalculator;
        this.eventPublisher = eventPublisher;
        this.lateLocationGrace = Duration.ofSeconds(lateLocationGraceSeconds);
        this.clock = clock;
    }

    @Transactional
    public ProposalResponseOutcome respondToProposal(
            Long userId,
            Long proposalId,
            WalkProposalStatus response,
            Instant reportedAt
    ) {
        if (response != WalkProposalStatus.ACCEPTED
                && response != WalkProposalStatus.DECLINED) {
            throw new BusinessException(ErrorCode.INVALID_REQUEST);
        }

        WalkProposalJpaEntity proposal = proposalRepository
                .findByIdForUpdate(proposalId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.WALK_PROPOSAL_NOT_FOUND
                ));
        RobotPairingJpaEntity pairing = findActiveOwnedPairingForUpdate(
                proposal.getRobotPairingId(),
                userId,
                ErrorCode.WALK_PROPOSAL_NOT_FOUND
        );
        Instant now = now();
        if (proposal.getStatus() == WalkProposalStatus.EXPIRED) {
            return ProposalResponseOutcome.EXPIRED;
        }
        validateReportedTime(reportedAt, proposal.getProposedAt(), now);
        if (proposal.getStatus() == response) {
            return ProposalResponseOutcome.RESPONDED;
        }
        if (proposal.getStatus() != WalkProposalStatus.PENDING) {
            throw new BusinessException(ErrorCode.INVALID_WALK_STATE);
        }
        if (proposal.isExpiredAt(now)) {
            proposal.expire();
            return ProposalResponseOutcome.EXPIRED;
        }

        proposal.respond(response, now);
        return ProposalResponseOutcome.RESPONDED;
    }

    @Transactional
    public CreationResult createWalk(
            Long userId,
            Long proposalId,
            Long petId,
            Long robotId
    ) {
        WalkProposalJpaEntity proposal = proposalRepository
                .findByIdForUpdate(proposalId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.WALK_PROPOSAL_NOT_FOUND
                ));
        RobotPairingJpaEntity pairing = findActiveOwnedPairingForUpdate(
                proposal.getRobotPairingId(),
                userId,
                ErrorCode.WALK_PROPOSAL_NOT_FOUND
        );
        if (!pairing.getPetId().equals(petId)
                || !pairing.getRobotId().equals(robotId)) {
            throw new BusinessException(ErrorCode.WALK_RESOURCE_MISMATCH);
        }
        var existing = walkRepository.findByProposalId(proposalId);
        if (existing.isPresent()) {
            return new CreationResult(WalkResult.from(existing.get()), false);
        }
        if (proposal.isExpiredAt(now())) {
            throw new BusinessException(ErrorCode.WALK_PROPOSAL_EXPIRED);
        }
        if (proposal.getStatus() != WalkProposalStatus.ACCEPTED) {
            throw new BusinessException(ErrorCode.INVALID_WALK_STATE);
        }

        if (walkRepository.findFirstByRobotPairingIdAndStatusIn(
                pairing.getId(),
                OPEN_WALK_STATUSES
        ).isPresent()) {
            throw new BusinessException(ErrorCode.WALK_ALREADY_ACTIVE);
        }

        WalkJpaEntity walk = walkRepository.saveAndFlush(
                new WalkJpaEntity(pairing.getId(), proposalId, now())
        );
        return new CreationResult(WalkResult.from(walk), true);
    }

    @Transactional
    public WalkResult startWalk(Long robotId, Long walkId, Instant reportedAt) {
        WalkJpaEntity walk = findWalkForUpdate(walkId);
        assertDeviceOwnsWalk(walk, robotId, true);
        if (walk.getStatus() == WalkStatus.ACTIVE) {
            return WalkResult.from(walk);
        }
        if (walk.getStatus() != WalkStatus.READY) {
            throw new BusinessException(ErrorCode.INVALID_WALK_STATE);
        }

        Instant startedAt = normalizeLifecycleTime(reportedAt, walk.getCreatedAt());
        walk.start(startedAt);
        return WalkResult.from(walk);
    }

    @Transactional
    public WalkLocationBatchResult saveLocations(
            Long userId,
            Long walkId,
            String idempotencyKey,
            List<WalkLocationStore.Point> requestedPoints
    ) {
        WalkJpaEntity walk = findWalkForUpdate(walkId);
        assertUserOwnsWalk(walk, userId);

        List<WalkLocationStore.Point> normalizedPoints = requestedPoints.stream()
                .map(this::normalizePoint)
                .toList();
        String requestHash = locationRequestHasher.hash(normalizedPoints);
        if (idempotencyKey != null) {
            var storedRequest = batchRequestStore.find(walkId, idempotencyKey);
            if (storedRequest.isPresent()) {
                if (!storedRequest.get().requestHash().equals(requestHash)) {
                    throw new BusinessException(ErrorCode.IDEMPOTENCY_KEY_REUSED);
                }
                return storedRequest.get().result();
            }
        }
        if (!acceptsLocations(walk)) {
            throw new BusinessException(ErrorCode.INVALID_WALK_STATE);
        }

        int rejectedCount = 0;
        Map<Integer, WalkLocationStore.Point> uniquePoints = new LinkedHashMap<>();
        for (WalkLocationStore.Point normalized : normalizedPoints) {
            if (normalized.accuracy() != null
                    && normalized.accuracy().compareTo(MAX_ACCURACY_METERS) > 0) {
                rejectedCount++;
                continue;
            }
            if (walk.getEndedAt() != null
                    && normalized.recordedAt().isAfter(walk.getEndedAt())) {
                rejectedCount++;
                continue;
            }
            validateRecordedAt(normalized.recordedAt(), walk);
            WalkLocationStore.Point duplicate = uniquePoints.putIfAbsent(
                    normalized.sequence(),
                    normalized
            );
            if (duplicate != null && !duplicate.hasSamePayload(normalized)) {
                throw new BusinessException(
                        ErrorCode.WALK_LOCATION_SEQUENCE_CONFLICT
                );
            }
        }

        Map<Integer, WalkLocationStore.Point> storedPoints = locationStore
                .findBySequences(walkId, uniquePoints.keySet());
        List<WalkLocationStore.Point> newPoints = new ArrayList<>();
        for (WalkLocationStore.Point point : uniquePoints.values()) {
            WalkLocationStore.Point stored = storedPoints.get(point.sequence());
            if (stored == null) {
                newPoints.add(point);
            } else if (!stored.hasSamePayload(point)) {
                throw new BusinessException(
                        ErrorCode.WALK_LOCATION_SEQUENCE_CONFLICT
                );
            }
        }
        newPoints.sort(Comparator.comparing(WalkLocationStore.Point::sequence));
        if (!newPoints.isEmpty()) {
            locationStore.insertBatch(walkId, newPoints);
            if (walk.getStatus() == WalkStatus.COMPLETED) {
                walk.refreshDistance(distanceCalculator.calculate(
                        locationStore.findAll(walkId)
                ));
            }
        }
        WalkLocationBatchResult result = new WalkLocationBatchResult(
                walkId,
                requestedPoints.size(),
                newPoints.size(),
                rejectedCount
        );
        if (idempotencyKey != null) {
            batchRequestStore.save(
                    walkId,
                    idempotencyKey,
                    requestHash,
                    result
            );
        }
        return result;
    }

    @Transactional
    public EndPreparation prepareEnd(
            Long robotId,
            Long walkId,
            Instant reportedAt
    ) {
        WalkJpaEntity walk = findWalkForUpdate(walkId);
        assertDeviceOwnsWalk(walk, robotId, walk.getStatus() == WalkStatus.ACTIVE);
        if (walk.getStatus() == WalkStatus.COMPLETED) {
            return new EndPreparation(true, WalkResult.from(walk));
        }
        if (walk.getStatus() == WalkStatus.PROCESSING) {
            return new EndPreparation(false, WalkResult.from(walk));
        }
        if (walk.getStatus() != WalkStatus.ACTIVE) {
            throw new BusinessException(ErrorCode.INVALID_WALK_STATE);
        }

        Instant endedAt = normalizeLifecycleTime(reportedAt, walk.getStartedAt());
        Instant latestLocationAt = locationStore.findLatestRecordedAt(walkId)
                .orElse(endedAt);
        if (latestLocationAt.isAfter(endedAt)) {
            endedAt = latestLocationAt;
        }
        walk.beginProcessing(endedAt);
        return new EndPreparation(false, WalkResult.from(walk));
    }

    @Transactional
    public WalkResult completeEnd(
            Long robotId,
            String deviceId,
            Long walkId
    ) {
        WalkJpaEntity walk = findWalkForUpdate(walkId);
        RobotPairingJpaEntity pairing = assertDeviceOwnsWalk(
                walk,
                robotId,
                false
        );
        if (walk.getStatus() == WalkStatus.COMPLETED) {
            return WalkResult.from(walk);
        }
        if (walk.getStatus() != WalkStatus.PROCESSING) {
            throw new BusinessException(ErrorCode.INVALID_WALK_STATE);
        }

        long duration = Duration.between(
                walk.getStartedAt(),
                walk.getEndedAt()
        ).getSeconds();
        if (duration < 0 || duration > Integer.MAX_VALUE) {
            throw new BusinessException(ErrorCode.INVALID_REQUEST);
        }
        BigDecimal currentDistance = distanceCalculator.calculate(
                locationStore.findAll(walkId)
        );
        walk.complete(currentDistance, (int) duration, now());
        WalkResult result = WalkResult.from(walk);
        eventPublisher.publishEvent(new WalkCompletedDomainEvent(
                walkId,
                robotId,
                pairing.getPetId(),
                deviceId,
                walk.getEndedAt(),
                result.durationSeconds(),
                result.distanceMeters()
        ));
        return result;
    }

    private WalkJpaEntity findWalkForUpdate(Long walkId) {
        return walkRepository.findByIdForUpdate(walkId)
                .orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));
    }

    private RobotPairingJpaEntity findActiveOwnedPairingForUpdate(
            Long pairingId,
            Long userId,
            ErrorCode notFoundCode
    ) {
        RobotPairingJpaEntity pairing = pairingRepository
                .findByIdForUpdate(pairingId)
                .filter(candidate -> candidate.getUnpairedAt() == null)
                .orElseThrow(() -> new BusinessException(notFoundCode));
        petRepository.findByIdAndUserIdAndDeletedAtIsNull(
                pairing.getPetId(),
                userId
        ).orElseThrow(() -> new BusinessException(notFoundCode));
        return pairing;
    }

    private void assertUserOwnsWalk(WalkJpaEntity walk, Long userId) {
        RobotPairingJpaEntity pairing = pairingRepository
                .findById(walk.getRobotPairingId())
                .orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));
        petRepository.findByIdAndUserIdAndDeletedAtIsNull(
                pairing.getPetId(),
                userId
        ).orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));
    }

    private RobotPairingJpaEntity assertDeviceOwnsWalk(
            WalkJpaEntity walk,
            Long robotId,
            boolean requireActivePairing
    ) {
        RobotPairingJpaEntity pairing = pairingRepository
                .findById(walk.getRobotPairingId())
                .filter(candidate -> candidate.getRobotId().equals(robotId))
                .orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));
        if (requireActivePairing && pairing.getUnpairedAt() != null) {
            throw new BusinessException(ErrorCode.WALK_NOT_FOUND);
        }
        return pairing;
    }

    private boolean acceptsLocations(WalkJpaEntity walk) {
        if (walk.getStatus() == WalkStatus.ACTIVE) {
            return true;
        }
        if (walk.getStatus() != WalkStatus.PROCESSING
                && walk.getStatus() != WalkStatus.COMPLETED) {
            return false;
        }
        return walk.getEndedAt() != null
                && now().isBefore(walk.getUpdatedAt().plus(lateLocationGrace));
    }

    private Instant normalizeLifecycleTime(Instant reportedAt, Instant lowerBound) {
        Instant now = now();
        Instant normalized = reportedAt == null ? now : truncate(reportedAt);
        if (normalized.isAfter(now.plus(MAX_CLOCK_SKEW))
                || normalized.isBefore(lowerBound.minus(MAX_CLOCK_SKEW))) {
            throw new BusinessException(ErrorCode.INVALID_REQUEST);
        }
        return normalized.isBefore(lowerBound) ? lowerBound : normalized;
    }

    private void validateReportedTime(
            Instant reportedAt,
            Instant lowerBound,
            Instant now
    ) {
        if (reportedAt == null
                || reportedAt.isAfter(now.plus(MAX_CLOCK_SKEW))
                || reportedAt.isBefore(lowerBound.minus(MAX_CLOCK_SKEW))) {
            throw new BusinessException(ErrorCode.INVALID_REQUEST);
        }
    }

    private void validateRecordedAt(Instant recordedAt, WalkJpaEntity walk) {
        Instant now = now();
        if (recordedAt.isAfter(now.plus(MAX_CLOCK_SKEW))
                || recordedAt.isBefore(walk.getStartedAt().minus(MAX_CLOCK_SKEW))) {
            throw new BusinessException(ErrorCode.INVALID_REQUEST);
        }
    }

    private WalkLocationStore.Point normalizePoint(WalkLocationStore.Point point) {
        return new WalkLocationStore.Point(
                point.latitude().setScale(7, RoundingMode.HALF_UP),
                point.longitude().setScale(7, RoundingMode.HALF_UP),
                point.accuracy() == null
                        ? null
                        : point.accuracy().setScale(2, RoundingMode.HALF_UP),
                point.sequence(),
                truncate(point.recordedAt())
        );
    }

    private Instant now() {
        return truncate(clock.instant());
    }

    private Instant truncate(Instant instant) {
        return instant.truncatedTo(ChronoUnit.MICROS);
    }

    public record CreationResult(WalkResult walk, boolean created) {
    }

    public record EndPreparation(boolean completed, WalkResult walk) {
    }

    public enum ProposalResponseOutcome {
        RESPONDED,
        EXPIRED
    }
}
