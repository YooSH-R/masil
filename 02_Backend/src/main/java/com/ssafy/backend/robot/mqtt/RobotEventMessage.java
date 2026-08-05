package com.ssafy.backend.robot.mqtt;

import tools.jackson.databind.JsonNode;

import java.time.Instant;
import java.util.UUID;

public record RobotEventMessage(
        UUID messageId,
        String messageVersion,
        String deviceId,
        Instant occurredAt,
        RobotEventType eventType,
        JsonNode data
) {
}
