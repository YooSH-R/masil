package com.ssafy.backend.robot.mqtt;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.UUID;

@Service
@ConditionalOnProperty(name = "mqtt.enabled", havingValue = "true")
public class RobotMqttApplicationService {

    private static final ZoneId DIARY_ZONE = ZoneId.of("Asia/Seoul");

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
        validateEnvelope(
                event.messageId(),
                event.messageVersion(),
                event.deviceId(),
                event.occurredAt()
        );
        if (event.eventType() == null) {
            throw new IllegalArgumentException("eventType은 필수입니다.");
        }

        RobotMqttStore.AffectionResult result = store
                .findEventResult(event.messageId())
                .orElseGet(() -> createEvent(event));
        AffectionChangedMessage response = toMessage(result);
        eventPublisher.publishEvent(new AffectionPublishEvent(response));
        return response;
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
        if (event.eventType() == RobotEventType.WALK_COMPLETED) {
            WalkCompletedData walk = requireWalkCompletedData(event);
            store.insertCompletedWalk(
                    affinity.pairingId(),
                    walk.startedAt(),
                    event.occurredAt(),
                    walk.walkDate(),
                    walk.session(),
                    "robot-images/" + event.deviceId() + "/"
                            + walk.walkDate() + "/session"
                            + walk.session() + "/"
            );
        }
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

    private WalkCompletedData requireWalkCompletedData(
            RobotEventMessage event
    ) {
        if (event.data() == null || !event.data().isObject()) {
            throw new IllegalArgumentException(
                    "WALK_COMPLETED data는 필수입니다."
            );
        }
        try {
            var startedAtNode = event.data().get("startedAt");
            var walkDateNode = event.data().get("walkDate");
            var sessionNode = event.data().get("session");
            if (startedAtNode == null
                    || walkDateNode == null
                    || sessionNode == null
                    || !startedAtNode.isTextual()
                    || !walkDateNode.isTextual()
                    || !sessionNode.isIntegralNumber()
                    || !sessionNode.canConvertToInt()) {
                throw new IllegalArgumentException(
                        "WALK_COMPLETED에는 startedAt, walkDate, session이 필요합니다."
                );
            }
            Instant startedAt = Instant.parse(startedAtNode.asText());
            LocalDate walkDate = LocalDate.parse(walkDateNode.asText());
            int session = sessionNode.intValue();
            if (session <= 0 || startedAt.isAfter(event.occurredAt())) {
                throw new IllegalArgumentException(
                        "WALK_COMPLETED 산책 시간 또는 session이 올바르지 않습니다."
                );
            }
            LocalDate expectedDate = startedAt.atZone(DIARY_ZONE)
                    .toLocalDate();
            if (!walkDate.equals(expectedDate)) {
                throw new IllegalArgumentException(
                        "walkDate는 startedAt의 한국 날짜와 같아야 합니다."
                );
            }
            return new WalkCompletedData(startedAt, walkDate, session);
        } catch (java.time.DateTimeException exception) {
            throw new IllegalArgumentException(
                    "WALK_COMPLETED 날짜 형식이 올바르지 않습니다.",
                    exception
            );
        }
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

    private record WalkCompletedData(
            Instant startedAt,
            LocalDate walkDate,
            int session
    ) {
    }
}
