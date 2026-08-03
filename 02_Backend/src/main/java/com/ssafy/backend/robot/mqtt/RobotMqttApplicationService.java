package com.ssafy.backend.robot.mqtt;

import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;

@Service
public class RobotMqttApplicationService {

    private final RobotMqttStore store;
    private final ApplicationEventPublisher eventPublisher;

    public RobotMqttApplicationService(
            RobotMqttStore store,
            ApplicationEventPublisher eventPublisher
    ) {
        this.store = store;
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public AffectionChangedMessage processEvent(
            RobotEventMessage event
    ) {
        validateEvent(event);

        RobotMqttStore.AffectionResult result = store
                .findEventResult(event.messageId())
                .orElseGet(() -> createEvent(event));
        return publishAffinityChanged(result);
    }

    @Transactional
    public AffectionChangedMessage processWalkCompletedEvent(
            RobotEventMessage event,
            long robotId,
            long petId
    ) {
        validateEvent(event);
        if (event.eventType() != RobotEventType.WALK_COMPLETED) {
            throw new IllegalArgumentException(
                    "산책 완료 처리에는 WALK_COMPLETED 이벤트가 필요합니다."
            );
        }

        RobotMqttStore.AffectionResult result = store
                .findEventResult(event.messageId(), petId)
                .orElseGet(() -> createWalkCompletedEvent(
                        event,
                        robotId,
                        petId
                ));
        return publishAffinityChanged(result);
    }

    @Transactional
    public void processHeartbeat(RobotHeartbeatMessage heartbeat) {
        validateEnvelope(
                heartbeat.messageId(),
                heartbeat.messageVersion(),
                heartbeat.deviceId(),
                heartbeat.occurredAt()
        );
        if (heartbeat.batteryLevel() < 0 || heartbeat.batteryLevel() > 100) {
            throw new IllegalArgumentException(
                    "batteryLevel은 0에서 100 사이여야 합니다."
            );
        }
        if (heartbeat.mode() == null || heartbeat.mode().isBlank()) {
            throw new IllegalArgumentException("mode는 필수입니다.");
        }
        store.upsertHeartbeat(heartbeat);
    }

    @Transactional
    public void processRequestResult(RobotRequestResultMessage result) {
        validateEnvelope(
                result.messageId(),
                result.messageVersion(),
                result.deviceId(),
                result.occurredAt()
        );
        if (result.requestId() == null || result.status() == null) {
            throw new IllegalArgumentException(
                    "requestId와 status는 필수입니다."
            );
        }
        store.updateRequestResult(result);
    }

    private RobotMqttStore.AffectionResult createEvent(
            RobotEventMessage event
    ) {
        RobotMqttStore.AffinityContext affinity =
                store.lockAffinity(event.deviceId());
        var concurrentResult = store.findEventResult(event.messageId());
        if (concurrentResult.isPresent()) {
            return concurrentResult.get();
        }
        return applyEvent(event, affinity);
    }

    private RobotMqttStore.AffectionResult createWalkCompletedEvent(
            RobotEventMessage event,
            long robotId,
            long petId
    ) {
        RobotMqttStore.AffinityContext affinity = store.lockAffinity(
                robotId,
                petId,
                event.deviceId()
        );
        var concurrentResult = store.findEventResult(
                event.messageId(),
                petId
        );
        if (concurrentResult.isPresent()) {
            return concurrentResult.get();
        }
        return applyEvent(event, affinity);
    }

    private RobotMqttStore.AffectionResult applyEvent(
            RobotEventMessage event,
            RobotMqttStore.AffinityContext affinity
    ) {
        int previousScore = affinity.currentScore();
        int currentScore = Math.max(
                0,
                Math.min(100, previousScore + event.eventType().scoreChange())
        );
        int appliedChange = currentScore - previousScore;
        int level = Math.min(5, currentScore / 20 + 1);
        String mood = moodOf(currentScore);
        Instant interactionAt = event.eventType()
                == RobotEventType.LONG_INACTIVITY
                ? null
                : event.occurredAt();

        store.updateAffinity(
                affinity.petId(),
                currentScore,
                level,
                mood,
                interactionAt
        );
        String payload = event.data() == null
                ? "{}"
                : event.data().toString();
        store.insertEvent(
                event,
                affinity.robotId(),
                payload,
                previousScore,
                appliedChange,
                currentScore
        );
        return new RobotMqttStore.AffectionResult(
                event.deviceId(),
                event.messageId(),
                previousScore,
                appliedChange,
                currentScore,
                level,
                mood,
                event.occurredAt()
        );
    }

    private AffectionChangedMessage publishAffinityChanged(
            RobotMqttStore.AffectionResult result
    ) {
        AffectionChangedMessage response = toMessage(result);
        eventPublisher.publishEvent(new AffectionPublishEvent(response));
        return response;
    }

    private AffectionChangedMessage toMessage(
            RobotMqttStore.AffectionResult result
    ) {
        return new AffectionChangedMessage(
                UUID.randomUUID(),
                "1.0",
                result.deviceId(),
                result.eventMessageId(),
                result.previousScore(),
                result.scoreChange(),
                result.currentScore(),
                result.affinityLevel(),
                result.mood(),
                Instant.now()
        );
    }

    private String moodOf(int score) {
        if (score >= 80) {
            return "HAPPY";
        }
        if (score >= 50) {
            return "FRIENDLY";
        }
        if (score >= 20) {
            return "CALM";
        }
        return "WARY";
    }

    private void validateEnvelope(
            UUID messageId,
            String version,
            String deviceId,
            Instant occurredAt
    ) {
        if (messageId == null
                || version == null || version.isBlank()
                || deviceId == null || deviceId.isBlank()
                || occurredAt == null) {
            throw new IllegalArgumentException(
                    "MQTT 공통 메시지 필드가 누락되었습니다."
            );
        }
    }

    private void validateEvent(RobotEventMessage event) {
        validateEnvelope(
                event.messageId(),
                event.messageVersion(),
                event.deviceId(),
                event.occurredAt()
        );
        if (event.eventType() == null) {
            throw new IllegalArgumentException("eventType은 필수입니다.");
        }
    }
}
