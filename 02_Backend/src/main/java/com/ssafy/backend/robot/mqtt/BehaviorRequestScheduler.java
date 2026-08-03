package com.ssafy.backend.robot.mqtt;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

@Component
@ConditionalOnProperty(
        name = {"mqtt.enabled", "mqtt.request-scheduler.enabled"},
        havingValue = "true"
)
public class BehaviorRequestScheduler {

    private static final Duration REQUEST_TTL = Duration.ofMinutes(30);
    private static final Duration WALK_INTERVAL = Duration.ofHours(72);
    private static final Duration PLAY_INTERVAL = Duration.ofHours(24);

    private final RobotMqttStore store;
    private final ApplicationEventPublisher eventPublisher;

    public BehaviorRequestScheduler(
            RobotMqttStore store,
            ApplicationEventPublisher eventPublisher
    ) {
        this.store = store;
        this.eventPublisher = eventPublisher;
    }

    @Scheduled(
            fixedDelayString = "${mqtt.request-scheduler.fixed-delay-ms:60000}",
            initialDelayString =
                    "${mqtt.request-scheduler.initial-delay-ms:60000}"
    )
    @Transactional
    public void publishDueRequests() {
        publishDueRequests(Instant.now());
    }

    List<BehaviorRequestMessage> publishDueRequests(Instant now) {
        store.expireRequests(now);
        List<BehaviorRequestMessage> queued = new ArrayList<>(
                store.findPendingRequests(now)
        );
        for (RobotMqttStore.RequestCandidate candidate
                : store.findRequestCandidates()) {
            if (isSleeping(candidate.mode())) {
                continue;
            }
            addIfDue(
                    queued, candidate, BehaviorRequestType.CARE_REQUEST,
                    candidate.batteryLevel() != null
                            && candidate.batteryLevel() <= 20,
                    "배터리가 부족해요. 충전과 관리가 필요해요.", now
            );
            addIfDue(
                    queued, candidate, BehaviorRequestType.WALK_REQUEST,
                    isOlderThan(candidate.lastWalkAt(), WALK_INTERVAL, now),
                    "오랫동안 산책하지 않았어요. 함께 산책해요.", now
            );
            addIfDue(
                    queued, candidate, BehaviorRequestType.PLAY_REQUEST,
                    isOlderThan(candidate.lastPlayAt(), PLAY_INTERVAL, now),
                    "오랫동안 놀지 않았어요. 함께 놀아 주세요.", now
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
        }
        for (BehaviorRequestMessage request : queued) {
            eventPublisher.publishEvent(
                    new BehaviorRequestPublishEvent(request, now)
            );
        }
        return queued;
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
        if (mode == null) {
            return false;
        }
        return switch (mode.trim().toUpperCase()) {
            case "SLEEP", "SLEEPING", "ASLEEP" -> true;
            default -> false;
        };
    }

    private void addIfDue(
            List<BehaviorRequestMessage> queued,
            RobotMqttStore.RequestCandidate candidate,
            BehaviorRequestType type,
            boolean due,
            String message,
            Instant now
    ) {
        if (!due || store.hasOpenRequest(candidate.robotId(), type)) {
            return;
        }
        BehaviorRequestMessage request = store.createRequest(
                candidate,
                type,
                message,
                now,
                now.plus(REQUEST_TTL)
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
}
