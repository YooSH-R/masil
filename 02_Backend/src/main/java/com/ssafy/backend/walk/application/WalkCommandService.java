package com.ssafy.backend.walk.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetRepository;
import com.ssafy.backend.robot.infrastructure.persistence.RobotJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.RobotPairingJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotPairingRepository;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotRepository;
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
    private final SpringDataRobotRepository robotRepository;
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
            SpringDataRobotRepository robotRepository,
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
        this.robotRepository = robotRepository;
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

    /**
     * 산책 세션을 만든다.
     *
     * <p>proposalId가 null이면 <b>앱에서 바로 시작한 산책</b>이다. 산책은 마실이가
     * 제안했을 때만 하는 것이 아니라 사용자가 그냥 나가서 걷기도 하므로, 제안이
     * 없어도 서버에 기록이 남아야 한다. 제안이 있어야만 세션을 만들 수 있으면
     * 그렇게 걸은 산책은 휴대폰 저장소에만 남아 다른 기기에서 영영 보이지 않는다.
     */
    @Transactional
    public CreationResult createWalk(
            Long userId,
            Long proposalId,
            Long petId,
            Long robotId
    ) {
        if (proposalId == null) {
            return createAppInitiatedWalk(userId, petId, robotId);
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

    /**
     * 제안 없이 앱에서 시작한 산책을 만든다.
     *
     * <p>제안 경로와 두 가지가 다르다.
     *
     * <p>첫째, <b>만들자마자 ACTIVE</b>다. 제안 산책은 마실이 기기가
     * {@code POST /walks/{id}/start}로 시작을 보고해 READY→ACTIVE로 넘어가지만,
     * 앱만으로 걸을 때는 그 보고자가 없다. READY에 머무르면
     * {@link #acceptsLocations}가 좌표를 전부 거부해 경로가 한 점도 안 남는다.
     * 사용자가 시작 버튼을 누른 시점이 곧 산책 시작이다.
     *
     * <p>둘째, 진행 중인 앱 산책이 이미 있으면 <b>에러 대신 그 산책을 돌려준다</b>.
     * 화면을 나갔다 다시 들어오거나 앱이 재시작되면 앱은 walkId를 잃은 채 다시
     * 만들려 한다. 그때 409를 주면 걷는 도중에 좌표를 올릴 곳이 사라진다.
     */
    private CreationResult createAppInitiatedWalk(
            Long userId,
            Long petId,
            Long robotId
    ) {
        RobotPairingJpaEntity pairing = pairingRepository
                .findActiveByPetIdForUpdate(petId)
                .filter(candidate -> candidate.getRobotId().equals(robotId))
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.WALK_RESOURCE_MISMATCH
                ));
        petRepository.findByIdAndUserIdAndDeletedAtIsNull(
                pairing.getPetId(),
                userId
        ).orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));

        var open = walkRepository.findFirstByRobotPairingIdAndStatusIn(
                pairing.getId(),
                OPEN_WALK_STATUSES
        );
        if (open.isPresent()) {
            // 마실이가 제안해서 시작한 산책이 진행 중이면 그건 기기가 끝내야 한다.
            // 앱 산책을 겹쳐 만들면 어느 쪽에 좌표가 쌓이는지 알 수 없어진다.
            if (open.get().getProposalId() != null) {
                throw new BusinessException(ErrorCode.WALK_ALREADY_ACTIVE);
            }
            return new CreationResult(WalkResult.from(open.get()), false);
        }

        Instant now = now();
        WalkJpaEntity walk = new WalkJpaEntity(pairing.getId(), null, now);
        walk.start(now);
        return new CreationResult(
                WalkResult.from(walkRepository.saveAndFlush(walk)),
                true
        );
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
        return prepareEndOf(walk, reportedAt);
    }

    /** 앱에서 시작한 산책을 앱이 끝낸다. 보고할 기기가 없으므로 앱이 종료 트리거다. */
    @Transactional
    public EndPreparation prepareEndByUser(
            Long userId,
            Long walkId,
            Instant reportedAt
    ) {
        WalkJpaEntity walk = findWalkForUpdate(walkId);
        assertUserMayEndWalk(walk, userId);
        return prepareEndOf(walk, reportedAt);
    }

    private EndPreparation prepareEndOf(WalkJpaEntity walk, Instant reportedAt) {
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
        Instant latestLocationAt = locationStore
                .findLatestRecordedAt(walk.getId())
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
        return completeEndOf(walk, robotId, deviceId, pairing.getPetId());
    }

    /**
     * 앱에서 시작한 산책을 완료 처리한다.
     *
     * <p>기기 경로와 달리 robotId·deviceId를 인증 주체가 아니라 페어링에서 찾는다.
     * 걷는 동안 마실이가 함께 있었든 아니든 산책은 그 펫의 산책이므로, 친밀도도
     * 기기 산책과 똑같이 오른다({@link WalkCompletedDomainEvent} 발행).
     */
    @Transactional
    public WalkResult completeEndByUser(Long userId, Long walkId) {
        WalkJpaEntity walk = findWalkForUpdate(walkId);
        RobotPairingJpaEntity pairing = assertUserMayEndWalk(walk, userId);
        return completeEndOf(
                walk,
                pairing.getRobotId(),
                deviceIdOf(pairing.getRobotId()),
                pairing.getPetId()
        );
    }

    private WalkResult completeEndOf(
            WalkJpaEntity walk,
            Long robotId,
            String deviceId,
            Long petId
    ) {
        Long walkId = walk.getId();
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
                petId,
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

    /**
     * 앱이 이 산책을 끝낼 수 있는지 확인하고 페어링을 돌려준다.
     *
     * <p>제안에서 시작한 산책은 거부한다. 그건 마실이 기기가 도킹을 감지해
     * 끝내는 산책이라, 앱이 먼저 끝내 버리면 아직 걷고 있는 기기가 보내는
     * 좌표와 종료 보고가 갈 곳을 잃는다.
     */
    private RobotPairingJpaEntity assertUserMayEndWalk(
            WalkJpaEntity walk,
            Long userId
    ) {
        if (walk.getProposalId() != null) {
            throw new BusinessException(ErrorCode.INVALID_WALK_STATE);
        }
        RobotPairingJpaEntity pairing = pairingRepository
                .findById(walk.getRobotPairingId())
                .orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));
        petRepository.findByIdAndUserIdAndDeletedAtIsNull(
                pairing.getPetId(),
                userId
        ).orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));
        return pairing;
    }

    /** MQTT 이벤트가 쓰는 deviceId. 로봇의 시리얼 번호가 곧 deviceId다. */
    private String deviceIdOf(Long robotId) {
        return robotRepository.findById(robotId)
                .map(RobotJpaEntity::getSerialNumber)
                .orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));
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
