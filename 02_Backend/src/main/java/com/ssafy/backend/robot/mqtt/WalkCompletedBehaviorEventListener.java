package com.ssafy.backend.robot.mqtt;

import com.ssafy.backend.walk.application.WalkCompletedDomainEvent;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.node.ObjectNode;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

@Component
class WalkCompletedBehaviorEventListener {

    private static final String MESSAGE_ID_PREFIX = "walk-completed:v1:";

    private final RobotMqttApplicationService mqttService;
    private final ObjectMapper objectMapper;

    WalkCompletedBehaviorEventListener(
            RobotMqttApplicationService mqttService,
            ObjectMapper objectMapper
    ) {
        this.mqttService = mqttService;
        this.objectMapper = objectMapper;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void handle(WalkCompletedDomainEvent event) {
        ObjectNode data = objectMapper.createObjectNode();
        data.put("walkId", event.walkId());
        data.put("durationSeconds", event.durationSeconds());
        data.put("distanceMeters", event.distanceMeters());

        mqttService.processWalkCompletedEvent(
                new RobotEventMessage(
                        messageIdFor(event.walkId()),
                        "1.0",
                        event.deviceId(),
                        event.occurredAt(),
                        RobotEventType.WALK_COMPLETED,
                        data
                ),
                event.robotId(),
                event.petId()
        );
    }

    static UUID messageIdFor(Long walkId) {
        return UUID.nameUUIDFromBytes(
                (MESSAGE_ID_PREFIX + walkId).getBytes(StandardCharsets.UTF_8)
        );
    }
}
