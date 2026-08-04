package com.ssafy.backend.robot.mqtt;

import com.ssafy.backend.walk.application.WalkProposalCreationOutcome;
import com.ssafy.backend.walk.application.WalkProposalCreationService;
import com.ssafy.backend.walk.application.WalkProposalProducerProperties;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

@Service
@ConditionalOnProperty(
        name = {"mqtt.enabled", "mqtt.request-scheduler.enabled"},
        havingValue = "true"
)
public class BehaviorRequestTransactionWorker {

    private static final Duration NON_WALK_REQUEST_TTL = Duration.ofMinutes(30);
    private static final Duration PLAY_INTERVAL = Duration.ofHours(24);

    private final RobotMqttStore store;
    private final WalkProposalCreationService walkProposalCreationService;
    private final WalkProposalProducerProperties walkProposalProperties;
    private final ApplicationEventPublisher eventPublisher;

    public BehaviorRequestTransactionWorker(
            RobotMqttStore store,
            WalkProposalCreationService walkProposalCreationService,
            WalkProposalProducerProperties walkProposalProperties,
            ApplicationEventPublisher eventPublisher
    ) {
        this.store = store;
        this.walkProposalCreationService = walkProposalCreationService;
        this.walkProposalProperties = walkProposalProperties;
        this.eventPublisher = eventPublisher;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public List<BehaviorRequestMessage> prepareCycle(Instant now) {
        store.expireRequests(now);
        List<BehaviorRequestMessage> pending = store.findPendingRequests(now);
        for (BehaviorRequestMessage request : pending) {
            publishAfterCommit(request, now);
        }
        return List.copyOf(pending);
    }

    public List<RobotMqttStore.RequestCandidate> findRequestCandidates() {
        return List.copyOf(store.findRequestCandidates());
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public List<BehaviorRequestMessage> processCandidate(
            RobotMqttStore.RequestCandidate candidate,
            Instant now
    ) {
        if (isSleeping(candidate.mode())) {
            return List.of();
        }

        List<BehaviorRequestMessage> queued = new ArrayList<>();
        addIfDue(
                queued,
                candidate,
                BehaviorRequestType.CARE_REQUEST,
                candidate.batteryLevel() != null
                        && candidate.batteryLevel() <= 20,
                "배터리가 부족해요. 충전과 관리가 필요해요.",
                now
        );
        addIfDue(
                queued,
                candidate,
                BehaviorRequestType.WALK_REQUEST,
                isOlderThan(
                        candidate.lastWalkAt(),
                        walkProposalProperties.getDueAfter(),
                        now
                ),
                "오랫동안 산책하지 않았어요. 함께 산책해요.",
                now
        );
        addIfDue(
                queued,
                candidate,
                BehaviorRequestType.PLAY_REQUEST,
                isOlderThan(candidate.lastPlayAt(), PLAY_INTERVAL, now),
                "오랫동안 놀지 않았어요. 함께 놀아 주세요.",
                now
        );
        addIfDue(
                queued,
                candidate,
                BehaviorRequestType.INTERACTION_REQUEST,
                isOlderThan(
                        candidate.lastInteractionAt(),
                        interactionInterval(candidate.affinityScore()),
                        now
                ),
                "보고 싶어요. 저와 상호작용해 주세요.",
                now
        );
        for (BehaviorRequestMessage request : queued) {
            publishAfterCommit(request, now);
        }
        return List.copyOf(queued);
    }

    Duration interactionInterval(int affinityScore) {
        if (affinityScore >= 81) {
            return Duration.ofHours(3);
        }
        if (affinityScore >= 61) {
            return Duration.ofHours(4);
        }
        if (affinityScore >= 41) {
            return Duration.ofHours(6);
        }
        if (affinityScore >= 21) {
            return Duration.ofHours(12);
        }
        return Duration.ofHours(24);
    }

    boolean isSleeping(String mode) {
        return mode != null && walkProposalProperties.getSleepingModes()
                .contains(mode.trim().toUpperCase(Locale.ROOT));
    }

    private void addIfDue(
            List<BehaviorRequestMessage> queued,
            RobotMqttStore.RequestCandidate candidate,
            BehaviorRequestType type,
            boolean due,
            String message,
            Instant now
    ) {
        if (!due) {
            return;
        }
        store.lockRequestGeneration(candidate.robotId());
        if (store.hasOpenRequest(candidate.robotId(), type)) {
            return;
        }
        if (type == BehaviorRequestType.WALK_REQUEST) {
            if (store.hasRecentRequest(
                    candidate.robotId(),
                    type,
                    now.minus(walkProposalProperties.getRetryCooldown())
            )) {
                return;
            }
            WalkProposalCreationOutcome outcome = walkProposalCreationService
                    .createIfDueForRobot(candidate.robotId(), now);
            if (outcome != WalkProposalCreationOutcome.CREATED
                    && outcome != WalkProposalCreationOutcome.ALREADY_PENDING) {
                return;
            }
        }
        Duration requestTtl = type == BehaviorRequestType.WALK_REQUEST
                ? walkProposalProperties.getProposalTtl()
                : NON_WALK_REQUEST_TTL;
        BehaviorRequestMessage request = store.createRequest(
                candidate,
                type,
                message,
                now,
                now.plus(requestTtl)
        );
        queued.add(request);
    }

    private boolean isOlderThan(
            Instant lastAt,
            Duration interval,
            Instant now
    ) {
        return lastAt == null || !lastAt.plus(interval).isAfter(now);
    }

    private void publishAfterCommit(
            BehaviorRequestMessage request,
            Instant now
    ) {
        eventPublisher.publishEvent(new BehaviorRequestPublishEvent(request, now));
    }

}
